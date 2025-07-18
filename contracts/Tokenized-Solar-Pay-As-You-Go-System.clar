(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))

(define-data-var energy-rate uint u1000)
(define-data-var total-energy-credits uint u0)

(define-map user-balances principal uint)
(define-map energy-usage { user: principal, month: uint } uint)
(define-map solar-devices principal bool)
(define-map energy-nfts uint { owner: principal, active: bool })
(define-map device-status principal { active: bool, last-reading: uint })

(define-non-fungible-token energy-access uint)

(define-public (register-device)
    (let ((sender tx-sender))
        (asserts! (is-none (map-get? solar-devices sender)) (err u104))
        (map-set solar-devices sender true)
        (map-set device-status sender { active: false, last-reading: u0 })
        (ok true)))

(define-public (purchase-credits (amount uint))
    (let ((sender tx-sender)
          (current-balance (default-to u0 (map-get? user-balances sender))))
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount sender contract-owner))
        (map-set user-balances 
            sender 
            (+ current-balance (* amount (var-get energy-rate))))
        (var-set total-energy-credits (+ (var-get total-energy-credits) amount))
        (ok true)))

(define-public (mint-energy-nft (token-id uint))
    (let ((sender tx-sender))
        (asserts! (is-none (map-get? energy-nfts token-id)) (err u105))
        (try! (nft-mint? energy-access token-id sender))
        (map-set energy-nfts token-id { owner: sender, active: true })
        (ok true)))

(define-public (consume-energy (amount uint))
    (let ((sender tx-sender)
          (balance (default-to u0 (map-get? user-balances sender)))
          (device (map-get? device-status sender)))
        (asserts! (is-some device) (err u106))
        (asserts! (>= balance amount) err-insufficient-balance)
        (map-set user-balances 
            sender 
            (- balance amount))
        (map-set device-status 
            sender 
            (merge (unwrap-panic device) { last-reading: amount }))
        (ok true)))

(define-public (transfer-credits (recipient principal) (amount uint))
    (let ((sender tx-sender)
          (sender-balance (default-to u0 (map-get? user-balances sender)))
          (recipient-balance (default-to u0 (map-get? user-balances recipient))))
        (asserts! (>= sender-balance amount) err-insufficient-balance)
        (map-set user-balances sender (- sender-balance amount))
        (map-set user-balances recipient (+ recipient-balance amount))
        (ok true)))

(define-read-only (get-balance (user principal))
    (ok (default-to u0 (map-get? user-balances user))))

(define-read-only (get-device-status (user principal))
    (ok (map-get? device-status user)))

(define-read-only (get-total-credits)
    (ok (var-get total-energy-credits)))

(define-public (update-energy-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set energy-rate new-rate)
        (ok true)))

(define-public (toggle-device (status bool))
    (let ((sender tx-sender)
          (device (map-get? device-status sender)))
        (asserts! (is-some device) (err u106))
        (map-set device-status 
            sender 
            (merge (unwrap-panic device) { active: status }))
        (ok true)))