# P2P Lending Platform Smart Contract

A decentralized peer-to-peer lending platform implemented as a smart contract on the Stacks blockchain. This contract enables users to create, fund, and manage loans with customizable terms, collateral requirements, and risk-based interest rates.

## Features

- **Loan Creation**: Borrowers can request loans by providing collateral
- **Risk-Based Interest Rates**: Three-tiered interest rate system (Low, Medium, High)
- **Flexible Repayment**: Supports partial repayments and tracking of repayment history
- **Loan Refinancing**: Allows borrowers to modify loan terms under specific conditions
- **Collateral Management**: Automatic collateral locking and release
- **Loan Liquidation**: Enables lenders to claim collateral for defaulted loans
- **Balance Management**: Users can deposit and withdraw funds from the platform

## Core Functions

### For Borrowers

1. `request-loan`
   - Parameters:
     - `requested-amount`: Amount of STX to borrow
     - `collateral-amount`: Amount of STX provided as collateral
     - `risk-level`: Risk category ("LOW", "MEDIUM", "HIGH")
     - `duration-blocks`: Loan duration in blocks
   - Requirements:
     - Collateral must be >= requested amount
     - Valid risk level and interest rate
     - Duration must be > 0

2. `make-loan-payment`
   - Parameters:
     - `loan-id`: Identifier of the loan
     - `payment-amount`: Amount to repay
   - Features:
     - Supports partial repayments
     - Automatically returns collateral upon full repayment
     - Updates loan status to "REPAID" when fully paid

3. `modify-loan-terms`
   - Parameters:
     - `loan-id`: Identifier of the loan
     - `new-risk-level`: New risk category
     - `additional-duration`: Additional blocks to extend the loan
   - Requirements:
     - New interest rate must be lower than current rate
     - Loan must be active
     - Only borrower can initiate

### For Lenders

1. `fund-loan`
   - Parameters:
     - `loan-id`: Identifier of the loan to fund
   - Features:
     - Transfers loan amount to borrower
     - Updates loan status to "ACTIVE"
     - Records loan origination block

2. `liquidate-loan`
   - Parameters:
     - `loan-id`: Identifier of the loan to liquidate
   - Requirements:
     - Loan must be past due
     - Only lender can initiate
     - Loan must be in "ACTIVE" status

### General Utility Functions

1. `deposit-funds`
   - Parameters:
     - `deposit-amount`: Amount of STX to deposit
   - Features:
     - Updates user's platform balance
     - Prevents overflow

2. `withdraw-funds`
   - Parameters:
     - `withdrawal-amount`: Amount of STX to withdraw
   - Requirements:
     - Sufficient balance available

## Read-Only Functions

1. `get-loan-details`
   - Returns complete information about a specific loan

2. `get-user-balance`
   - Returns user's current platform balance

3. `get-risk-adjusted-rate`
   - Returns interest rate for a given risk level

4. `calculate-total-loan-repayment`
   - Calculates total repayment amount including interest

## Error Codes

- `ERR-UNAUTHORIZED-ACCESS` (u1): User not authorized for operation
- `ERR-INVALID-LOAN-AMOUNT` (u2): Invalid loan amount specified
- `ERR-INSUFFICIENT-USER-BALANCE` (u3): Insufficient balance for operation
- `ERR-LOAN-RECORD-NOT-FOUND` (u4): Loan ID doesn't exist
- `ERR-LOAN-ALREADY-FUNDED-ERROR` (u5): Attempt to fund an already funded loan
- `ERR-LOAN-NOT-FUNDED-ERROR` (u6): Operation on unfunded loan
- `ERR-LOAN-IN-DEFAULT-STATE` (u7): Operation on defaulted loan
- `ERR-INVALID-LOAN-PARAMETERS` (u8): Invalid loan parameters provided
- `ERR-LOAN-REPAYMENT-NOT-DUE` (u9): Attempted early liquidation
- `ERR-INSUFFICIENT-COLLATERAL` (u10): Insufficient collateral provided
- `ERR-INVALID-INTEREST-RATE` (u11): Invalid interest rate specified
- `ERR-REFINANCE-NOT-ALLOWED` (u12): Refinancing conditions not met
- `ERR-INVALID-REPAYMENT-AMOUNT` (u13): Invalid repayment amount
- `ERR-OVERFLOW` (u14): Arithmetic overflow detected

## Loan States

1. `OPEN`: Loan created but not yet funded
2. `ACTIVE`: Loan funded and in repayment period
3. `REPAID`: Loan fully repaid
4. `DEFAULTED`: Loan defaulted and liquidated

## Interest Rates

Default risk-based interest rates:
- LOW: 5%
- MEDIUM: 10%
- HIGH: 15%

## Security Considerations

- Collateral is locked in the contract until loan completion or default
- Only authorized participants can perform sensitive operations
- Balance overflow checks implemented
- Strict validation of all input parameters
- Time-based operations use block height for reliability