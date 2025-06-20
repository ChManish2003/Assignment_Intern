-- =====================================================
-- DevifyX Banking System - Test Procedures
-- =====================================================
-- This script contains test procedures to validate system functionality
-- =====================================================

USE banking_system;

DELIMITER //

-- =====================================================
-- TEST PROCEDURES
-- =====================================================

-- Test account creation
CREATE PROCEDURE TestAccountCreation()
BEGIN
    DECLARE v_account_id INT;
    DECLARE v_account_number VARCHAR(20);
    DECLARE v_result VARCHAR(255);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Test failed: Account creation error' AS test_result;
        RESIGNAL;
    END;

    START TRANSACTION;
    
    -- Test creating a new savings account
    CALL CreateAccount(1, 1, 1, 1000.00, v_account_id, v_account_number, v_result);
    
    IF v_result = 'Account created successfully' THEN
        SELECT 'PASS: Account creation test successful' AS test_result, 
               v_account_id AS account_id, 
               v_account_number AS account_number;
    ELSE
        SELECT 'FAIL: Account creation test failed' AS test_result, v_result AS error_message;
    END IF;
    
    ROLLBACK; -- Don't actually create the test account
END //

-- Test transaction processing
CREATE PROCEDURE TestTransactionProcessing()
BEGIN
    DECLARE v_trans_id INT;
    DECLARE v_result VARCHAR(255);
    DECLARE v_initial_balance DECIMAL(15,2);
    DECLARE v_final_balance DECIMAL(15,2);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Test failed: Transaction processing error' AS test_result;
        RESIGNAL;
    END;

    START TRANSACTION;
    
    -- Get initial balance
    SELECT balance INTO v_initial_balance FROM accounts WHERE account_id = 1;
    
    -- Test deposit
    CALL MakeDeposit(1, 500.00, 1, 'Test deposit', 'TEST001', v_trans_id, v_result);
    
    -- Get final balance
    SELECT balance INTO v_final_balance FROM accounts WHERE account_id = 1;
    
    IF v_result = 'Transaction completed successfully' AND v_final_balance = v_initial_balance + 500.00 THEN
        SELECT 'PASS: Transaction processing test successful' AS test_result,
               v_initial_balance AS initial_balance,
               v_final_balance AS final_balance,
               v_trans_id AS transaction_id;
    ELSE
        SELECT 'FAIL: Transaction processing test failed' AS test_result, v_result AS error_message;
    END IF;
    
    ROLLBACK; -- Don't actually process the test transaction
END //

-- Test fraud detection
CREATE PROCEDURE TestFraudDetection()
BEGIN
    DECLARE v_alert_count INT DEFAULT 0;
    
    -- Check if fraud alerts were created for large transactions
    SELECT COUNT(*) INTO v_alert_count
    FROM fraud_alerts fa
    JOIN transactions t ON fa.transaction_id = t.transaction_id
    WHERE t.amount >= 10000.00 AND fa.alert_type = 'LARGE_TRANSACTION';
    
    IF v_alert_count > 0 THEN
        SELECT 'PASS: Fraud detection test successful' AS test_result,
               v_alert_count AS alerts_generated;
    ELSE
        SELECT 'FAIL: Fraud detection test failed' AS test_result,
               'No fraud alerts generated for large transactions' AS error_message;
    END IF;
END //

-- Test interest calculation
CREATE PROCEDURE TestInterestCalculation()
BEGIN
    DECLARE v_interest_before DECIMAL(15,2);
    DECLARE v_interest_after DECIMAL(15,2);
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_interest_rate DECIMAL(5,4);
    DECLARE v_expected_interest DECIMAL(15,2);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Test failed: Interest calculation error' AS test_result;
        RESIGNAL;
    END;

    START TRANSACTION;
    
    -- Get account details before interest calculation
    SELECT a.interest_earned, a.balance, at.interest_rate
    INTO v_interest_before, v_balance, v_interest_rate
    FROM accounts a
    JOIN account_types at ON a.account_type_id = at.type_id
    WHERE a.account_id = 1;
    
    -- Calculate expected monthly interest
    SET v_expected_interest = ROUND(v_balance * (v_interest_rate / 12), 2);
    
    -- Run interest calculation
    CALL CalculateMonthlyInterest();
    
    -- Get interest after calculation
    SELECT interest_earned INTO v_interest_after FROM accounts WHERE account_id = 1;
    
    IF v_interest_after >= v_interest_before THEN
        SELECT 'PASS: Interest calculation test successful' AS test_result,
               v_interest_before AS interest_before,
               v_interest_after AS interest_after,
               v_expected_interest AS expected_interest;
    ELSE
        SELECT 'FAIL: Interest calculation test failed' AS test_result;
    END IF;
    
    ROLLBACK; -- Don't actually apply the test interest
END //

