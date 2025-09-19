;; MindDAO Peer Support - Mental Health Community Support System
;; Manages support groups, peer assistance, crisis intervention, and resource sharing

;; ===================================
;; CONSTANTS AND ERROR CODES
;; ===================================

(define-constant CONTRACT_DEPLOYER tx-sender)
(define-constant SYSTEM_NAME "MindDAO Peer Support")

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_MEMBER (err u201))
(define-constant ERR_GROUP_NOT_FOUND (err u202))
(define-constant ERR_ALREADY_MEMBER (err u203))
(define-constant ERR_GROUP_FULL (err u204))
(define-constant ERR_REQUEST_NOT_FOUND (err u205))
(define-constant ERR_ALREADY_RESPONDED (err u206))
(define-constant ERR_INVALID_STATUS (err u207))
(define-constant ERR_CRISIS_COOLDOWN (err u208))
(define-constant ERR_INVALID_RATING (err u209))
(define-constant ERR_RESOURCE_NOT_FOUND (err u210))

;; Support group types
(define-constant GROUP_TYPE_GENERAL u1)
(define-constant GROUP_TYPE_ANXIETY u2)
(define-constant GROUP_TYPE_DEPRESSION u3)
(define-constant GROUP_TYPE_TRAUMA u4)
(define-constant GROUP_TYPE_ADDICTION u5)
(define-constant GROUP_TYPE_GRIEF u6)

;; Support request urgency levels
(define-constant URGENCY_LOW u1)
(define-constant URGENCY_MEDIUM u2)
(define-constant URGENCY_HIGH u3)
(define-constant URGENCY_CRISIS u4)

;; Group settings
(define-constant MAX_GROUP_SIZE u20)
(define-constant MIN_GROUP_SIZE u3)
(define-constant CRISIS_COOLDOWN_PERIOD u144) ;; 24 hours in blocks

;; ===================================
;; DATA VARIABLES
;; ===================================

(define-data-var total-groups uint u0)
(define-data-var total-support-requests uint u0)
(define-data-var total-resources uint u0)
(define-data-var next-group-id uint u1)
(define-data-var next-request-id uint u1)
(define-data-var next-resource-id uint u1)

;; ===================================
;; DATA MAPS
;; ===================================

;; Member profiles for peer support
(define-map peer-profiles principal {
  display-name: (string-ascii 50),
  bio: (string-ascii 200),
  support-areas: (list 10 uint), ;; Areas they can provide support in
  seeking-support: (list 10 uint), ;; Areas they need support in
  joined-at: uint,
  is-active: bool,
  privacy-level: uint, ;; 1=public, 2=semi-private, 3=anonymous
  crisis-requests-count: uint,
  last-crisis-request: uint,
  reputation-score: uint,
  total-help-provided: uint,
  total-help-received: uint
})

;; Support groups
(define-map support-groups uint {
  name: (string-ascii 100),
  description: (string-ascii 300),
  group-type: uint,
  facilitator: principal,
  created-at: uint,
  is-active: bool,
  is-private: bool,
  member-count: uint,
  max-members: uint,
  meeting-schedule: (string-ascii 100), ;; When group meets
  group-rules: (string-ascii 500)
})

;; Group memberships
(define-map group-memberships { group-id: uint, member: principal } {
  joined-at: uint,
  role: uint, ;; 1=member, 2=moderator, 3=facilitator
  is-active: bool,
  contribution-score: uint
})

;; Peer support requests
(define-map support-requests uint {
  requester: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  support-type: uint, ;; Group type they need support for
  urgency-level: uint,
  requested-at: uint,
  is-anonymous: bool,
  is-resolved: bool,
  response-count: uint
})

;; Support responses
(define-map support-responses { request-id: uint, responder: principal } {
  response: (string-ascii 300),
  responded-at: uint,
  is-helpful: (optional bool), ;; Requester can mark as helpful
  rating: (optional uint) ;; 1-5 rating from requester
})

;; Crisis interventions
(define-map crisis-interventions uint {
  person-in-crisis: principal,
  reported-by: principal,
  description: (string-ascii 300),
  urgency-level: uint,
  reported-at: uint,
  status: uint, ;; 1=open, 2=responding, 3=resolved
  assigned-supporters: (list 5 principal),
  professional-contacted: bool,
  resolution-notes: (optional (string-ascii 300))
})

