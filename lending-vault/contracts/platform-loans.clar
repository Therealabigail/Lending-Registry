;; P2P Lending Platform

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS u1)
(define-constant ERR-INVALID-LOAN-AMOUNT u2)
(define-constant ERR-INSUFFICIENT-USER-BALANCE u3)
(define-constant ERR-LOAN-RECORD-NOT-FOUND u4)
(define-constant ERR-LOAN-ALREADY-FUNDED-ERROR u5)
(define-constant ERR-LOAN-NOT-FUNDED-ERROR u6)
(define-constant ERR-LOAN-IN-DEFAULT-STATE u7)
(define-constant ERR-INVALID-LOAN-PARAMETERS u8)
(define-constant ERR-LOAN-REPAYMENT-NOT-DUE u9)
(define-constant ERR-INSUFFICIENT-COLLATERAL u10)
(define-constant ERR-INVALID-INTEREST-RATE u11)
(define-constant ERR-REFINANCE-NOT-ALLOWED u12)
(define-constant ERR-INVALID-REPAYMENT-AMOUNT u13)
(define-constant ERR-OVERFLOW u14)

;; Data structures
(define-map active-loans
  { loan-id: uint }
  {
    borrower-principal: principal,
    lender-principal: (optional principal),
    borrowed-amount: uint,
    collateral-amount: uint,
    annual-interest-rate-percentage: uint,
    loan-duration-in-blocks: uint,
    loan-origination-block: (optional uint),
    loan-status: (string-ascii 20),
    total-amount-repaid: uint
  }
)

(define-map user-stx-balances principal uint)
(define-map risk-based-interest-rates (string-ascii 20) uint)

(define-data-var total-loans-created uint u1)

;; Initialize interest rates
(map-set risk-based-interest-rates "LOW" u5)
(map-set risk-based-interest-rates "MEDIUM" u10)
(map-set risk-based-interest-rates "HIGH" u15)

;; Read-only functions
(define-read-only (get-loan-details (loan-id uint))
  (map-get? active-loans { loan-id: loan-id })
)

(define-read-only (get-user-balance (user-address principal))
  (default-to u0 (map-get? user-stx-balances user-address))
)

(define-read-only (get-risk-adjusted-rate (risk-level (string-ascii 20)))
  (default-to u0 (map-get? risk-based-interest-rates risk-level))
)

(define-read-only (calculate-total-loan-repayment (loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (principal-amount (get borrowed-amount loan-record))
    (interest-rate-percentage (get annual-interest-rate-percentage loan-record))
    (loan-duration (get loan-duration-in-blocks loan-record))
  )
  (ok (+ principal-amount (/ (* principal-amount interest-rate-percentage loan-duration) (* u100 u144 u365))))
  )
)

;; Public functions
(define-public (request-loan (requested-amount uint) (collateral-amount uint) (risk-level (string-ascii 20)) (duration-blocks uint))
  (let (
    (loan-id (var-get total-loans-created))
    (interest-rate (unwrap! (map-get? risk-based-interest-rates risk-level) (err ERR-INVALID-INTEREST-RATE)))
  )
    ;; Input validation
    (asserts! (> requested-amount u0) (err ERR-INVALID-LOAN-AMOUNT))
    (asserts! (>= collateral-amount requested-amount) (err ERR-INSUFFICIENT-COLLATERAL))
    (asserts! (> duration-blocks u0) (err ERR-INVALID-LOAN-PARAMETERS))
    (asserts! (and (>= interest-rate u1) (<= interest-rate u100)) (err ERR-INVALID-INTEREST-RATE))
    
    ;; Transfer collateral to contract
    (try! (stx-transfer? collateral-amount tx-sender (as-contract tx-sender)))
    
    ;; Create loan record
    (map-set active-loans
      { loan-id: loan-id }
      {
        borrower-principal: tx-sender,
        lender-principal: none,
        borrowed-amount: requested-amount,
        collateral-amount: collateral-amount,
        annual-interest-rate-percentage: interest-rate,
        loan-duration-in-blocks: duration-blocks,
        loan-origination-block: none,
        loan-status: "OPEN",
        total-amount-repaid: u0
      }
    )
    
    ;; Increment loan counter
    (var-set total-loans-created (+ loan-id u1))
    (ok loan-id)
  )
)

(define-public (fund-loan (loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (loan-amount (get borrowed-amount loan-record))
  )
    ;; Validate loan status
    (asserts! (is-eq (get loan-status loan-record) "OPEN") (err ERR-LOAN-ALREADY-FUNDED-ERROR))
    
    ;; Transfer funds to borrower
    (try! (stx-transfer? loan-amount tx-sender (get borrower-principal loan-record)))
    
    ;; Update loan record
    (map-set active-loans
      { loan-id: loan-id }
      (merge loan-record {
        lender-principal: (some tx-sender),
        loan-origination-block: (some block-height),
        loan-status: "ACTIVE"
      })
    )
    (ok true)
  )
)

