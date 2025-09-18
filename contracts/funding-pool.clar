;; MindDAO Funding Pool - Collective Mental Health Support Funding
;; Manages community contributions, funding proposals, and emergency fund allocation

;; ===================================
;; CONSTANTS AND ERROR CODES
;; ===================================

(define-constant CONTRACT_DEPLOYER tx-sender)
(define-constant DAO_NAME "MindDAO Funding Pool")

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_MEMBER (err u101))
(define-constant ERR_ALREADY_MEMBER (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u104))
(define-constant ERR_ALREADY_VOTED (err u105))
(define-constant ERR_VOTING_CLOSED (err u106))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_EMERGENCY_COOLDOWN (err u109))
(define-constant ERR_TRANSFER_FAILED (err u110))

;; Proposal types
(define-constant PROPOSAL_TYPE_GENERAL u1)
(define-constant PROPOSAL_TYPE_EMERGENCY u2)
(define-constant PROPOSAL_TYPE_THERAPY u3)
(define-constant PROPOSAL_TYPE_RESEARCH u4)
(define-constant PROPOSAL_TYPE_COMMUNITY u5)

;; Funding thresholds
(define-constant MIN_CONTRIBUTION u10000) ;; 0.01 STX in microSTX
(define-constant MIN_PROPOSAL_AMOUNT u50000) ;; 0.05 STX minimum request
(define-constant EMERGENCY_THRESHOLD u500000) ;; 0.5 STX emergency threshold
(define-constant VOTING_PERIOD u144) ;; blocks (~24 hours)
(define-constant QUORUM_PERCENTAGE u51) ;; 51% quorum required

;; ===================================
;; DATA VARIABLES
;; ===================================

(define-data-var total-pool uint u0)
(define-data-var total-members uint u0)
(define-data-var next-proposal-id uint u1)
(define-data-var emergency-fund uint u0)
(define-data-var last-emergency-disbursement uint u0)
(define-data-var dao-fee-percentage uint u5) ;; 5% fee for DAO operations

;; ===================================
;; DATA MAPS
;; ===================================

;; Member management
(define-map members principal {
  total-contributed: uint,
  contribution-count: uint,
  member-since: uint,
  is-active: bool,
  emergency-requests-count: uint,
  last-emergency-request: uint
})

;; Funding proposals
(define-map proposals uint {
  proposer: principal,
  proposal-type: uint,
  title: (string-ascii 100),
  description: (string-ascii 500),
  amount-requested: uint,
  recipient: principal,
  created-at: uint,
  voting-ends-at: uint,
  votes-for: uint,
  votes-against: uint,
  total-votes: uint,
  executed: bool,
  approved: bool
})

;; Vote tracking
(define-map votes { proposal-id: uint, voter: principal } {
  vote: bool, ;; true = for, false = against
  voted-at: uint
})

;; Emergency fund requests
(define-map emergency-requests uint {
  requester: principal,
  amount: uint,
  reason: (string-ascii 200),
  requested-at: uint,
  approved: bool,
  disbursed: bool,
  approver: (optional principal)
})

;; Member contributions tracking
(define-map contributions { member: principal, contribution-id: uint } {
  amount: uint,
  contributed-at: uint,
  purpose: (string-ascii 100)
})

;; Disbursement history
(define-map disbursements uint {
  recipient: principal,
  amount: uint,
  purpose: (string-ascii 100),
  proposal-id: (optional uint),
  disbursed-at: uint,
  disbursed-by: principal
})

;; ===================================
;; PUBLIC FUNCTIONS
;; ===================================