;; Mental health resources
(define-map resources uint {
  title: (string-ascii 100),
  description: (string-ascii 300),
  resource-type: uint, ;; 1=article, 2=video, 3=tool, 4=hotline
  url: (string-ascii 200),
  tags: (list 10 uint), ;; Related support areas
  contributor: principal,
  created-at: uint,
  is-verified: bool,
  rating: uint, ;; Average rating * 100
  rating-count: uint
})

;; Resource ratings
(define-map resource-ratings { resource-id: uint, rater: principal } {
  rating: uint, ;; 1-5
  review: (optional (string-ascii 200)),
  rated-at: uint
})

;; Peer connections (for direct support)
(define-map peer-connections { supporter: principal, supportee: principal } {
  connected-at: uint,
  connection-type: uint, ;; 1=mentor, 2=buddy, 3=accountability
  is-active: bool,
  mutual-rating: (optional uint),
  interaction-count: uint,
  last-interaction: uint
})

;; Safe space violations and moderation
(define-map violations uint {
  reported-user: principal,
  reported-by: principal,
  violation-type: uint, ;; 1=harassment, 2=spam, 3=unsafe-advice
  description: (string-ascii 300),
  reported-at: uint,
  status: uint, ;; 1=pending, 2=reviewed, 3=resolved
  moderator-notes: (optional (string-ascii 200))
})

;; ===================================
;; PUBLIC FUNCTIONS
;; ===================================

;; Create peer support profile
(define-public (create-profile 
  (display-name (string-ascii 50)) 
  (bio (string-ascii 200))
  (support-areas (list 10 uint))
  (seeking-support (list 10 uint))
  (privacy-level uint)
)
  (let (
    (existing-profile (map-get? peer-profiles tx-sender))
  )
    (asserts! (is-none existing-profile) ERR_ALREADY_MEMBER)
    (asserts! (and (>= privacy-level u1) (<= privacy-level u3)) ERR_INVALID_STATUS)
    
    (map-set peer-profiles tx-sender {
      display-name: display-name,
      bio: bio,
      support-areas: support-areas,
      seeking-support: seeking-support,
      joined-at: stacks-block-height,
      is-active: true,
      privacy-level: privacy-level,
      crisis-requests-count: u0,
      last-crisis-request: u0,
      reputation-score: u100, ;; Start with base score
      total-help-provided: u0,
      total-help-received: u0
    })
    
    (ok true)
  )
)

;; Create a support group
(define-public (create-support-group 
  (name (string-ascii 100))
  (description (string-ascii 300))
  (group-type uint)
  (is-private bool)
  (max-members uint)
  (meeting-schedule (string-ascii 100))
  (group-rules (string-ascii 500))
)
  (let (
    (profile (unwrap! (map-get? peer-profiles tx-sender) ERR_NOT_MEMBER))
    (group-id (var-get next-group-id))
  )
    (asserts! (get is-active profile) ERR_NOT_MEMBER)
    (asserts! (and (>= group-type u1) (<= group-type u6)) ERR_INVALID_STATUS)
    (asserts! (and (>= max-members MIN_GROUP_SIZE) (<= max-members MAX_GROUP_SIZE)) ERR_GROUP_FULL)
    
    ;; Create group
    (map-set support-groups group-id {
      name: name,
      description: description,
      group-type: group-type,
      facilitator: tx-sender,
      created-at: stacks-block-height,
      is-active: true,
      is-private: is-private,
      member-count: u1,
      max-members: max-members,
      meeting-schedule: meeting-schedule,
      group-rules: group-rules
    })
    
    ;; Add creator as facilitator
    (map-set group-memberships { group-id: group-id, member: tx-sender } {
      joined-at: stacks-block-height,
      role: u3, ;; facilitator
      is-active: true,
      contribution-score: u0
    })
    
    (var-set next-group-id (+ group-id u1))
    (var-set total-groups (+ (var-get total-groups) u1))
    
    (ok group-id)
  )
)

