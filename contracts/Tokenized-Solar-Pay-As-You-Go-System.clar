(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-alert-not-found (err u107))
(define-constant err-invalid-threshold (err u108))

(define-data-var energy-rate uint u1000)
(define-data-var total-energy-credits uint u0)

(define-map user-balances principal uint)
(define-map energy-usage { user: principal, month: uint } uint)
(define-map solar-devices principal bool)
(define-map energy-nfts uint { owner: principal, active: bool })
(define-map device-status principal { active: bool, last-reading: uint })
(define-map alert-settings principal { low-threshold: uint, critical-threshold: uint, enabled: bool })
(define-map consumption-alerts principal { alert-type: uint, triggered-at: uint, consumption-amount: uint })

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
          (device (map-get? device-status sender))
          (new-balance (- balance amount))
          (alert-config (map-get? alert-settings sender)))
        (asserts! (is-some device) (err u106))
        (asserts! (>= balance amount) err-insufficient-balance)
        (map-set user-balances sender new-balance)
        (map-set device-status 
            sender 
            (merge (unwrap-panic device) { last-reading: amount }))
        (if (and (is-some alert-config) 
                 (get enabled (unwrap-panic alert-config)))
            (begin
                (if (<= new-balance (get critical-threshold (unwrap-panic alert-config)))
                    (map-set consumption-alerts sender 
                        { alert-type: u2, triggered-at: burn-block-height, consumption-amount: amount })
                    (if (<= new-balance (get low-threshold (unwrap-panic alert-config)))
                        (map-set consumption-alerts sender 
                            { alert-type: u1, triggered-at: burn-block-height, consumption-amount: amount })
                        true))
                (ok true))
            (ok true))))

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

(define-public (configure-alerts (low-threshold uint) (critical-threshold uint))
    (let ((sender tx-sender))
        (asserts! (< low-threshold critical-threshold) err-invalid-threshold)
        (map-set alert-settings sender 
            { low-threshold: low-threshold, critical-threshold: critical-threshold, enabled: true })
        (ok true)))

(define-public (toggle-alerts (enabled bool))
    (let ((sender tx-sender)
          (current-settings (map-get? alert-settings sender)))
        (asserts! (is-some current-settings) err-alert-not-found)
        (map-set alert-settings sender 
            (merge (unwrap-panic current-settings) { enabled: enabled }))
        (ok true)))

(define-public (clear-alert)
    (let ((sender tx-sender))
        (map-delete consumption-alerts sender)
        (ok true)))

(define-read-only (get-alert-settings (user principal))
    (ok (map-get? alert-settings user)))

(define-read-only (get-active-alert (user principal))
    (ok (map-get? consumption-alerts user)))

(define-read-only (check-consumption-status (user principal))
    (let ((balance (default-to u0 (map-get? user-balances user)))
          (alert-config (map-get? alert-settings user)))
        (if (is-some alert-config)
            (let ((config (unwrap-panic alert-config)))
                (if (<= balance (get critical-threshold config))
                    (ok u2)
                    (if (<= balance (get low-threshold config))
                        (ok u1)
                        (ok u0))))
            (ok u0))))