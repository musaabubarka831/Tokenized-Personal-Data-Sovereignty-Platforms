;; Consent Management Contract
;; Controls data usage permissions and consent preferences

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_ALREADY_EXISTS (err u202))
(define-constant ERR_INVALID_INPUT (err u203))
(define-constant ERR_CONSENT_EXPIRED (err u204))

;; Consent purposes
(define-constant PURPOSE_MARKETING u1)
(define-constant PURPOSE_ANALYTICS u2)
(define-constant PURPOSE_PERSONALIZATION u3)
(define-constant PURPOSE_RESEARCH u4)
(define-constant PURPOSE_SHARING u5)

;; Data structures
(define-map consent-records
  { user: principal, purpose: uint, data-processor: principal }
  {
    granted: bool,
    granted-at: uint,
    expires-at: (optional uint),
    conditions: (string-ascii 200),
    revoked-at: (optional uint)
  }
)

(define-map global-preferences
  { user: principal }
  {
    default-consent: bool,
    require-explicit: bool,
    auto-expire-days: (optional uint),
    notification-preference: (string-ascii 50)
  }
)

(define-map consent-history
  { user: principal, timestamp: uint }
  {
    action: (string-ascii 20),
    purpose: uint,
    processor: principal,
    details: (string-ascii 100)
  }
)

;; Public functions

;; Set global consent preferences
(define-public (set-global-preferences
    (default-consent bool)
    (require-explicit bool)
    (auto-expire-days (optional uint))
    (notification-preference (string-ascii 50)))
  (begin
    (asserts! (> (len notification-preference) u0) ERR_INVALID_INPUT)

    (map-set global-preferences
      { user: tx-sender }
      {
        default-consent: default-consent,
        require-explicit: require-explicit,
        auto-expire-days: auto-expire-days,
        notification-preference: notification-preference
      }
    )

    ;; Log preference change
    (map-set consent-history
      { user: tx-sender, timestamp: block-height }
      {
        action: "preferences-updated",
        purpose: u0,
        processor: tx-sender,
        details: "Global preferences modified"
      }
    )
    (ok true)
  )
)

;; Grant consent for specific purpose and processor
(define-public (grant-consent
    (purpose uint)
    (data-processor principal)
    (expires-at (optional uint))
    (conditions (string-ascii 200)))
  (begin
    (asserts! (and (>= purpose u1) (<= purpose u5)) ERR_INVALID_INPUT)
    (asserts! (> (len conditions) u0) ERR_INVALID_INPUT)

    ;; Check if consent already exists
    (asserts! (is-none (map-get? consent-records
      { user: tx-sender, purpose: purpose, data-processor: data-processor }))
      ERR_ALREADY_EXISTS)

    ;; Validate expiration date
    (match expires-at
      exp-date (asserts! (> exp-date block-height) ERR_INVALID_INPUT)
      true
    )

    (map-set consent-records
      { user: tx-sender, purpose: purpose, data-processor: data-processor }
      {
        granted: true,
        granted-at: block-height,
        expires-at: expires-at,
        conditions: conditions,
        revoked-at: none
      }
    )

    ;; Log consent grant
    (map-set consent-history
      { user: tx-sender, timestamp: block-height }
      {
        action: "consent-granted",
        purpose: purpose,
        processor: data-processor,
        details: "Consent granted with conditions"
      }
    )
    (ok true)
  )
)

;; Revoke consent
(define-public (revoke-consent (purpose uint) (data-processor principal))
  (let
    (
      (consent (unwrap! (map-get? consent-records
        { user: tx-sender, purpose: purpose, data-processor: data-processor })
        ERR_NOT_FOUND))
    )
    (asserts! (get granted consent) ERR_INVALID_INPUT)
    (asserts! (is-none (get revoked-at consent)) ERR_INVALID_INPUT)

    (map-set consent-records
      { user: tx-sender, purpose: purpose, data-processor: data-processor }
      (merge consent {
        granted: false,
        revoked-at: (some block-height)
      })
    )

    ;; Log consent revocation
    (map-set consent-history
      { user: tx-sender, timestamp: block-height }
      {
        action: "consent-revoked",
        purpose: purpose,
        processor: data-processor,
        details: "Consent revoked by user"
      }
    )
    (ok true)
  )
)

;; Update consent conditions
(define-public (update-consent-conditions
    (purpose uint)
    (data-processor principal)
    (new-conditions (string-ascii 200)))
  (let
    (
      (consent (unwrap! (map-get? consent-records
        { user: tx-sender, purpose: purpose, data-processor: data-processor })
        ERR_NOT_FOUND))
    )
    (asserts! (get granted consent) ERR_INVALID_INPUT)
    (asserts! (is-none (get revoked-at consent)) ERR_INVALID_INPUT)
    (asserts! (> (len new-conditions) u0) ERR_INVALID_INPUT)

    (map-set consent-records
      { user: tx-sender, purpose: purpose, data-processor: data-processor }
      (merge consent { conditions: new-conditions })
    )

    ;; Log condition update
    (map-set consent-history
      { user: tx-sender, timestamp: block-height }
      {
        action: "conditions-updated",
        purpose: purpose,
        processor: data-processor,
        details: "Consent conditions modified"
      }
    )
    (ok true)
  )
)

;; Extend consent expiration
(define-public (extend-consent
    (purpose uint)
    (data-processor principal)
    (new-expires-at uint))
  (let
    (
      (consent (unwrap! (map-get? consent-records
        { user: tx-sender, purpose: purpose, data-processor: data-processor })
        ERR_NOT_FOUND))
    )
    (asserts! (get granted consent) ERR_INVALID_INPUT)
    (asserts! (is-none (get revoked-at consent)) ERR_INVALID_INPUT)
    (asserts! (> new-expires-at block-height) ERR_INVALID_INPUT)

    (map-set consent-records
      { user: tx-sender, purpose: purpose, data-processor: data-processor }
      (merge consent { expires-at: (some new-expires-at) })
    )

    ;; Log extension
    (map-set consent-history
      { user: tx-sender, timestamp: block-height }
      {
        action: "consent-extended",
        purpose: purpose,
        processor: data-processor,
        details: "Consent expiration extended"
      }
    )
    (ok true)
  )
)

;; Read-only functions

;; Check if consent is valid and active
(define-read-only (is-consent-valid (user principal) (purpose uint) (data-processor principal))
  (match (map-get? consent-records { user: user, purpose: purpose, data-processor: data-processor })
    consent
      (and
        (get granted consent)
        (is-none (get revoked-at consent))
        (match (get expires-at consent)
          exp-date (> exp-date block-height)
          true
        )
      )
    false
  )
)

;; Get consent record
(define-read-only (get-consent-record (user principal) (purpose uint) (data-processor principal))
  (map-get? consent-records { user: user, purpose: purpose, data-processor: data-processor })
)

;; Get user's global preferences
(define-read-only (get-global-preferences (user principal))
  (map-get? global-preferences { user: user })
)

;; Check if consent has expired
(define-read-only (is-consent-expired (user principal) (purpose uint) (data-processor principal))
  (match (map-get? consent-records { user: user, purpose: purpose, data-processor: data-processor })
    consent
      (match (get expires-at consent)
        exp-date (<= exp-date block-height)
        false
      )
    false
  )
)

;; Get consent history entry
(define-read-only (get-consent-history (user principal) (timestamp uint))
  (map-get? consent-history { user: user, timestamp: timestamp })
)