;; Join the DAO by making an initial contribution
(define-public (join-dao (contribution-amount uint))
  (let (
    (current-member (map-get? members tx-sender))
  )
    (asserts! (is-none current-member) ERR_ALREADY_MEMBER)
    (asserts! (>= contribution-amount MIN_CONTRIBUTION) ERR_INVALID_AMOUNT)
    
    ;; Accept the contribution
    (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
    
    ;; Register member
    (map-set members tx-sender {
      total-contributed: contribution-amount,
      contribution-count: u1,
      member-since: stacks-block-height,
      is-active: true,
      emergency-requests-count: u0,
      last-emergency-request: u0
    })
    
    ;; Update pool totals
    (var-set total-pool (+ (var-get total-pool) contribution-amount))
    (var-set total-members (+ (var-get total-members) u1))
    
    ;; Allocate 10% to emergency fund
    (let ((emergency-allocation (/ contribution-amount u10)))
      (var-set emergency-fund (+ (var-get emergency-fund) emergency-allocation))
    )
    
    (ok true)
  )
)

;; Make additional contribution to the pool
(define-public (contribute (amount uint) (purpose (string-ascii 100)))
  (let (
    (member-info (unwrap! (map-get? members tx-sender) ERR_NOT_MEMBER))
    (contribution-id (get contribution-count member-info))
  )
    (asserts! (>= amount MIN_CONTRIBUTION) ERR_INVALID_AMOUNT)
    (asserts! (get is-active member-info) ERR_NOT_MEMBER)
    
    ;; Accept the contribution
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update member record
    (map-set members tx-sender (merge member-info {
      total-contributed: (+ (get total-contributed member-info) amount),
      contribution-count: (+ contribution-id u1)
    }))
    
    ;; Record contribution
    (map-set contributions { member: tx-sender, contribution-id: (+ contribution-id u1) } {
      amount: amount,
      contributed-at: stacks-block-height,
      purpose: purpose
    })
    
    ;; Update pool total
    (var-set total-pool (+ (var-get total-pool) amount))
    
    ;; Allocate 10% to emergency fund
    (let ((emergency-allocation (/ amount u10)))
      (var-set emergency-fund (+ (var-get emergency-fund) emergency-allocation))
    )
    
    (ok true)
  )
)

;; Submit a funding proposal
(define-public (submit-proposal 
  (proposal-type uint) 
  (title (string-ascii 100)) 
  (description (string-ascii 500)) 
  (amount-requested uint)
  (recipient principal)
)
  (let (
    (member-info (unwrap! (map-get? members tx-sender) ERR_NOT_MEMBER))
    (proposal-id (var-get next-proposal-id))
  )
    (asserts! (get is-active member-info) ERR_NOT_MEMBER)
    (asserts! (>= amount-requested MIN_PROPOSAL_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (<= amount-requested (var-get total-pool)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (and (>= proposal-type u1) (<= proposal-type u5)) ERR_INVALID_AMOUNT)
    
    ;; Create proposal
    (map-set proposals proposal-id {
      proposer: tx-sender,
      proposal-type: proposal-type,
      title: title,
      description: description,
      amount-requested: amount-requested,
      recipient: recipient,
      created-at: stacks-block-height,
      voting-ends-at: (+ stacks-block-height VOTING_PERIOD),
      votes-for: u0,
      votes-against: u0,
      total-votes: u0,
      executed: false,
      approved: false
    })
    
    ;; Increment proposal counter
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Vote on a funding proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    (member-info (unwrap! (map-get? members tx-sender) ERR_NOT_MEMBER))
    (vote-key { proposal-id: proposal-id, voter: tx-sender })
  )
    (asserts! (get is-active member-info) ERR_NOT_MEMBER)
    (asserts! (is-none (map-get? votes vote-key)) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get voting-ends-at proposal)) ERR_VOTING_CLOSED)
    
    ;; Record vote
    (map-set votes vote-key {
      vote: vote-for,
      voted-at: stacks-block-height
    })
    
    ;; Update proposal vote counts
    (if vote-for
      (map-set proposals proposal-id (merge proposal {
        votes-for: (+ (get votes-for proposal) u1),
        total-votes: (+ (get total-votes proposal) u1)
      }))
      (map-set proposals proposal-id (merge proposal {
        votes-against: (+ (get votes-against proposal) u1),
        total-votes: (+ (get total-votes proposal) u1)
      }))
    )
    
    (ok true)
  )
)

;; Execute an approved proposal
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    (total-members-count (var-get total-members))
    (required-quorum (/ (* total-members-count QUORUM_PERCENTAGE) u100))
  )
    (asserts! (> stacks-block-height (get voting-ends-at proposal)) ERR_VOTING_CLOSED)
    (asserts! (not (get executed proposal)) ERR_PROPOSAL_NOT_APPROVED)
    (asserts! (>= (get total-votes proposal) required-quorum) ERR_PROPOSAL_NOT_APPROVED)
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR_PROPOSAL_NOT_APPROVED)
    
    ;; Execute the funding
    (try! (as-contract (stx-transfer? (get amount-requested proposal) tx-sender (get recipient proposal))))
    
    ;; Mark proposal as executed
    (map-set proposals proposal-id (merge proposal {
      executed: true,
      approved: true
    }))
    
    ;; Update pool total
    (var-set total-pool (- (var-get total-pool) (get amount-requested proposal)))
    
    ;; Record disbursement
    (map-set disbursements proposal-id {
      recipient: (get recipient proposal),
      amount: (get amount-requested proposal),
      purpose: (get title proposal),
      proposal-id: (some proposal-id),
      disbursed-at: stacks-block-height,
      disbursed-by: tx-sender
    })
    
    (ok true)
  )
)

