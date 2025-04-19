;; DeFi Oracle Verification Network: Full Oracle Network with Verification Records

;; Constants
(define-constant ERR-NOT-NETWORK-CONTROLLER (err u1))
(define-constant ERR-NETWORK-OFFLINE (err u2))
(define-constant ERR-INVALID-FEED (err u3))
(define-constant ERR-FEED-ALREADY-VERIFIED (err u4))
(define-constant ERR-INVALID-VERIFICATION-SIGNATURE (err u5))
(define-constant ERR-EMBARGO-ACTIVE (err u6))
(define-constant ERR-INSUFFICIENT-DEPOSIT (err u7))
(define-constant ERR-INVALID-INPUT (err u8))
(define-constant ERR-FEED-EXISTS (err u9))
(define-constant MAX-FEED-ID u100) ;; Maximum allowed feed ID

;; Data Variables
(define-data-var network-controller principal tx-sender)
(define-data-var network-online bool false)
(define-data-var current-round uint u0)
(define-data-var participation-deposit uint u1000000) ;; 1 STX
(define-data-var total-incentives uint u0)
(define-data-var last-checkpoint uint u0) ;; Block height tracking for embargo periods

;; Feed Structure
(define-map price-feeds
    uint
    {
        data-source: (string-utf8 256),
        verification-signature: (buff 32), ;; SHA256 hash of the expected verification data
        embargo-end: uint,                 ;; Embargo period end block height
        incentive: uint,
        verified: bool
    }
)

;; Verifier Performance Tracking
(define-map verifier-stats
    principal
    {
        active-feed: uint,
        verified-feeds: (list 20 uint),
        last-verification: uint,
        total-verifications: uint
    }
)

;; Verifier History
(define-map feed-verifications
    {feed: uint, verifier: principal}
    {
        submission-count: uint,
        verified-at: (optional uint)
    }
)

;; Events
(define-map verification-records
    uint
    (list 10 {verifier: principal, block-height: uint})
)

;; Authorization
(define-private (is-controller)
    (is-eq tx-sender (var-get network-controller)))

;; Block Height Management
(define-public (set-checkpoint (new-checkpoint uint))
    (begin
        (asserts! (is-controller) ERR-NOT-NETWORK-CONTROLLER)
        ;; Validate checkpoint is not less than current
        (asserts! (>= new-checkpoint (var-get last-checkpoint)) ERR-INVALID-INPUT)
        (var-set last-checkpoint new-checkpoint)
        (ok true)))

;; Network Management Functions
(define-public (start-network)
    (begin
        (asserts! (is-controller) ERR-NOT-NETWORK-CONTROLLER)
        (var-set network-online true)
        (var-set current-round u0)
        (var-set total-incentives u0)
        (ok true)))

(define-public (register-feed
    (feed-id uint)
    (data-source (string-utf8 256))
    (verification-signature (buff 32))
    (embargo-end uint)
    (incentive uint))
    (begin
        (asserts! (is-controller) ERR-NOT-NETWORK-CONTROLLER)
        
        ;; Validate feed-id is within acceptable range
        (asserts! (<= feed-id MAX-FEED-ID) ERR-INVALID-INPUT)
        
        ;; Check if feed already exists to prevent overwriting
        (asserts! (is-none (map-get? price-feeds feed-id)) ERR-FEED-EXISTS)
        
        ;; Validate embargo end is in the future
        (asserts! (>= embargo-end (var-get last-checkpoint)) ERR-INVALID-INPUT)
        
        ;; Validate verification signature is not empty
        (asserts! (> (len verification-signature) u0) ERR-INVALID-INPUT)
        
        ;; Validate data source is not empty
        (asserts! (> (len data-source) u0) ERR-INVALID-INPUT)
        
        ;; Validate incentive is a positive amount
        (asserts! (> incentive u0) ERR-INVALID-INPUT)
        
        ;; Set the feed data
        (map-set price-feeds feed-id
            {
                data-source: data-source,
                verification-signature: verification-signature,
                embargo-end: embargo-end,
                incentive: incentive,
                verified: false
            })
            
        ;; Calculate new incentives pool safely
        (let ((new-incentives (+ (var-get total-incentives) incentive)))
            ;; Make sure the addition doesn't overflow
            (asserts! (>= new-incentives (var-get total-incentives)) ERR-INVALID-INPUT)
            ;; Update the total incentives
            (var-set total-incentives new-incentives))
        (ok true)))

;; Verifier Onboarding
(define-public (join-network)
    (begin
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        ;; Require participation deposit
        (try! (stx-transfer? (var-get participation-deposit) tx-sender (var-get network-controller)))
        
        (map-set verifier-stats tx-sender
            {
                active-feed: u0,
                verified-feeds: (list),
                last-verification: u0,
                total-verifications: u0
            })
        (ok true)))

;; Feed Verification Functions
(define-public (verify-feed
    (feed-id uint)
    (verification-data (buff 32)))
    (let (
        (feed (unwrap! (map-get? price-feeds feed-id) ERR-INVALID-FEED))
        (verifier (unwrap! (map-get? verifier-stats tx-sender) ERR-INVALID-FEED))
        (current-height (var-get last-checkpoint))
        )
        ;; Check feed availability
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        (asserts! (>= current-height (get embargo-end feed)) ERR-EMBARGO-ACTIVE)
        (asserts! (not (get verified feed)) ERR-FEED-ALREADY-VERIFIED)
        
        ;; Verify data signature - directly compare the signatures
        (if (is-eq verification-data (get verification-signature feed))
            (begin
                ;; Update feed status
                (map-set price-feeds feed-id
                    (merge feed {verified: true}))
                
                ;; Update verifier stats
                (map-set verifier-stats tx-sender
                    (merge verifier {
                        active-feed: (+ feed-id u1),
                        verified-feeds: (unwrap! (as-max-len? 
                            (append (get verified-feeds verifier) feed-id) u20)
                            ERR-INVALID-FEED),
                        total-verifications: (+ (get total-verifications verifier) u1)
                    }))
                
                ;; Record verification
                (map-set feed-verifications
                    {feed: feed-id, verifier: tx-sender}
                    {
                        submission-count: u1,
                        verified-at: (some current-height)
                    })
                
                ;; Distribute incentive
                (try! (stx-transfer? (get incentive feed) (var-get network-controller) tx-sender))
                
                ;; Record success
                (match (map-get? verification-records feed-id)
                    records (map-set verification-records feed-id
                        (unwrap! (as-max-len?
                            (append records {verifier: tx-sender, block-height: current-height})
                            u10)
                            ERR-INVALID-FEED))
                    (map-set verification-records feed-id
                        (list {verifier: tx-sender, block-height: current-height})))
                
                (ok true))
            ERR-INVALID-VERIFICATION-SIGNATURE)))

;; Read-only functions
(define-read-only (get-feed-source (feed-id uint))
    (match (map-get? price-feeds feed-id)
        feed (if (>= (var-get last-checkpoint) (get embargo-end feed))
            (ok (get data-source feed))
            ERR-EMBARGO-ACTIVE)
        ERR-INVALID-FEED))

(define-read-only (get-verifier-profile (verifier principal))
    (map-get? verifier-stats verifier))

(define-read-only (get-verification-history (feed-id uint))
    (map-get? verification-records feed-id))

(define-read-only (get-current-checkpoint)
    (var-get last-checkpoint))

(define-read-only (get-network-info)
    {
        online: (var-get network-online),
        current-round: (var-get current-round),
        total-incentives: (var-get total-incentives),
        participation-deposit: (var-get participation-deposit),
        last-checkpoint: (var-get last-checkpoint)
    })