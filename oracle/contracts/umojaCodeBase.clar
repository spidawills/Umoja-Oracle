;; DeFi Oracle Verification Network - Stage 1: Basic Oracle Network

;; Constants
(define-constant ERR-NOT-NETWORK-CONTROLLER (err u1))
(define-constant ERR-NETWORK-OFFLINE (err u2))
(define-constant ERR-INVALID-FEED (err u3))
(define-constant ERR-FEED-ALREADY-VERIFIED (err u4))
(define-constant ERR-INVALID-VERIFICATION-SIGNATURE (err u5))

;; Data Variables
(define-data-var network-controller principal tx-sender)
(define-data-var network-online bool false)
(define-data-var current-round uint u0)

;; Feed Structure
(define-map price-feeds
    uint
    {
        data-source: (string-utf8 256),
        verification-signature: (buff 32), ;; SHA256 hash of the expected verification data
        incentive: uint,
        verified: bool
    }
)

;; Verifier Performance Tracking
(define-map verifier-stats
    principal
    {
        active-feed: uint,
        total-verifications: uint
    }
)

;; Authorization
(define-private (is-controller)
    (is-eq tx-sender (var-get network-controller)))

;; Network Management Functions
(define-public (start-network)
    (begin
        (asserts! (is-controller) ERR-NOT-NETWORK-CONTROLLER)
        (var-set network-online true)
        (var-set current-round u0)
        (ok true)))

(define-public (register-feed
    (feed-id uint)
    (data-source (string-utf8 256))
    (verification-signature (buff 32))
    (incentive uint))
    (begin
        (asserts! (is-controller) ERR-NOT-NETWORK-CONTROLLER)
        
        ;; Validate verification signature is not empty
        (asserts! (> (len verification-signature) u0) ERR-NOT-NETWORK-CONTROLLER)
        
        ;; Validate data source is not empty
        (asserts! (> (len data-source) u0) ERR-NOT-NETWORK-CONTROLLER)
        
        ;; Set the feed data
        (map-set price-feeds feed-id
            {
                data-source: data-source,
                verification-signature: verification-signature,
                incentive: incentive,
                verified: false
            })
        (ok true)))

;; Verifier Onboarding
(define-public (join-network)
    (begin
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        
        (map-set verifier-stats tx-sender
            {
                active-feed: u0,
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
        )
        ;; Check feed availability
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
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
                        total-verifications: (+ (get total-verifications verifier) u1)
                    }))
                
                ;; Distribute incentive
                (try! (stx-transfer? (get incentive feed) (var-get network-controller) tx-sender))
                
                (ok true))
            ERR-INVALID-VERIFICATION-SIGNATURE)))

;; Read-only functions
(define-read-only (get-feed-source (feed-id uint))
    (match (map-get? price-feeds feed-id)
        feed (ok (get data-source feed))
        ERR-INVALID-FEED))

(define-read-only (get-verifier-profile (verifier principal))
    (map-get? verifier-stats verifier))

(define-read-only (get-network-info)
    {
        online: (var-get network-online),
        current-round: (var-get current-round)
    })
