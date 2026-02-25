;; Ocean - Cleanup Rewards Smart Contract

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VOLUNTEER-REGISTERED (err u101))
(define-constant ERR-NO-VOLUNTEER-DATA (err u102))
(define-constant ERR-INVALID-TARGET (err u103))
(define-constant ERR-POOL-EMPTY (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-CLEANUP (err u106))
(define-constant ERR-INVALID-MISSION (err u107))

;; Data variables
(define-data-var contract-guardian principal tx-sender)
(define-data-var eco-fund uint u0)
(define-data-var volunteer-count uint u0)

;; Data maps
(define-map ocean-volunteers
    principal
    {
        eco-score: uint,
        cleanup-sessions: uint,
        ocean-guardian-rank: uint,
        last-contribution: uint,
        tokens-collected: uint,
        active-missions: uint
    }
)

(define-map cleanup-missions
    {volunteer: principal, mission-number: uint}
    {
        plastic-target: uint,
        plastic-collected: uint,
        mission-expiry: uint,
        mission-success: bool,
        eco-tokens: uint,
        ocean-zone: (string-ascii 20)
    }
)

(define-map eco-badges
    principal
    (list 10 (string-ascii 30))
)

;; Public functions

;; Volunteer registration
(define-public (register-volunteer)
    (let
        ((new-volunteer tx-sender))
        (asserts! (is-none (map-get? ocean-volunteers new-volunteer)) (err ERR-VOLUNTEER-REGISTERED))
        (map-set ocean-volunteers
            new-volunteer
            {
                eco-score: u0,
                cleanup-sessions: u0,
                ocean-guardian-rank: u1,
                last-contribution: stacks-block-height,
                tokens-collected: u0,
                active-missions: u0
            }
        )
        (var-set volunteer-count (+ (var-get volunteer-count) u1))
        (ok true)
    )
)

;; Start cleanup mission
(define-public (launch-cleanup-mission (plastic-goal uint) (deadline-time uint) (zone-name (string-ascii 20)))
    (let
        ((volunteer tx-sender)
         (volunteer-info (unwrap! (map-get? ocean-volunteers volunteer) ERR-NO-VOLUNTEER-DATA))
         (mission-number (+ (get active-missions volunteer-info) u1)))
        
        (asserts! (> plastic-goal u0) ERR-INVALID-TARGET)
        (asserts! (> deadline-time stacks-block-height) ERR-INVALID-TARGET)
        (asserts! (<= (len zone-name) u20) ERR-INVALID-TARGET)
        
        (map-set cleanup-missions
            {volunteer: volunteer, mission-number: mission-number}
            {
                plastic-target: plastic-goal,
                plastic-collected: u0,
                mission-expiry: deadline-time,
                mission-success: false,
                eco-tokens: (compute-eco-reward plastic-goal),
                ocean-zone: zone-name
            }
        )
        
        (map-set ocean-volunteers
            volunteer
            (merge volunteer-info {active-missions: mission-number})
        )
        (ok mission-number)
    )
)

;; Log cleanup activity
(define-public (report-cleanup (mission-number uint) (plastic-amount uint))
    (let
        ((volunteer tx-sender)
         (volunteer-info (unwrap! (map-get? ocean-volunteers volunteer) ERR-NO-VOLUNTEER-DATA)))
        
        (asserts! (> plastic-amount u0) ERR-INVALID-CLEANUP)
        (asserts! (<= mission-number (get active-missions volunteer-info)) ERR-INVALID-MISSION)
        
        (let
            ((mission-info (unwrap! (map-get? cleanup-missions {volunteer: volunteer, mission-number: mission-number}) ERR-INVALID-MISSION))
             (current-time stacks-block-height))
            
            (asserts! (not (get mission-success mission-info)) ERR-INVALID-TARGET)
            (asserts! (<= current-time (get mission-expiry mission-info)) ERR-INVALID-TARGET)
            
            (let
                ((new-collected (+ (get plastic-collected mission-info) plastic-amount))
                 (mission-complete (>= new-collected (get plastic-target mission-info)))
                 (score-boost (compute-score-boost plastic-amount))
                 (new-eco-score (+ (get eco-score volunteer-info) score-boost)))
                
                ;; Update mission
                (map-set cleanup-missions
                    {volunteer: volunteer, mission-number: mission-number}
                    (merge mission-info {
                        plastic-collected: new-collected,
                        mission-success: mission-complete
                    })
                )
                
                ;; Update volunteer
                (map-set ocean-volunteers
                    volunteer
                    (merge volunteer-info {
                        eco-score: new-eco-score,
                        cleanup-sessions: (+ (get cleanup-sessions volunteer-info) u1),
                        last-contribution: current-time,
                        ocean-guardian-rank: (compute-guardian-rank new-eco-score)
                    })
                )
                
                ;; Award badge if complete
                (if mission-complete
                    (grant-eco-badge volunteer (concat "Cleaned " (get ocean-zone mission-info)))
                    true
                )
                
                (ok {
                    collected: new-collected,
                    complete: mission-complete,
                    eco-score: new-eco-score
                })
            )
        )
    )
)

;; Claim eco rewards
(define-public (claim-eco-tokens (mission-number uint))
    (let
        ((volunteer tx-sender)
         (volunteer-info (unwrap! (map-get? ocean-volunteers volunteer) ERR-NO-VOLUNTEER-DATA)))
        
        (asserts! (<= mission-number (get active-missions volunteer-info)) ERR-INVALID-MISSION)
        
        (let
            ((mission-info (unwrap! (map-get? cleanup-missions {volunteer: volunteer, mission-number: mission-number}) ERR-INVALID-MISSION)))
            
            (asserts! (get mission-success mission-info) ERR-INVALID-TARGET)
            (asserts! (>= (var-get eco-fund) (get eco-tokens mission-info)) ERR-POOL-EMPTY)
            
            ;; Distribute tokens
            (var-set eco-fund (- (var-get eco-fund) (get eco-tokens mission-info)))
            (map-set ocean-volunteers
                volunteer
                (merge volunteer-info {
                    tokens-collected: (+ (get tokens-collected volunteer-info) (get eco-tokens mission-info))
                })
            )
            
            (ok (get eco-tokens mission-info))
        )
    )
)

;; Private functions

(define-private (compute-eco-reward (plastic-goal uint))
    (let
        ((base-rate u100))
        (* base-rate (/ plastic-goal u100))
    )
)

(define-private (compute-score-boost (plastic-amount uint))
    (* plastic-amount u10)
)

(define-private (compute-guardian-rank (total-score uint))
    (+ u1 (/ total-score u1000))
)

(define-private (grant-eco-badge (volunteer principal) (badge-title (string-ascii 30)))
    (let
        ((current-badges (default-to (list) (map-get? eco-badges volunteer))))
        (map-set eco-badges
            volunteer
            (unwrap-panic (as-max-len? (append current-badges badge-title) u10))
        )
    )
)

;; Read-only functions

(define-read-only (get-volunteer-info (volunteer principal))
    (map-get? ocean-volunteers volunteer)
)

(define-read-only (get-mission-info (volunteer principal) (mission-number uint))
    (map-get? cleanup-missions {volunteer: volunteer, mission-number: mission-number})
)

(define-read-only (get-volunteer-badges (volunteer principal))
    (map-get? eco-badges volunteer)
)

(define-read-only (get-platform-stats)
    {
        total-volunteers: (var-get volunteer-count),
        eco-fund-balance: (var-get eco-fund)
    }
)

;; Administrative functions

(define-public (deposit-eco-fund (token-amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-guardian)) ERR-NOT-AUTHORIZED)
        (asserts! (> token-amount u0) ERR-INVALID-AMOUNT)
        (var-set eco-fund (+ (var-get eco-fund) token-amount))
        (ok true)
    )
)

(define-public (transfer-guardianship (new-guardian principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-guardian)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-guardian (var-get contract-guardian))) ERR-NOT-AUTHORIZED)
        (var-set contract-guardian new-guardian)
        (ok true)
    )
)