(define-public (make-loan-payment (loan-id uint) (payment-amount uint))
  (let (
    (loan-record (unwrap! (get-loan-details loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (total-owed-amount (unwrap! (calculate-total-loan-repayment loan-id) (err ERR-INVALID-LOAN-AMOUNT)))
    (previously-paid-amount (get total-amount-repaid loan-record))
  )
    ;; Validate loan status and payment amount
    (asserts! (is-eq (get loan-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (is-eq tx-sender (get borrower-principal loan-record)) (err ERR-UNAUTHORIZED-ACCESS))
    (asserts! (<= (+ previously-paid-amount payment-amount) total-owed-amount) (err ERR-INVALID-REPAYMENT-AMOUNT))
    
    ;; Transfer payment to lender
    (try! (stx-transfer? payment-amount tx-sender (unwrap! (get lender-principal loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR))))
    
    ;; Update loan record
    (map-set active-loans
      { loan-id: loan-id }
      (merge loan-record {
        total-amount-repaid: (+ previously-paid-amount payment-amount),
        loan-status: (if (>= (+ previously-paid-amount payment-amount) total-owed-amount) "REPAID" "ACTIVE")
      })
    )
    
    ;; Return collateral if loan is fully repaid
    (if (>= (+ previously-paid-amount payment-amount) total-owed-amount)
      (try! (as-contract (stx-transfer? (get collateral-amount loan-record) tx-sender (get borrower-principal loan-record))))
      true
    )
    
    (ok true)
  )
)

(define-public (liquidate-loan (loan-id uint))
  (let (
    (loan-record (unwrap! (get-loan-details loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (start-block (unwrap! (get loan-origination-block loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR)))
    (maturity-block (+ start-block (get loan-duration-in-blocks loan-record)))
  )
    ;; Validate loan status and conditions
    (asserts! (is-eq (get loan-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (>= block-height maturity-block) (err ERR-LOAN-REPAYMENT-NOT-DUE))
    (asserts! (is-eq tx-sender (unwrap! (get lender-principal loan-record) (err ERR-UNAUTHORIZED-ACCESS))) (err ERR-UNAUTHORIZED-ACCESS))
    
    ;; Transfer collateral to lender
    (try! (as-contract (stx-transfer? (get collateral-amount loan-record) tx-sender (unwrap! (get lender-principal loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR)))))
    
    ;; Update loan status
    (map-set active-loans
      { loan-id: loan-id }
      (merge loan-record { loan-status: "DEFAULTED" })
    )
    (ok true)
  )
)

(define-public (modify-loan-terms (loan-id uint) (new-risk-level (string-ascii 20)) (additional-duration uint))
  (let (
    (loan-record (unwrap! (get-loan-details loan-id) (err ERR-LOAN-RECORD-NOT-FOUND)))
    (new-interest-rate (unwrap! (map-get? risk-based-interest-rates new-risk-level) (err ERR-INVALID-INTEREST-RATE)))
  )
    ;; Validate loan status and conditions
    (asserts! (is-eq (get loan-status loan-record) "ACTIVE") (err ERR-LOAN-NOT-FUNDED-ERROR))
    (asserts! (is-eq tx-sender (get borrower-principal loan-record)) (err ERR-UNAUTHORIZED-ACCESS))
    (asserts! (< new-interest-rate (get annual-interest-rate-percentage loan-record)) (err ERR-REFINANCE-NOT-ALLOWED))
    (asserts! (and (>= new-interest-rate u1) (<= new-interest-rate u100)) (err ERR-INVALID-INTEREST-RATE))
    
    ;; Update loan record
    (map-set active-loans
      { loan-id: loan-id }
      (merge loan-record {
        annual-interest-rate-percentage: new-interest-rate,
        loan-duration-in-blocks: (+ additional-duration (- (get loan-duration-in-blocks loan-record) (- block-height (unwrap! (get loan-origination-block loan-record) (err ERR-LOAN-NOT-FUNDED-ERROR)))))
      })
    )
    (ok true)
  )
)

;; Utility functions
(define-public (deposit-funds (deposit-amount uint))
  (let (
    (current-balance (get-user-balance tx-sender))
  )
    (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
    ;; Check for potential overflow before updating the balance
    (asserts! (< (+ current-balance deposit-amount) u340282366920938463463374607431768211455) (err ERR-OVERFLOW))
    (ok (map-set user-stx-balances tx-sender (+ current-balance deposit-amount)))
  )
)

(define-public (withdraw-funds (withdrawal-amount uint))
  (let (
    (current-balance (get-user-balance tx-sender))
  )
    (asserts! (<= withdrawal-amount current-balance) (err ERR-INSUFFICIENT-USER-BALANCE))
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    (ok (map-set user-stx-balances tx-sender (- current-balance withdrawal-amount)))
  )
)