;; Join a support group
(define-public (join-support-group (group-id uint))
  (let (
    (profile (unwrap! (map-get? peer-profiles tx-sender) ERR_NOT_MEMBER))
    (group (unwrap! (map-get? support-groups group-id) ERR_GROUP_NOT_FOUND))
    (membership-key { group-id: group-id, member: tx-sender })
    (existing-membership (map-get? group-memberships membership-key))
  )
    (asserts! (get is-active profile) ERR_NOT_MEMBER)
    (asserts! (get is-active group) ERR_GROUP_NOT_FOUND)
    (asserts! (is-none existing-membership) ERR_ALREADY_MEMBER)
    (asserts! (< (get member-count group) (get max-members group)) ERR_GROUP_FULL)
    
    ;; Add member to group
    (map-set group-memberships membership-key {
      joined-at: stacks-block-height,
      role: u1, ;; regular member
      is-active: true,
      contribution-score: u0
    })
    
    ;; Update group member count
    (map-set support-groups group-id (merge group {
      member-count: (+ (get member-count group) u1)
    }))
    
    (ok true)
  )
)

;; Submit a support request
(define-public (submit-support-request
  (title (string-ascii 100))
  (description (string-ascii 500))
  (support-type uint)
  (urgency-level uint)
  (is-anonymous bool)
)
  (let (
    (profile (unwrap! (map-get? peer-profiles tx-sender) ERR_NOT_MEMBER))
    (request-id (var-get next-request-id))
  )
    (asserts! (get is-active profile) ERR_NOT_MEMBER)
    (asserts! (and (>= support-type u1) (<= support-type u6)) ERR_INVALID_STATUS)
    (asserts! (and (>= urgency-level u1) (<= urgency-level u4)) ERR_INVALID_STATUS)
    
    ;; Check crisis cooldown for high urgency requests
    (if (is-eq urgency-level URGENCY_CRISIS)
      (asserts! 
        (>= (- stacks-block-height (get last-crisis-request profile)) CRISIS_COOLDOWN_PERIOD) 
        ERR_CRISIS_COOLDOWN
      )
      true
    )
    
    ;; Create support request
    (map-set support-requests request-id {
      requester: tx-sender,
      title: title,
      description: description,
      support-type: support-type,
      urgency-level: urgency-level,
      requested-at: stacks-block-height,
      is-anonymous: is-anonymous,
      is-resolved: false,
      response-count: u0
    })
    
    ;; Update profile if crisis request
    (if (is-eq urgency-level URGENCY_CRISIS)
      (map-set peer-profiles tx-sender (merge profile {
        crisis-requests-count: (+ (get crisis-requests-count profile) u1),
        last-crisis-request: stacks-block-height
      }))
      true
    )
    
    (var-set next-request-id (+ request-id u1))
    (var-set total-support-requests (+ (var-get total-support-requests) u1))
    
    (ok request-id)
  )
)

;; Respond to a support request
(define-public (respond-to-request (request-id uint) (response (string-ascii 300)))
  (let (
    (profile (unwrap! (map-get? peer-profiles tx-sender) ERR_NOT_MEMBER))
    (request (unwrap! (map-get? support-requests request-id) ERR_REQUEST_NOT_FOUND))
    (response-key { request-id: request-id, responder: tx-sender })
    (existing-response (map-get? support-responses response-key))
  )
    (asserts! (get is-active profile) ERR_NOT_MEMBER)
    (asserts! (not (get is-resolved request)) ERR_INVALID_STATUS)
    (asserts! (is-none existing-response) ERR_ALREADY_RESPONDED)
    (asserts! (not (is-eq tx-sender (get requester request))) ERR_UNAUTHORIZED)
    
    ;; Record response
    (map-set support-responses response-key {
      response: response,
      responded-at: stacks-block-height,
      is-helpful: none,
      rating: none
    })
    
    ;; Update request response count
    (map-set support-requests request-id (merge request {
      response-count: (+ (get response-count request) u1)
    }))
    
    ;; Update responder's help provided count
    (map-set peer-profiles tx-sender (merge profile {
      total-help-provided: (+ (get total-help-provided profile) u1)
    }))
    
    (ok true)
  )
)