;; Request emergency funding (fast-tracked for mental health crises)
(define-public (request-emergency-funding (amount uint) (reason (string-ascii 200)))
  (let (
    (member-info (unwrap! (map-get? members tx-sender) ERR_NOT_MEMBER))
    (last-request (get last-emergency-request member-info))
    (request-id (var-get next-proposal-id))
  )
    (asserts! (get is-active member-info) ERR_NOT_MEMBER)
    (asserts! (<= amount EMERGENCY_THRESHOLD) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get emergency-fund)) ERR_INSUFFICIENT_FUNDS)
    ;; Prevent spam - 24 hours between emergency requests
    (asserts! (>= (- stacks-block-height last-request) u144) ERR_EMERGENCY_COOLDOWN)
    
    ;; Create emergency request
    (map-set emergency-requests request-id {
      requester: tx-sender,
      amount: amount,
      reason: reason,
      requested-at: stacks-block-height,
      approved: false,
      disbursed: false,
      approver: none
    })
    
    ;; Update member record
    (map-set members tx-sender (merge member-info {
      emergency-requests-count: (+ (get emergency-requests-count member-info) u1),
      last-emergency-request: stacks-block-height
    }))
    
    (var-set next-proposal-id (+ request-id u1))
    
    (ok request-id)
  )
)

;; Approve emergency funding (by senior members)
(define-public (approve-emergency-funding (request-id uint))
  (let (
    (request (unwrap! (map-get? emergency-requests request-id) ERR_PROPOSAL_NOT_FOUND))
    (member-info (unwrap! (map-get? members tx-sender) ERR_NOT_MEMBER))
  )
    (asserts! (get is-active member-info) ERR_NOT_MEMBER)
    ;; Only senior members (contributed > 1 STX) can approve emergency requests
    (asserts! (>= (get total-contributed member-info) u1000000) ERR_UNAUTHORIZED)
    (asserts! (not (get approved request)) ERR_PROPOSAL_NOT_APPROVED)
    
    ;; Approve and disburse immediately
    (try! (as-contract (stx-transfer? (get amount request) tx-sender (get requester request))))
    
    ;; Mark as approved and disbursed
    (map-set emergency-requests request-id (merge request {
      approved: true,
      disbursed: true,
      approver: (some tx-sender)
    }))
    
    ;; Update emergency fund
    (var-set emergency-fund (- (var-get emergency-fund) (get amount request)))
    (var-set last-emergency-disbursement stacks-block-height)
    
    (ok true)
  )
)

;; ===================================
;; READ-ONLY FUNCTIONS
;; ===================================

;; Get member information
(define-read-only (get-member-info (member principal))
  (map-get? members member)
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; Get emergency request details
(define-read-only (get-emergency-request (request-id uint))
  (map-get? emergency-requests request-id)
)

;; Get vote information
(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

;; Get pool statistics
(define-read-only (get-pool-stats)
  {
    total-pool: (var-get total-pool),
    total-members: (var-get total-members),
    emergency-fund: (var-get emergency-fund),
    next-proposal-id: (var-get next-proposal-id),
    last-emergency-disbursement: (var-get last-emergency-disbursement)
  }
)

;; Check if member can make emergency request
(define-read-only (can-request-emergency (member principal))
  (match (map-get? members member)
    member-info 
      (and 
        (get is-active member-info)
        (>= (- stacks-block-height (get last-emergency-request member-info)) u144)
      )
    false
  )
)

;; Get member's contribution history
(define-read-only (get-contribution (member principal) (contribution-id uint))
  (map-get? contributions { member: member, contribution-id: contribution-id })
)

;; Calculate voting power (based on contribution)
(define-read-only (get-voting-power (member principal))
  (match (map-get? members member)
    member-info (get total-contributed member-info)
    u0
  )
)