-- Test authentication
CREATE PROCEDURE TestAuthentication()
BEGIN
    DECLARE v_user_id INT;
    DECLARE v_result VARCHAR(255);
    
    -- Test valid login
    CALL AuthenticateUser('johndoe', 'password123', '192.168.1.200', 'Test Browser', v_user_id, v_result);
    
    IF v_result = 'Login successful' AND v_user_id = 1 THEN
        SELECT 'PASS: Authentication test successful' AS test_result,
               v_user_id AS authenticated_user_id;
    ELSE
        SELECT 'FAIL: Authentication test failed' AS test_result, v_result AS error_message;
    END IF;
    
    -- Test invalid login
    CALL AuthenticateUser('johndoe', 'wrongpassword', '192.168.1.200', 'Test Browser', v_user_id, v_result);
    
    IF v_result != 'Login successful' AND v_user_id IS NULL THEN
        SELECT 'PASS: Invalid authentication test successful' AS test_result;
    ELSE
        SELECT 'FAIL: Invalid authentication test failed' AS test_result, 
               'System allowed invalid login' AS error_message;
    END IF;
END //

-- Test transfer functionality
CREATE PROCEDURE TestTransferFunctionality()
BEGIN
    DECLARE v_from_trans_id INT;
    DECLARE v_to_trans_id INT;
    DECLARE v_result VARCHAR(255);
    DECLARE v_from_balance_before DECIMAL(15,2);
    DECLARE v_to_balance_before DECIMAL(15,2);
    DECLARE v_from_balance_after DECIMAL(15,2);
    DECLARE v_to_balance_after DECIMAL(15,2);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Test failed: Transfer functionality error' AS test_result;
        RESIGNAL;
    END;

    START TRANSACTION;
    
    -- Get initial balances
    SELECT balance INTO v_from_balance_before FROM accounts WHERE account_id = 1;
    SELECT balance INTO v_to_balance_before FROM accounts WHERE account_id = 2;
    
    -- Test transfer
    CALL TransferFunds(1, 2, 100.00, 1, 'Test transfer', 'TESTXFER001', v_from_trans_id, v_to_trans_id, v_result);
    
    -- Get final balances
    SELECT balance INTO v_from_balance_after FROM accounts WHERE account_id = 1;
    SELECT balance INTO v_to_balance_after FROM accounts WHERE account_id = 2;
    
    IF v_result = 'Transfer completed successfully' AND 
       v_from_balance_after = v_from_balance_before - 100.00 AND
       v_to_balance_after = v_to_balance_before + 100.00 THEN
        SELECT 'PASS: Transfer functionality test successful' AS test_result,
               v_from_trans_id AS from_transaction_id,
               v_to_trans_id AS to_transaction_id;
    ELSE
        SELECT 'FAIL: Transfer functionality test failed' AS test_result, v_result AS error_message;
    END IF;
    
    ROLLBACK; -- Don't actually process the test transfer
END //

-- Run all tests
CREATE PROCEDURE RunAllTests()
BEGIN
    SELECT '========================================' AS separator;
    SELECT 'BANKING SYSTEM TEST SUITE' AS title;
    SELECT '========================================' AS separator;
    
    SELECT 'Running Account Creation Test...' AS status;
    CALL TestAccountCreation();
    
    SELECT 'Running Transaction Processing Test...' AS status;
    CALL TestTransactionProcessing();
    
    SELECT 'Running Fraud Detection Test...' AS status;
    CALL TestFraudDetection();
    
    SELECT 'Running Interest Calculation Test...' AS status;
    CALL TestInterestCalculation();
    
    SELECT 'Running Authentication Test...' AS status;
    CALL TestAuthentication();
    
    SELECT 'Running Transfer Functionality Test...' AS status;
    CALL TestTransferFunctionality();
    
    SELECT '========================================' AS separator;
    SELECT 'TEST SUITE COMPLETED' AS title;
    SELECT '========================================' AS separator;
END //

DELIMITER ;

-- =====================================================
-- DATA VALIDATION QUERIES
-- =====================================================

-- Check data integrity
SELECT 'Data Integrity Check' AS check_type;

-- Verify all accounts have valid users
SELECT 
    'Accounts with invalid users' AS check_name,
    COUNT(*) AS count
FROM accounts a
LEFT JOIN users u ON a.user_id = u.user_id
WHERE u.user_id IS NULL;

-- Verify all transactions have valid accounts
SELECT 
    'Transactions with invalid accounts' AS check_name,
    COUNT(*) AS count
FROM transactions t
LEFT JOIN accounts a ON t.account_id = a.account_id
WHERE a.account_id IS NULL;

-- Verify balance consistency
SELECT 
    'Accounts with balance inconsistencies' AS check_name,
    COUNT(*) AS count
FROM accounts a
WHERE a.available_balance > a.balance;

-- Check for orphaned records
SELECT 
    'Orphaned account owners' AS check_name,
    COUNT(*) AS count
FROM account_owners ao
LEFT JOIN accounts a ON ao.account_id = a.account_id
LEFT JOIN users u ON ao.user_id = u.user_id
WHERE a.account_id IS NULL OR u.user_id IS NULL;

COMMIT;