;; Rate a support response (by original requester)
(define-public (rate-response (request-id uint) (responder principal) (rating uint))
  (let (
    (request (unwrap! (map-get? support-requests request-id) ERR_REQUEST_NOT_FOUND))
    (response-key { request-id: request-id, responder: responder })
    (response (unwrap! (map-get? support-responses response-key) ERR_REQUEST_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get requester request)) ERR_UNAUTHORIZED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
    (asserts! (is-none (get rating response)) ERR_ALREADY_RESPONDED)
    
    ;; Update response rating
    (map-set support-responses response-key (merge response {
      is-helpful: (some (>= rating u3)),
      rating: (some rating)
    }))
    
    ;; Update responder's reputation
    (let ((responder-profile (unwrap! (map-get? peer-profiles responder) ERR_NOT_MEMBER)))
      (map-set peer-profiles responder (merge responder-profile {
        reputation-score: (+ (get reputation-score responder-profile) (* rating u10))
      }))
    )
    
    (ok true)
  )
)

;; Report crisis situation
(define-public (report-crisis 
  (person-in-crisis principal)
  (description (string-ascii 300))
  (urgency-level uint)
)
  (let (
    (profile (unwrap! (map-get? peer-profiles tx-sender) ERR_NOT_MEMBER))
    (crisis-id (var-get next-request-id))
  )
    (asserts! (get is-active profile) ERR_NOT_MEMBER)
    (asserts! (and (>= urgency-level u3) (<= urgency-level u4)) ERR_INVALID_STATUS)
    
    ;; Create crisis intervention record
    (map-set crisis-interventions crisis-id {
      person-in-crisis: person-in-crisis,
      reported-by: tx-sender,
      description: description,
      urgency-level: urgency-level,
      reported-at: stacks-block-height,
      status: u1, ;; open
      assigned-supporters: (list tx-sender),
      professional-contacted: false,
      resolution-notes: none
    })
    
    (var-set next-request-id (+ crisis-id u1))
    
    (ok crisis-id)
  )
)

;; Add mental health resource
(define-public (add-resource
  (title (string-ascii 100))
  (description (string-ascii 300))
  (resource-type uint)
  (url (string-ascii 200))
  (tags (list 10 uint))
)
  (let (
    (profile (unwrap! (map-get? peer-profiles tx-sender) ERR_NOT_MEMBER))
    (resource-id (var-get next-resource-id))
  )
    (asserts! (get is-active profile) ERR_NOT_MEMBER)
    (asserts! (and (>= resource-type u1) (<= resource-type u4)) ERR_INVALID_STATUS)
    
    ;; Create resource
    (map-set resources resource-id {
      title: title,
      description: description,
      resource-type: resource-type,
      url: url,
      tags: tags,
      contributor: tx-sender,
      created-at: stacks-block-height,
      is-verified: false,
      rating: u0,
      rating-count: u0
    })
    
    (var-set next-resource-id (+ resource-id u1))
    (var-set total-resources (+ (var-get total-resources) u1))
    
    (ok resource-id)
  )
)

;; ===================================
;; READ-ONLY FUNCTIONS
;; ===================================

;; Get peer profile
(define-read-only (get-peer-profile (member principal))
  (map-get? peer-profiles member)
)

;; Get support group info
(define-read-only (get-support-group (group-id uint))
  (map-get? support-groups group-id)
)

;; Get group membership
(define-read-only (get-group-membership (group-id uint) (member principal))
  (map-get? group-memberships { group-id: group-id, member: member })
)

;; Get support request
(define-read-only (get-support-request (request-id uint))
  (map-get? support-requests request-id)
)

;; Get support response
(define-read-only (get-support-response (request-id uint) (responder principal))
  (map-get? support-responses { request-id: request-id, responder: responder })
)

;; Get crisis intervention details
(define-read-only (get-crisis-intervention (crisis-id uint))
  (map-get? crisis-interventions crisis-id)
)

;; Get resource details
(define-read-only (get-resource (resource-id uint))
  (map-get? resources resource-id)
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-groups: (var-get total-groups),
    total-support-requests: (var-get total-support-requests),
    total-resources: (var-get total-resources),
    next-group-id: (var-get next-group-id),
    next-request-id: (var-get next-request-id),
    next-resource-id: (var-get next-resource-id)
  }
)

;; Check if member can make crisis request
(define-read-only (can-request-crisis (member principal))
  (match (map-get? peer-profiles member)
    profile
      (and 
        (get is-active profile)
        (>= (- stacks-block-height (get last-crisis-request profile)) CRISIS_COOLDOWN_PERIOD)
      )
    false
  )
)

;; Get member reputation level
(define-read-only (get-reputation-level (member principal))
  (match (map-get? peer-profiles member)
    profile
      (let ((score (get reputation-score profile)))
        (if (>= score u500) u5 ;; Expert
          (if (>= score u300) u4 ;; Advanced
            (if (>= score u200) u3 ;; Intermediate
              (if (>= score u100) u2 ;; Basic
                u1 ;; Newcomer
              )
            )
          )
        )
      )
    u0 ;; Not a member
  )
)
