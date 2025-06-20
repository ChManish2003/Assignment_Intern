-- =====================================================
-- DevifyX Banking System - Stored Procedures
-- =====================================================
-- This script contains all stored procedures for banking operations
-- =====================================================

USE banking_system;

DELIMITER //

-- =====================================================
-- ACCOUNT MANAGEMENT PROCEDURES
-- =====================================================

-- Procedure to create a new account
CREATE PROCEDURE CreateAccount(
    IN p_user_id INT,
    IN p_account_type_id INT,
    IN p_currency_id INT,
    IN p_initial_deposit DECIMAL(15,2),
    OUT p_account_id INT,
    OUT p_account_number VARCHAR(20),
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_account_count INT DEFAULT 0;
    DECLARE v_min_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_user_exists INT DEFAULT 0;
    DECLARE v_type_exists INT DEFAULT 0;
    DECLARE v_currency_exists INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'Error creating account: Database error occurred';
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Validate inputs
    SELECT COUNT(*) INTO v_user_exists FROM users WHERE user_id = p_user_id AND is_active = TRUE;
    SELECT COUNT(*) INTO v_type_exists FROM account_types WHERE type_id = p_account_type_id AND is_active = TRUE;
    SELECT COUNT(*) INTO v_currency_exists FROM currencies WHERE currency_id = p_currency_id AND is_active = TRUE;

    IF v_user_exists = 0 THEN
        SET p_result_message = 'Invalid or inactive user';
        ROLLBACK;
    ELSEIF v_type_exists = 0 THEN
        SET p_result_message = 'Invalid or inactive account type';
        ROLLBACK;
    ELSEIF v_currency_exists = 0 THEN
        SET p_result_message = 'Invalid or inactive currency';
        ROLLBACK;
    ELSE
        -- Get minimum balance requirement
        SELECT minimum_balance INTO v_min_balance 
        FROM account_types 
        WHERE type_id = p_account_type_id;

        -- Check if initial deposit meets minimum balance
        IF p_initial_deposit < v_min_balance THEN
            SET p_result_message = CONCAT('Initial deposit must be at least $', v_min_balance);
            ROLLBACK;
        ELSE
            -- Generate account number
            SELECT COUNT(*) + 1 INTO v_account_count FROM accounts;
            SET p_account_number = CONCAT('ACC', LPAD(p_user_id, 3, '0'), LPAD(v_account_count, 6, '0'));

            -- Create the account
            INSERT INTO accounts (account_number, user_id, account_type_id, currency_id, balance, available_balance)
            VALUES (p_account_number, p_user_id, p_account_type_id, p_currency_id, p_initial_deposit, p_initial_deposit);

            SET p_account_id = LAST_INSERT_ID();

            -- Add primary ownership
            INSERT INTO account_owners (account_id, user_id, ownership_type, permissions)
            VALUES (p_account_id, p_user_id, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE');

            -- Record initial deposit transaction if amount > 0
            IF p_initial_deposit > 0 THEN
                CALL RecordTransaction(p_account_id, 1, p_initial_deposit, p_currency_id, 'Initial deposit', NULL, NULL, @trans_id, @trans_result);
            END IF;

            SET p_result_message = 'Account created successfully';
            COMMIT;
        END IF;
    END IF;
END //

-- Procedure to close an account
CREATE PROCEDURE CloseAccount(
    IN p_account_id INT,
    IN p_user_id INT,
    IN p_reason TEXT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_owner_check INT DEFAULT 0;
    DECLARE v_account_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'Error closing account: Database error occurred';
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Check if user has permission to close account
    SELECT COUNT(*) INTO v_owner_check 
    FROM account_owners 
    WHERE account_id = p_account_id AND user_id = p_user_id 
    AND FIND_IN_SET('CLOSE', permissions) > 0;

    -- Get account details
    SELECT balance, status INTO v_balance, v_account_status 
    FROM accounts 
    WHERE account_id = p_account_id;

    IF v_owner_check = 0 THEN
        SET p_result_message = 'User does not have permission to close this account';
        ROLLBACK;
    ELSEIF v_account_status = 'CLOSED' THEN
        SET p_result_message = 'Account is already closed';
        ROLLBACK;
    ELSEIF v_balance > 0 THEN
        SET p_result_message = 'Cannot close account with positive balance. Please withdraw all funds first.';
        ROLLBACK;
    ELSEIF v_balance < 0 THEN
        SET p_result_message = 'Cannot close account with negative balance. Please settle the debt first.';
        ROLLBACK;
    ELSE
        -- Close the account
        UPDATE accounts 
        SET status = 'CLOSED', closed_date = CURDATE(), updated_at = CURRENT_TIMESTAMP
        WHERE account_id = p_account_id;

        -- Log the closure
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (p_user_id, 'DATA_MODIFICATION', CONCAT('Account ', p_account_id, ' closed. Reason: ', IFNULL(p_reason, 'Not specified')), 'MEDIUM');

        SET p_result_message = 'Account closed successfully';
        COMMIT;
    END IF;
END //

-- =====================================================
-- TRANSACTION PROCEDURES
-- =====================================================

-- Core procedure to record transactions
CREATE PROCEDURE RecordTransaction(
    IN p_account_id INT,
    IN p_transaction_type_id INT,
    IN p_amount DECIMAL(15,2),
    IN p_currency_id INT,
    IN p_description TEXT,
    IN p_reference_number VARCHAR(100),
    IN p_related_account_id INT,
    OUT p_transaction_id INT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_balance_before DECIMAL(15,2) DEFAULT 0;
    DECLARE v_balance_after DECIMAL(15,2) DEFAULT 0;
    DECLARE v_available_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_account_status VARCHAR(20);
    DECLARE v_transaction_number VARCHAR(50);
    DECLARE v_affects_balance BOOLEAN DEFAULT TRUE;
    DECLARE v_overdraft_limit DECIMAL(15,2) DEFAULT 0;
    DECLARE v_exchange_rate DECIMAL(10,6) DEFAULT 1.000000;
    DECLARE v_type_name VARCHAR(50);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'Transaction failed: Database error occurred';
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Get current account details
    SELECT a.balance, a.available_balance, a.status, at.overdraft_limit
    INTO v_balance_before, v_available_balance, v_account_status, v_overdraft_limit
    FROM accounts a
    JOIN account_types at ON a.account_type_id = at.type_id
    WHERE a.account_id = p_account_id;

    -- Get transaction type details
    SELECT affects_balance, type_name INTO v_affects_balance, v_type_name
    FROM transaction_types 
    WHERE type_id = p_transaction_type_id;

    -- Get exchange rate if different currency
    IF p_currency_id != 1 THEN
        SELECT exchange_rate INTO v_exchange_rate FROM currencies WHERE currency_id = p_currency_id;
    END IF;

    -- Check account status
    IF v_account_status != 'ACTIVE' THEN
        SET p_result_message = 'Transaction failed: Account is not active';
        ROLLBACK;
    ELSE
        -- Calculate new balance
        IF v_affects_balance THEN
            IF v_type_name IN ('DEPOSIT', 'TRANSFER_IN', 'INTEREST_CREDIT', 'REFUND', 'DIRECT_DEPOSIT', 'CHECK_DEPOSIT') THEN
                SET v_balance_after = v_balance_before + (p_amount * v_exchange_rate);
            ELSE
                SET v_balance_after = v_balance_before - (p_amount * v_exchange_rate);
                
                -- Check for sufficient funds (including overdraft)
                IF v_balance_after < (0 - v_overdraft_limit) THEN
                    SET p_result_message = 'Transaction failed: Insufficient funds';
                    ROLLBACK;
                    LEAVE;
                END IF;
            END IF;
        ELSE
            SET v_balance_after = v_balance_before;
        END IF;

        -- Generate transaction number
        SET v_transaction_number = CONCAT('TXN', DATE_FORMAT(NOW(), '%Y%m%d'), LPAD(CONNECTION_ID(), 6, '0'), LPAD(MICROSECOND(NOW()), 6, '0'));

        -- Insert transaction record
        INSERT INTO transactions (
            transaction_number, account_id, transaction_type_id, amount, currency_id, 
            exchange_rate, balance_before, balance_after, description, reference_number, 
            related_account_id, status, transaction_date
        ) VALUES (
            v_transaction_number, p_account_id, p_transaction_type_id, p_amount, p_currency_id,
            v_exchange_rate, v_balance_before, v_balance_after, p_description, p_reference_number,
            p_related_account_id, 'COMPLETED', CURRENT_TIMESTAMP
        );

        SET p_transaction_id = LAST_INSERT_ID();

        -- Update account balance if transaction affects balance
        IF v_affects_balance THEN
            UPDATE accounts 
            SET balance = v_balance_after, 
                available_balance = v_balance_after,
                last_transaction_date = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
            WHERE account_id = p_account_id;
        END IF;

        -- Update transaction status
        UPDATE transactions 
        SET status = 'COMPLETED', processed_date = CURRENT_TIMESTAMP 
        WHERE transaction_id = p_transaction_id;

        SET p_result_message = 'Transaction completed successfully';
        COMMIT;
    END IF;
END //

-- Procedure for deposits
CREATE PROCEDURE MakeDeposit(
    IN p_account_id INT,
    IN p_amount DECIMAL(15,2),
    IN p_currency_id INT,
    IN p_description TEXT,
    IN p_reference_number VARCHAR(100),
    OUT p_transaction_id INT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_deposit_type_id INT;
    
    -- Get deposit transaction type ID
    SELECT type_id INTO v_deposit_type_id FROM transaction_types WHERE type_name = 'DEPOSIT';
    
    -- Call the main transaction procedure
    CALL RecordTransaction(
        p_account_id, v_deposit_type_id, p_amount, p_currency_id, 
        p_description, p_reference_number, NULL, 
        p_transaction_id, p_result_message
    );
END //

-- Procedure for withdrawals
CREATE PROCEDURE MakeWithdrawal(
    IN p_account_id INT,
    IN p_amount DECIMAL(15,2),
    IN p_currency_id INT,
    IN p_description TEXT,
    IN p_reference_number VARCHAR(100),
    OUT p_transaction_id INT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_withdrawal_type_id INT;
    
    -- Get withdrawal transaction type ID
    SELECT type_id INTO v_withdrawal_type_id FROM transaction_types WHERE type_name = 'WITHDRAWAL';
    
    -- Call the main transaction procedure
    CALL RecordTransaction(
        p_account_id, v_withdrawal_type_id, p_amount, p_currency_id, 
        p_description, p_reference_number, NULL, 
        p_transaction_id, p_result_message
    );
END //

-- Procedure for transfers between accounts
CREATE PROCEDURE TransferFunds(
    IN p_from_account_id INT,
    IN p_to_account_id INT,
    IN p_amount DECIMAL(15,2),
    IN p_currency_id INT,
    IN p_description TEXT,
    IN p_reference_number VARCHAR(100),
    OUT p_from_transaction_id INT,
    OUT p_to_transaction_id INT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_transfer_out_type_id INT;
    DECLARE v_transfer_in_type_id INT;
    DECLARE v_from_result VARCHAR(255);
    DECLARE v_to_result VARCHAR(255);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_message = 'Transfer failed: Database error occurred';
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Get transaction type IDs
    SELECT type_id INTO v_transfer_out_type_id FROM transaction_types WHERE type_name = 'TRANSFER_OUT';
    SELECT type_id INTO v_transfer_in_type_id FROM transaction_types WHERE type_name = 'TRANSFER_IN';

    -- Validate accounts exist and are different
    IF p_from_account_id = p_to_account_id THEN
        SET p_result_message = 'Cannot transfer to the same account';
        ROLLBACK;
    ELSE
        -- Process outgoing transfer
        CALL RecordTransaction(
            p_from_account_id, v_transfer_out_type_id, p_amount, p_currency_id, 
            CONCAT('Transfer to account ', p_to_account_id, ': ', IFNULL(p_description, '')), 
            p_reference_number, p_to_account_id, 
            p_from_transaction_id, v_from_result
        );

        -- If outgoing transfer successful, process incoming transfer
        IF v_from_result = 'Transaction completed successfully' THEN
            CALL RecordTransaction(
                p_to_account_id, v_transfer_in_type_id, p_amount, p_currency_id, 
                CONCAT('Transfer from account ', p_from_account_id, ': ', IFNULL(p_description, '')), 
                p_reference_number, p_from_account_id, 
                p_to_transaction_id, v_to_result
            );

            IF v_to_result = 'Transaction completed successfully' THEN
                SET p_result_message = 'Transfer completed successfully';
                COMMIT;
            ELSE
                SET p_result_message = CONCAT('Transfer failed: ', v_to_result);
                ROLLBACK;
            END IF;
        ELSE
            SET p_result_message = CONCAT('Transfer failed: ', v_from_result);
            ROLLBACK;
        END IF;
    END IF;
END //

-- =====================================================
-- INTEREST CALCULATION PROCEDURES
-- =====================================================

-- Procedure to calculate and credit interest for all eligible accounts
CREATE PROCEDURE CalculateMonthlyInterest()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_account_id INT;
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_interest_rate DECIMAL(5,4);
    DECLARE v_interest_amount DECIMAL(15,2);
    DECLARE v_currency_id INT;
    DECLARE v_last_calculation DATE;
    DECLARE v_interest_type_id INT;
    DECLARE v_transaction_id INT;
    DECLARE v_result_message VARCHAR(255);
    
    -- Cursor for accounts eligible for interest
    DECLARE interest_cursor CURSOR FOR
        SELECT a.account_id, a.balance, a.currency_id, at.interest_rate, a.last_interest_calculation
        FROM accounts a
        JOIN account_types at ON a.account_type_id = at.type_id
        WHERE a.status = 'ACTIVE' 
        AND at.interest_rate > 0
        AND a.balance > 0
        AND (a.last_interest_calculation IS NULL OR a.last_interest_calculation < LAST_DAY(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)));
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Get interest credit transaction type
    SELECT type_id INTO v_interest_type_id FROM transaction_types WHERE type_name = 'INTEREST_CREDIT';

    OPEN interest_cursor;

    interest_loop: LOOP
        FETCH interest_cursor INTO v_account_id, v_balance, v_currency_id, v_interest_rate, v_last_calculation;
        
        IF done THEN
            LEAVE interest_loop;
        END IF;

        -- Calculate monthly interest (annual rate / 12)
        SET v_interest_amount = ROUND(v_balance * (v_interest_rate / 12), 2);

        -- Only credit if interest amount is significant (> $0.01)
        IF v_interest_amount > 0.01 THEN
            -- Record interest transaction
            CALL RecordTransaction(
                v_account_id, v_interest_type_id, v_interest_amount, v_currency_id,
                CONCAT('Monthly interest credit - Rate: ', v_interest_rate * 100, '%'),
                CONCAT('INT', DATE_FORMAT(NOW(), '%Y%m')), NULL,
                v_transaction_id, v_result_message
            );

            -- Update interest earned and last calculation date
            UPDATE accounts 
            SET interest_earned = interest_earned + v_interest_amount,
                last_interest_calculation = CURDATE()
            WHERE account_id = v_account_id;
        END IF;
    END LOOP;

    CLOSE interest_cursor;
    COMMIT;

    -- Log the interest calculation completion
    INSERT INTO security_logs (action_type, description, severity)
    VALUES ('DATA_MODIFICATION', 'Monthly interest calculation completed', 'LOW');
END //

-- =====================================================
-- SECURITY AND AUTHENTICATION PROCEDURES
-- =====================================================

-- Procedure for user authentication
CREATE PROCEDURE AuthenticateUser(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_ip_address VARCHAR(45),
    IN p_user_agent TEXT,
    OUT p_user_id INT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_stored_hash VARCHAR(255);
    DECLARE v_salt VARCHAR(32);
    DECLARE v_failed_attempts INT DEFAULT 0;
    DECLARE v_account_locked BOOLEAN DEFAULT FALSE;
    DECLARE v_locked_until TIMESTAMP;
    DECLARE v_auth_id INT;
    DECLARE v_computed_hash VARCHAR(255);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_result_message = 'Authentication failed: System error';
        RESIGNAL;
    END;

    -- Get user authentication details
    SELECT ua.auth_id, ua.user_id, ua.password_hash, ua.salt, ua.failed_login_attempts, 
           ua.account_locked, ua.locked_until
    INTO v_auth_id, p_user_id, v_stored_hash, v_salt, v_failed_attempts, v_account_locked, v_locked_until
    FROM user_auth ua
    JOIN users u ON ua.user_id = u.user_id
    WHERE ua.username = p_username AND u.is_active = TRUE;

    IF p_user_id IS NULL THEN
        SET p_result_message = 'Invalid username or password';
        SET p_user_id = NULL;
        
        -- Log failed login attempt
        INSERT INTO security_logs (action_type, description, ip_address, user_agent, severity)
        VALUES ('LOGIN_FAILED', CONCAT('Failed login attempt for username: ', p_username), p_ip_address, p_user_agent, 'MEDIUM');
    ELSE
        -- Check if account is locked
        IF v_account_locked = TRUE AND (v_locked_until IS NULL OR v_locked_until > NOW()) THEN
            SET p_result_message = 'Account is locked due to multiple failed login attempts';
            SET p_user_id = NULL;
            
            INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
            VALUES (p_user_id, 'LOGIN_FAILED', 'Login attempt on locked account', p_ip_address, p_user_agent, 'HIGH');
        ELSE
            -- Compute hash with salt
            SET v_computed_hash = SHA2(CONCAT(p_password, v_salt), 256);
            
            IF v_computed_hash = v_stored_hash THEN
                -- Successful login
                UPDATE user_auth 
                SET last_login = NOW(), failed_login_attempts = 0, account_locked = FALSE, locked_until = NULL
                WHERE auth_id = v_auth_id;
                
                SET p_result_message = 'Login successful';
                
                INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
                VALUES (p_user_id, 'LOGIN_SUCCESS', 'Successful login', p_ip_address, p_user_agent, 'LOW');
            ELSE
                -- Failed login
                SET v_failed_attempts = v_failed_attempts + 1;
                
                -- Lock account if too many failed attempts
                IF v_failed_attempts >= 5 THEN
                    UPDATE user_auth 
                    SET failed_login_attempts = v_failed_attempts, 
                        account_locked = TRUE, 
                        locked_until = DATE_ADD(NOW(), INTERVAL 30 MINUTE)
                    WHERE auth_id = v_auth_id;
                    
                    SET p_result_message = 'Account locked due to multiple failed login attempts';
                    
                    INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
                    VALUES (p_user_id, 'ACCOUNT_LOCKED', 'Account locked after 5 failed login attempts', p_ip_address, p_user_agent, 'HIGH');
                ELSE
                    UPDATE user_auth 
                    SET failed_login_attempts = v_failed_attempts
                    WHERE auth_id = v_auth_id;
                    
                    SET p_result_message = CONCAT('Invalid password. ', (5 - v_failed_attempts), ' attempts remaining.');
                END IF;
                
                SET p_user_id = NULL;
                
                INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
                VALUES (p_user_id, 'LOGIN_FAILED', CONCAT('Failed login attempt #', v_failed_attempts), p_ip_address, p_user_agent, 'MEDIUM');
            END IF;
        END IF;
    END IF;
END //

-- =====================================================
-- REPORTING PROCEDURES
-- =====================================================

-- Procedure to generate monthly account statements
CREATE PROCEDURE GenerateMonthlyStatements(
    IN p_statement_month INT,
    IN p_statement_year INT
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_account_id INT;
    DECLARE v_period_start DATE;
    DECLARE v_period_end DATE;
    DECLARE v_opening_balance DECIMAL(15,2);
    DECLARE v_closing_balance DECIMAL(15,2);
    DECLARE v_total_deposits DECIMAL(15,2);
    DECLARE v_total_withdrawals DECIMAL(15,2);
    DECLARE v_total_fees DECIMAL(15,2);
    DECLARE v_interest_earned DECIMAL(15,2);
    DECLARE v_transaction_count INT;
    
    -- Cursor for active accounts
    DECLARE account_cursor CURSOR FOR
        SELECT account_id FROM accounts WHERE status = 'ACTIVE';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Set statement period
    SET v_period_start = DATE(CONCAT(p_statement_year, '-', LPAD(p_statement_month, 2, '0'), '-01'));
    SET v_period_end = LAST_DAY(v_period_start);

    OPEN account_cursor;

    statement_loop: LOOP
        FETCH account_cursor INTO v_account_id;
        
        IF done THEN
            LEAVE statement_loop;
        END IF;

        -- Get opening balance (balance at start of period)
        SELECT COALESCE(balance_after, 0) INTO v_opening_balance
        FROM transactions 
        WHERE account_id = v_account_id 
        AND transaction_date < v_period_start 
        ORDER BY transaction_date DESC, transaction_id DESC 
        LIMIT 1;

        -- Get closing balance (current balance or balance at end of period)
        SELECT COALESCE(balance_after, v_opening_balance) INTO v_closing_balance
        FROM transactions 
        WHERE account_id = v_account_id 
        AND transaction_date <= v_period_end 
        ORDER BY transaction_date DESC, transaction_id DESC 
        LIMIT 1;

        -- Calculate totals for the period
        SELECT 
            COALESCE(SUM(CASE WHEN tt.type_name IN ('DEPOSIT', 'TRANSFER_IN', 'DIRECT_DEPOSIT', 'CHECK_DEPOSIT') THEN t.amount ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN tt.type_name IN ('WITHDRAWAL', 'TRANSFER_OUT', 'ATM_WITHDRAWAL', 'BILL_PAYMENT') THEN t.amount ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN tt.type_name LIKE '%FEE%' OR tt.type_name = 'MONTHLY_MAINTENANCE' THEN t.amount ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN tt.type_name = 'INTEREST_CREDIT' THEN t.amount ELSE 0 END), 0),
            COUNT(*)
        INTO v_total_deposits, v_total_withdrawals, v_total_fees, v_interest_earned, v_transaction_count
        FROM transactions t
        JOIN transaction_types tt ON t.transaction_type_id = tt.type_id
        WHERE t.account_id = v_account_id 
        AND t.transaction_date BETWEEN v_period_start AND v_period_end
        AND t.status = 'COMPLETED';

        -- Insert statement record (avoid duplicates)
        INSERT IGNORE INTO account_statements (
            account_id, statement_period_start, statement_period_end,
            opening_balance, closing_balance, total_deposits, total_withdrawals,
            total_fees, interest_earned, transaction_count
        ) VALUES (
            v_account_id, v_period_start, v_period_end,
            v_opening_balance, v_closing_balance, v_total_deposits, v_total_withdrawals,
            v_total_fees, v_interest_earned, v_transaction_count
        );

    END LOOP;

    CLOSE account_cursor;
    COMMIT;

    -- Log statement generation
    INSERT INTO security_logs (action_type, description, severity)
    VALUES ('DATA_MODIFICATION', CONCAT('Monthly statements generated for ', p_statement_month, '/', p_statement_year), 'LOW');
END //

DELIMITER ;

-- =====================================================
-- GRANT PERMISSIONS (if needed for specific users)
-- =====================================================

-- Example: Create a banking application user with limited permissions
-- CREATE USER 'banking_app'@'localhost' IDENTIFIED BY 'secure_password';
-- GRANT SELECT, INSERT, UPDATE ON banking_system.* TO 'banking_app'@'localhost';
-- GRANT EXECUTE ON PROCEDURE banking_system.* TO 'banking_app'@'localhost';
-- FLUSH PRIVILEGES;

COMMIT;
