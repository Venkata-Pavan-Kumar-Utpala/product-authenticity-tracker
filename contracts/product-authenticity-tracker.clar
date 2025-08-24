;; Product Authenticity Tracker Smart Contract
;; Anti-counterfeiting solution using blockchain to verify genuine products throughout supply chain

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-invalid-manufacturer (err u105))
(define-constant err-invalid-input (err u106))

;; Product status definitions
(define-constant STATUS-MANUFACTURED u1)
(define-constant STATUS-IN-TRANSIT u2)
(define-constant STATUS-DELIVERED u3)
(define-constant STATUS-SOLD u4)
(define-constant STATUS-RECALLED u5)

;; Data Variables
(define-data-var next-product-id uint u1)
(define-data-var next-manufacturer-id uint u1)

;; Data Maps

;; Registered manufacturers
(define-map manufacturers
    { manufacturer-id: uint }
    {
        name: (string-ascii 100),
        address: principal,
        verified: bool,
        registered-at: uint
    }
)

;; Manufacturer lookup by address
(define-map manufacturer-addresses
    { address: principal }
    { manufacturer-id: uint }
)

;; Products registry
(define-map products
    { product-id: uint }
    {
        manufacturer-id: uint,
        product-name: (string-ascii 100),
        model: (string-ascii 50),
        serial-number: (string-ascii 50),
        batch-number: (string-ascii 50),
        manufactured-date: uint,
        status: uint,
        current-holder: principal,
        metadata-uri: (optional (string-ascii 200))
    }
)

;; Product ownership history and supply chain tracking
(define-map product-history
    { product-id: uint, sequence: uint }
    {
        from-address: principal,
        to-address: principal,
        status: uint,
        location: (string-ascii 100),
        timestamp: uint,
        notes: (optional (string-ascii 200))
    }
)

;; Track sequence numbers for product history
(define-map product-sequence-counter
    { product-id: uint }
    { next-sequence: uint }
)

;; Authorized verifiers (quality control, shipping companies, retailers)
(define-map authorized-verifiers
    { verifier: principal }
    { 
        name: (string-ascii 100),
        role: (string-ascii 50),
        authorized-by: principal,
        authorized-at: uint
    }
)

;; Helper functions for input validation
(define-private (is-valid-string (str (string-ascii 200)))
    (> (len str) u0)
)

(define-private (is-valid-status (status uint))
    (and (>= status u1) (<= status u5))
)

;; Public Functions

;; Register a new manufacturer (only contract owner)
(define-public (register-manufacturer (name (string-ascii 100)) (manufacturer-address principal))
    (let
        (
            (manufacturer-id (var-get next-manufacturer-id))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-valid-string name) err-invalid-input)
        (asserts! (is-none (map-get? manufacturer-addresses { address: manufacturer-address })) err-already-exists)
        
        (map-set manufacturers
            { manufacturer-id: manufacturer-id }
            {
                name: name,
                address: manufacturer-address,
                verified: true,
                registered-at: stacks-block-height
            }
        )
        
        (map-set manufacturer-addresses
            { address: manufacturer-address }
            { manufacturer-id: manufacturer-id }
        )
        
        (var-set next-manufacturer-id (+ manufacturer-id u1))
        (ok manufacturer-id)
    )
)

;; Register a new product (only registered manufacturers)
(define-public (register-product 
    (product-name (string-ascii 100))
    (model (string-ascii 50))
    (serial-number (string-ascii 50))
    (batch-number (string-ascii 50))
    (metadata-uri (optional (string-ascii 200)))
)
    (let
        (
            (product-id (var-get next-product-id))
            (manufacturer-data (map-get? manufacturer-addresses { address: tx-sender }))
        )
        (asserts! (is-some manufacturer-data) err-invalid-manufacturer)
        (asserts! (is-valid-string product-name) err-invalid-input)
        (asserts! (is-valid-string model) err-invalid-input)
        (asserts! (is-valid-string serial-number) err-invalid-input)
        (asserts! (is-valid-string batch-number) err-invalid-input)
        
        (let
            (
                (manufacturer-id (get manufacturer-id (unwrap-panic manufacturer-data)))
            )
            
            (map-set products
                { product-id: product-id }
                {
                    manufacturer-id: manufacturer-id,
                    product-name: product-name,
                    model: model,
                    serial-number: serial-number,
                    batch-number: batch-number,
                    manufactured-date: stacks-block-height,
                    status: STATUS-MANUFACTURED,
                    current-holder: tx-sender,
                    metadata-uri: metadata-uri
                }
            )
            
            ;; Initialize product history
            (map-set product-history
                { product-id: product-id, sequence: u1 }
                {
                    from-address: tx-sender,
                    to-address: tx-sender,
                    status: STATUS-MANUFACTURED,
                    location: "Manufacturing Facility",
                    timestamp: stacks-block-height,
                    notes: (some "Product manufactured")
                }
            )
            
            (map-set product-sequence-counter
                { product-id: product-id }
                { next-sequence: u2 }
            )
            
            (var-set next-product-id (+ product-id u1))
            (ok product-id)
        )
    )
)

