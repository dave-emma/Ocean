# 🌊 Ocean Cleanup Rewards — Smart Contract

A Clarity smart contract deployed on the Stacks blockchain that incentivizes ocean cleanup volunteers by tracking their cleanup missions and rewarding them with eco-tokens.

---

## Overview

This contract allows volunteers to register, create cleanup missions with plastic collection targets, log their progress, and claim token rewards upon mission completion. An administrator manages the reward pool and contract ownership.

---

## Features

- **Volunteer registration** — onboard new volunteers with a starting profile
- **Mission management** — create time-bound cleanup missions with plastic targets and ocean zones
- **Progress tracking** — log plastic collected per mission, earn eco-scores and guardian ranks
- **Badge system** — earn zone-specific achievement badges on mission completion
- **Token rewards** — claim eco-tokens from the reward pool for completed missions
- **Admin controls** — deposit funds and transfer contract ownership

---

## Contract Architecture

### Data Stores

| Store | Type | Description |
|---|---|---|
| `contract-guardian` | Variable | Current contract administrator |
| `eco-fund` | Variable | Available token balance for rewards |
| `volunteer-count` | Variable | Total registered volunteers |
| `ocean-volunteers` | Map | Volunteer profiles (score, rank, sessions, tokens) |
| `cleanup-missions` | Map | Mission records keyed by volunteer + mission number |
| `eco-badges` | Map | List of earned badge strings per volunteer (max 10) |

### Volunteer Profile

```clarity
{
  eco-score: uint,           ;; Cumulative score from all cleanups
  cleanup-sessions: uint,    ;; Total number of cleanup reports submitted
  ocean-guardian-rank: uint, ;; Rank derived from eco-score (score / 1000 + 1)
  last-contribution: uint,   ;; Block timestamp of last cleanup activity
  tokens-collected: uint,    ;; Total eco-tokens claimed
  active-missions: uint      ;; Most recent mission number
}
```

### Mission Record

```clarity
{
  plastic-target: uint,           ;; Goal in kg/units of plastic
  plastic-collected: uint,        ;; Running total collected
  mission-expiry: uint,           ;; Deadline timestamp
  mission-success: bool,          ;; Whether the target was met
  eco-tokens: uint,               ;; Reward tokens claimable on success
  ocean-zone: (string-ascii 20)   ;; Name of the cleanup zone
}
```

---

## Public Functions

### `register-volunteer`
Registers the caller as a new volunteer. Each address can only register once.

```clarity
(register-volunteer) → (ok true)
```

---

### `launch-cleanup-mission`
Creates a new cleanup mission for the calling volunteer.

```clarity
(launch-cleanup-mission plastic-goal deadline-time zone-name)
  → (ok mission-number)
```

| Parameter | Type | Description |
|---|---|---|
| `plastic-goal` | `uint` | Plastic collection target (must be > 0) |
| `deadline-time` | `uint` | Unix timestamp for mission expiry (must be in the future) |
| `zone-name` | `string-ascii 20` | Name of the ocean zone |

---

### `report-cleanup`
Logs a cleanup activity for a specific mission. Updates the volunteer's eco-score and session count. Awards a badge if the mission target is met.

```clarity
(report-cleanup mission-number plastic-amount) → (ok { collected, complete, eco-score })
```

| Parameter | Type | Description |
|---|---|---|
| `mission-number` | `uint` | Target mission to report against |
| `plastic-amount` | `uint` | Amount of plastic collected in this session |

---

### `claim-eco-tokens`
Claims the token reward for a successfully completed mission. Transfers tokens from the eco-fund to the volunteer's collected total.

```clarity
(claim-eco-tokens mission-number) → (ok token-amount)
```

---

### `deposit-eco-fund` *(admin only)*
Adds tokens to the reward pool. Only callable by the `contract-guardian`.

```clarity
(deposit-eco-fund token-amount) → (ok true)
```

---

### `transfer-guardianship` *(admin only)*
Transfers contract ownership to a new principal.

```clarity
(transfer-guardianship new-guardian) → (ok true)
```

---

## Read-Only Functions

| Function | Description |
|---|---|
| `get-volunteer-info(volunteer)` | Returns the full volunteer profile |
| `get-mission-info(volunteer, mission-number)` | Returns the full mission record |
| `get-volunteer-badges(volunteer)` | Returns the list of earned badges |
| `get-platform-stats` | Returns total volunteer count and current eco-fund balance |

---

## Reward Calculations

| Metric | Formula |
|---|---|
| Mission eco-tokens | `(plastic-target / 100) * 100` |
| Score boost per report | `plastic-amount * 10` |
| Guardian rank | `(eco-score / 1000) + 1` |

---

## Error Codes

| Code | Constant | Cause |
|---|---|---|
| `u100` | `ERR-NOT-AUTHORIZED` | Caller is not the contract guardian |
| `u101` | `ERR-VOLUNTEER-REGISTERED` | Address is already registered |
| `u102` | `ERR-NO-VOLUNTEER-DATA` | Caller is not a registered volunteer |
| `u103` | `ERR-INVALID-TARGET` | Invalid goal, deadline, zone, or mission state |
| `u104` | `ERR-POOL-EMPTY` | Eco-fund has insufficient tokens for reward |
| `u105` | `ERR-INVALID-AMOUNT` | Deposit amount must be greater than zero |
| `u106` | `ERR-INVALID-CLEANUP` | Plastic amount reported must be greater than zero |
| `u107` | `ERR-INVALID-MISSION` | Mission number does not exist for this volunteer |

---

## Usage Example

```clarity
;; 1. Register as a volunteer
(contract-call? .ocean-cleanup register-volunteer)

;; 2. Start a mission targeting 500 units of plastic in "Pacific Gyre"
(contract-call? .ocean-cleanup launch-cleanup-mission u500 u1800000000 "Pacific Gyre")

;; 3. Report collected plastic against mission 1
(contract-call? .ocean-cleanup report-cleanup u1 u300)

;; 4. Report more plastic to complete the mission
(contract-call? .ocean-cleanup report-cleanup u1 u200)

;; 5. Claim your eco-token reward
(contract-call? .ocean-cleanup claim-eco-tokens u1)
```

---

## Deployment Notes

- The deploying address automatically becomes the `contract-guardian`.
- The eco-fund starts at `0` — the guardian must call `deposit-eco-fund` before volunteers can claim rewards.
- Badges are stored as a list capped at **10 entries** per volunteer. Once the cap is reached, `grant-eco-badge` will panic due to `unwrap-panic` on `as-max-len?`. Consider adding a guard before deploying to production.
- Block tracking uses `stacks-block-height`, a **Clarity 3** built-in. If you need Clarity 1/2 compatibility, replace it with `block-height` and set `clarity_version = 2` in your `Clarinet.toml`. Either way, `deadline-time` passed to `launch-cleanup-mission` must be a **block number**, not a Unix timestamp — e.g. `(+ stacks-block-height u144)` for ~24 hours at 10 min/block.