;; Transfer product to next party in supply chain
(define-public (transfer-product 
    (product-id uint)
    (to-address principal)
    (new-status uint)
    (location (string-ascii 100))
    (notes (optional (string-ascii 200)))
)
    (let
        (
            (product-data (unwrap! (map-get? products { product-id: product-id }) err-not-found))
            (sequence-data (unwrap! (map-get? product-sequence-counter { product-id: product-id }) err-not-found))
            (current-sequence (get next-sequence sequence-data))
        )
        ;; Input validation
        (asserts! (> product-id u0) err-invalid-input)
        (asserts! (is-valid-status new-status) err-invalid-input)
        (asserts! (is-valid-string location) err-invalid-input)
        
        ;; Verify sender is current holder or authorized verifier
        (asserts! 
            (or 
                (is-eq tx-sender (get current-holder product-data))
                (is-some (map-get? authorized-verifiers { verifier: tx-sender }))
            ) 
            err-unauthorized
        )
        
        ;; Validate status transition
        (asserts! (not (is-eq new-status (get status product-data))) err-invalid-status)
        
        ;; Update product
        (map-set products
            { product-id: product-id }
            (merge product-data {
                status: new-status,
                current-holder: to-address
            })
        )
        
        ;; Add to history
        (map-set product-history
            { product-id: product-id, sequence: current-sequence }
            {
                from-address: (get current-holder product-data),
                to-address: to-address,
                status: new-status,
                location: location,
                timestamp: stacks-block-height,
                notes: notes
            }
        )
        
        ;; Increment sequence counter
        (map-set product-sequence-counter
            { product-id: product-id }
            { next-sequence: (+ current-sequence u1) }
        )
        
        (ok true)
    )
)

;; Authorize a verifier (only contract owner)
(define-public (authorize-verifier 
    (verifier principal)
    (name (string-ascii 100))
    (role (string-ascii 50))
)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-valid-string name) err-invalid-input)
        (asserts! (is-valid-string role) err-invalid-input)
        
        (map-set authorized-verifiers
            { verifier: verifier }
            {
                name: name,
                role: role,
                authorized-by: tx-sender,
                authorized-at: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Revoke verifier authorization (only contract owner)
(define-public (revoke-verifier (verifier principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some (map-get? authorized-verifiers { verifier: verifier })) err-not-found)
        (map-delete authorized-verifiers { verifier: verifier })
        (ok true)
    )
)

;; Mark product as recalled (only manufacturer or authorized verifier)
(define-public (recall-product (product-id uint) (reason (string-ascii 200)))
    (let
        (
            (product-data (unwrap! (map-get? products { product-id: product-id }) err-not-found))
            (manufacturer-data (map-get? manufacturers { manufacturer-id: (get manufacturer-id product-data) }))
        )
        (asserts! (> product-id u0) err-invalid-input)
        (asserts! (is-valid-string reason) err-invalid-input)
        
        (asserts! 
            (or 
                (is-eq tx-sender (get address (unwrap-panic manufacturer-data)))
                (is-some (map-get? authorized-verifiers { verifier: tx-sender }))
            ) 
            err-unauthorized
        )
        
        (try! (transfer-product 
            product-id
            (get current-holder product-data)
            STATUS-RECALLED
            "Recalled"
            (some reason)
        ))
        
        (ok true)
    )
)

;; Read-only functions

;; Get product details
(define-read-only (get-product (product-id uint))
    (map-get? products { product-id: product-id })
)

;; Get manufacturer details
(define-read-only (get-manufacturer (manufacturer-id uint))
    (map-get? manufacturers { manufacturer-id: manufacturer-id })
)

;; Get manufacturer by address
(define-read-only (get-manufacturer-by-address (address principal))
    (match (map-get? manufacturer-addresses { address: address })
        manufacturer-lookup (map-get? manufacturers { manufacturer-id: (get manufacturer-id manufacturer-lookup) })
        none
    )
)

;; Get product history entry
(define-read-only (get-product-history (product-id uint) (sequence uint))
    (map-get? product-history { product-id: product-id, sequence: sequence })
)

;; Get current sequence for product history
(define-read-only (get-product-sequence-counter (product-id uint))
    (map-get? product-sequence-counter { product-id: product-id })
)

;; Verify product authenticity
(define-read-only (verify-authenticity (product-id uint))
    (match (map-get? products { product-id: product-id })
        product-data 
        (let
            (
                (manufacturer-data (unwrap! (map-get? manufacturers { manufacturer-id: (get manufacturer-id product-data) }) (err u404)))
            )
            (ok {
                is-authentic: (get verified manufacturer-data),
                manufacturer: (get name manufacturer-data),
                product-name: (get product-name product-data),
                status: (get status product-data),
                current-holder: (get current-holder product-data),
                manufactured-date: (get manufactured-date product-data)
            })
        )
        err-not-found
    )
)

;; Check if address is authorized verifier
(define-read-only (is-authorized-verifier (address principal))
    (is-some (map-get? authorized-verifiers { verifier: address }))
)

;; Get verifier details
(define-read-only (get-verifier (verifier principal))
    (map-get? authorized-verifiers { verifier: verifier })
)

;; Get contract stats
(define-read-only (get-contract-stats)
    {
        total-products: (- (var-get next-product-id) u1),
        total-manufacturers: (- (var-get next-manufacturer-id) u1),
        contract-owner: contract-owner
    }
)