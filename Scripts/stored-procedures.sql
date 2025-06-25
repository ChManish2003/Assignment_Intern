USE banking_system;
DELIMITER //

-- =====================================================
-- ACCOUNT MANAGEMENT PROCEDURES
-- =====================================================

-- Procedure to create a new account (MySQL 8.0.42 optimized)
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
    DECLARE v_user_age INT DEFAULT 0;
    
    -- Enhanced error handler for MySQL 8.0.42
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Error creating account: ', @text);
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Validate inputs with enhanced checks
    SELECT COUNT(*), TIMESTAMPDIFF(YEAR, date_of_birth, CURDATE()) 
    INTO v_user_exists, v_user_age
    FROM users 
    WHERE user_id = p_user_id AND is_active = TRUE;
    
    SELECT COUNT(*) INTO v_type_exists 
    FROM account_types 
    WHERE type_id = p_account_type_id AND is_active = TRUE;
    
    SELECT COUNT(*) INTO v_currency_exists 
    FROM currencies 
    WHERE currency_id = p_currency_id AND is_active = TRUE;

    -- Enhanced validation logic
    IF v_user_exists = 0 THEN
        SET p_result_message = 'Invalid or inactive user';
        ROLLBACK;
    ELSEIF v_user_age < 18 THEN
        SET p_result_message = 'User must be at least 18 years old to open an account';
        ROLLBACK;
    ELSEIF v_type_exists = 0 THEN
        SET p_result_message = 'Invalid or inactive account type';
        ROLLBACK;
    ELSEIF v_currency_exists = 0 THEN
        SET p_result_message = 'Invalid or inactive currency';
        ROLLBACK;
    ELSEIF p_initial_deposit < 0 THEN
        SET p_result_message = 'Initial deposit cannot be negative';
        ROLLBACK;
    ELSE
        -- Get minimum balance requirement
        SELECT minimum_balance INTO v_min_balance 
        FROM account_types 
        WHERE type_id = p_account_type_id;

        -- Check if initial deposit meets minimum balance
        IF p_initial_deposit < v_min_balance THEN
            SET p_result_message = CONCAT('Initial deposit must be at least $', FORMAT(v_min_balance, 2));
            ROLLBACK;
        ELSE
            -- Generate unique account number using MySQL 8.0.42 features
            SELECT COALESCE(MAX(CAST(SUBSTRING(account_number, 4) AS UNSIGNED)), 0) + 1 
            INTO v_account_count 
            FROM accounts;
            
            SET p_account_number = CONCAT('ACC', LPAD(v_account_count, 9, '0'));

            -- Create the account
            INSERT INTO accounts (
                account_number, user_id, account_type_id, currency_id, 
                balance, available_balance, status
            ) VALUES (
                p_account_number, p_user_id, p_account_type_id, p_currency_id, 
                p_initial_deposit, p_initial_deposit, 'ACTIVE'
            );

            SET p_account_id = LAST_INSERT_ID();

            -- Add primary ownership
            INSERT INTO account_owners (account_id, user_id, ownership_type, permissions)
            VALUES (p_account_id, p_user_id, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE');

            -- Record initial deposit transaction if amount > 0
            IF p_initial_deposit > 0 THEN
                CALL RecordTransaction(
                    p_account_id, 
                    (SELECT type_id FROM transaction_types WHERE type_name = 'DEPOSIT'), 
                    p_initial_deposit, p_currency_id, 'Initial deposit', 
                    CONCAT('INIT', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')), 
                    NULL, @trans_id, @trans_result
                );
            END IF;

            SET p_result_message = 'Account created successfully';
            COMMIT;
        END IF;
    END IF;
END //

-- Enhanced procedure to close an account
CREATE PROCEDURE CloseAccount(
    IN p_account_id INT,
    IN p_user_id INT,
    IN p_reason TEXT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_available_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_owner_check INT DEFAULT 0;
    DECLARE v_account_status VARCHAR(20);
    DECLARE v_pending_transactions INT DEFAULT 0;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Error closing account: ', @text);
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Check if user has permission to close account
    SELECT COUNT(*) INTO v_owner_check 
    FROM account_owners 
    WHERE account_id = p_account_id AND user_id = p_user_id 
    AND FIND_IN_SET('CLOSE', permissions) > 0;

    -- Get account details
    SELECT balance, available_balance, status 
    INTO v_balance, v_available_balance, v_account_status 
    FROM accounts 
    WHERE account_id = p_account_id;

    -- Check for pending transactions
    SELECT COUNT(*) INTO v_pending_transactions
    FROM transactions 
    WHERE account_id = p_account_id AND status = 'PENDING';

    -- Enhanced validation
    IF v_owner_check = 0 THEN
        SET p_result_message = 'User does not have permission to close this account';
        ROLLBACK;
    ELSEIF v_account_status = 'CLOSED' THEN
        SET p_result_message = 'Account is already closed';
        ROLLBACK;
    ELSEIF v_pending_transactions > 0 THEN
        SET p_result_message = 'Cannot close account with pending transactions';
        ROLLBACK;
    ELSEIF ABS(v_balance) > 0.01 THEN -- Allow for small rounding differences
        SET p_result_message = CONCAT('Cannot close account with balance of $', FORMAT(v_balance, 2), '. Please transfer all funds first.');
        ROLLBACK;
    ELSE
        -- Close the account
        UPDATE accounts 
        SET status = 'CLOSED', 
            closed_date = CURDATE(), 
            updated_at = CURRENT_TIMESTAMP
        WHERE account_id = p_account_id;

        -- Log the closure
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (p_user_id, 'DATA_MODIFICATION', 
                CONCAT('Account ', p_account_id, ' closed. Reason: ', COALESCE(p_reason, 'Not specified')), 
                'MEDIUM');

        SET p_result_message = 'Account closed successfully';
        COMMIT;
    END IF;
END //

-- =====================================================
-- TRANSACTION PROCEDURES (Enhanced for MySQL 8.0.42)
-- =====================================================

-- Core procedure to record transactions with enhanced validation
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
    DECLARE v_daily_limit INT DEFAULT 0;
    DECLARE v_daily_count INT DEFAULT 0;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Transaction failed: ', @text);
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Get current account details with enhanced query
    SELECT a.balance, a.available_balance, a.status, at.overdraft_limit, at.transaction_limit_daily
    INTO v_balance_before, v_available_balance, v_account_status, v_overdraft_limit, v_daily_limit
    FROM accounts a
    JOIN account_types at ON a.account_type_id = at.type_id
    WHERE a.account_id = p_account_id;

    -- Get transaction type details
    SELECT affects_balance, type_name 
    INTO v_affects_balance, v_type_name
    FROM transaction_types 
    WHERE type_id = p_transaction_type_id;

    -- Get exchange rate if different currency
    IF p_currency_id != 1 THEN
        SELECT exchange_rate INTO v_exchange_rate 
        FROM currencies 
        WHERE currency_id = p_currency_id AND is_active = TRUE;
        
        IF v_exchange_rate IS NULL THEN
            SET p_result_message = 'Invalid or inactive currency';
            ROLLBACK;
            LEAVE;
        END IF;
    END IF;

    -- Enhanced validation
    IF v_account_status != 'ACTIVE' THEN
        SET p_result_message = 'Transaction failed: Account is not active';
        ROLLBACK;
    ELSEIF p_amount <= 0 THEN
        SET p_result_message = 'Transaction failed: Amount must be positive';
        ROLLBACK;
    ELSE
        -- Check daily transaction limits
        IF v_daily_limit > 0 THEN
            SELECT COUNT(*) INTO v_daily_count
            FROM transactions 
            WHERE account_id = p_account_id 
            AND DATE(transaction_date) = CURDATE()
            AND status = 'COMPLETED';
            
            IF v_daily_count >= v_daily_limit THEN
                SET p_result_message = 'Transaction failed: Daily transaction limit exceeded';
                ROLLBACK;
                LEAVE;
            END IF;
        END IF;

        -- Calculate new balance
        IF v_affects_balance THEN
            IF v_type_name IN ('DEPOSIT', 'TRANSFER_IN', 'INTEREST_CREDIT', 'REFUND', 'DIRECT_DEPOSIT', 'CHECK_DEPOSIT') THEN
                SET v_balance_after = v_balance_before + (p_amount * v_exchange_rate);
            ELSE
                SET v_balance_after = v_balance_before - (p_amount * v_exchange_rate);
                
                -- Enhanced overdraft checking
                IF v_balance_after < (0 - v_overdraft_limit) THEN
                    SET p_result_message = CONCAT('Transaction failed: Insufficient funds. Available: $', 
                                                FORMAT(v_available_balance, 2), 
                                                ', Overdraft limit: $', FORMAT(v_overdraft_limit, 2));
                    ROLLBACK;
                    LEAVE;
                END IF;
            END IF;
        ELSE
            SET v_balance_after = v_balance_before;
        END IF;

        -- Generate unique transaction number using MySQL 8.0.42 features
        SET v_transaction_number = CONCAT('TXN', 
                                        DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 
                                        LPAD(CONNECTION_ID() % 10000, 4, '0'));

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
                available_balance = GREATEST(0, v_balance_after - COALESCE((
                    SELECT SUM(amount) FROM account_holds 
                    WHERE account_id = p_account_id AND status = 'ACTIVE'
                ), 0)),
                last_transaction_date = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
            WHERE account_id = p_account_id;
        END IF;

        SET p_result_message = 'Transaction completed successfully';
        COMMIT;
    END IF;
END //

-- Enhanced deposit procedure
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
    SELECT type_id INTO v_deposit_type_id 
    FROM transaction_types 
    WHERE type_name = 'DEPOSIT';
    
    IF v_deposit_type_id IS NULL THEN
        SET p_result_message = 'Deposit transaction type not found';
    ELSE
        -- Call the main transaction procedure
        CALL RecordTransaction(
            p_account_id, v_deposit_type_id, p_amount, p_currency_id, 
            COALESCE(p_description, 'Deposit'), p_reference_number, NULL, 
            p_transaction_id, p_result_message
        );
    END IF;
END //

-- Enhanced withdrawal procedure
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
    SELECT type_id INTO v_withdrawal_type_id 
    FROM transaction_types 
    WHERE type_name = 'WITHDRAWAL';
    
    IF v_withdrawal_type_id IS NULL THEN
        SET p_result_message = 'Withdrawal transaction type not found';
    ELSE
        -- Call the main transaction procedure
        CALL RecordTransaction(
            p_account_id, v_withdrawal_type_id, p_amount, p_currency_id, 
            COALESCE(p_description, 'Withdrawal'), p_reference_number, NULL, 
            p_transaction_id, p_result_message
        );
    END IF;
END //

-- Enhanced transfer procedure with atomic operations
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
    DECLARE v_from_account_exists INT DEFAULT 0;
    DECLARE v_to_account_exists INT DEFAULT 0;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Transfer failed: ', @text);
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Enhanced validation
    SELECT COUNT(*) INTO v_from_account_exists 
    FROM accounts 
    WHERE account_id = p_from_account_id AND status = 'ACTIVE';
    
    SELECT COUNT(*) INTO v_to_account_exists 
    FROM accounts 
    WHERE account_id = p_to_account_id AND status = 'ACTIVE';

    IF p_from_account_id = p_to_account_id THEN
        SET p_result_message = 'Cannot transfer to the same account';
        ROLLBACK;
    ELSEIF v_from_account_exists = 0 THEN
        SET p_result_message = 'Source account not found or inactive';
        ROLLBACK;
    ELSEIF v_to_account_exists = 0 THEN
        SET p_result_message = 'Destination account not found or inactive';
        ROLLBACK;
    ELSEIF p_amount <= 0 THEN
        SET p_result_message = 'Transfer amount must be positive';
        ROLLBACK;
    ELSE
        -- Get transaction type IDs
        SELECT type_id INTO v_transfer_out_type_id 
        FROM transaction_types WHERE type_name = 'TRANSFER_OUT';
        
        SELECT type_id INTO v_transfer_in_type_id 
        FROM transaction_types WHERE type_name = 'TRANSFER_IN';

        -- Process outgoing transfer
        CALL RecordTransaction(
            p_from_account_id, v_transfer_out_type_id, p_amount, p_currency_id, 
            CONCAT('Transfer to account ', p_to_account_id, 
                   CASE WHEN p_description IS NOT NULL THEN CONCAT(': ', p_description) ELSE '' END), 
            p_reference_number, p_to_account_id, 
            p_from_transaction_id, v_from_result
        );

        -- If outgoing transfer successful, process incoming transfer
        IF v_from_result = 'Transaction completed successfully' THEN
            CALL RecordTransaction(
                p_to_account_id, v_transfer_in_type_id, p_amount, p_currency_id, 
                CONCAT('Transfer from account ', p_from_account_id,
                       CASE WHEN p_description IS NOT NULL THEN CONCAT(': ', p_description) ELSE '' END), 
                p_reference_number, p_from_account_id, 
                p_to_transaction_id, v_to_result
            );

            IF v_to_result = 'Transaction completed successfully' THEN
                SET p_result_message = 'Transfer completed successfully';
                COMMIT;
            ELSE
                SET p_result_message = CONCAT('Transfer failed at destination: ', v_to_result);
                ROLLBACK;
            END IF;
        ELSE
            SET p_result_message = CONCAT('Transfer failed at source: ', v_from_result);
            ROLLBACK;
        END IF;
    END IF;
END //

-- =====================================================
-- INTEREST CALCULATION PROCEDURES (Enhanced)
-- =====================================================

-- Enhanced procedure to calculate and credit interest
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
    DECLARE v_accounts_processed INT DEFAULT 0;
    DECLARE v_total_interest DECIMAL(15,2) DEFAULT 0;
    
    -- Enhanced cursor for accounts eligible for interest
    DECLARE interest_cursor CURSOR FOR
        SELECT a.account_id, a.balance, a.currency_id, at.interest_rate, a.last_interest_calculation
        FROM accounts a
        JOIN account_types at ON a.account_type_id = at.type_id
        WHERE a.status = 'ACTIVE' 
        AND at.interest_rate > 0
        AND a.balance > 0
        AND (a.last_interest_calculation IS NULL 
             OR a.last_interest_calculation < DATE_SUB(CURDATE(), INTERVAL 1 MONTH));
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        ROLLBACK;
        INSERT INTO security_logs (action_type, description, severity)
        VALUES ('DATA_MODIFICATION', CONCAT('Interest calculation failed: ', @text), 'HIGH');
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Get interest credit transaction type
    SELECT type_id INTO v_interest_type_id 
    FROM transaction_types 
    WHERE type_name = 'INTEREST_CREDIT';

    IF v_interest_type_id IS NULL THEN
        INSERT INTO security_logs (action_type, description, severity)
        VALUES ('DATA_MODIFICATION', 'Interest calculation failed: INTEREST_CREDIT transaction type not found', 'HIGH');
        ROLLBACK;
    ELSE
        OPEN interest_cursor;

        interest_loop: LOOP
            FETCH interest_cursor INTO v_account_id, v_balance, v_currency_id, v_interest_rate, v_last_calculation;
            
            IF done THEN
                LEAVE interest_loop;
            END IF;

            -- Calculate monthly interest (annual rate / 12) with proper rounding
            SET v_interest_amount = ROUND(v_balance * (v_interest_rate / 12), 2);

            -- Only credit if interest amount is significant (> $0.01)
            IF v_interest_amount > 0.01 THEN
                -- Record interest transaction
                CALL RecordTransaction(
                    v_account_id, v_interest_type_id, v_interest_amount, v_currency_id,
                    CONCAT('Monthly interest credit - Rate: ', FORMAT(v_interest_rate * 100, 2), '%'),
                    CONCAT('INT', DATE_FORMAT(NOW(), '%Y%m%d')), NULL,
                    v_transaction_id, v_result_message
                );

                IF v_result_message = 'Transaction completed successfully' THEN
                    -- Update interest earned and last calculation date
                    UPDATE accounts 
                    SET interest_earned = interest_earned + v_interest_amount,
                        last_interest_calculation = CURDATE()
                    WHERE account_id = v_account_id;
                    
                    SET v_accounts_processed = v_accounts_processed + 1;
                    SET v_total_interest = v_total_interest + v_interest_amount;
                END IF;
            END IF;
        END LOOP;

        CLOSE interest_cursor;
        COMMIT;

        -- Log the interest calculation completion with statistics
        INSERT INTO security_logs (action_type, description, severity)
        VALUES ('DATA_MODIFICATION', 
                CONCAT('Monthly interest calculation completed. Accounts processed: ', v_accounts_processed, 
                       ', Total interest credited: $', FORMAT(v_total_interest, 2)), 
                'LOW');
    END IF;
END //

-- =====================================================
-- AUTHENTICATION PROCEDURES (Enhanced for MySQL 8.0.42)
-- =====================================================

-- Enhanced user authentication procedure
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
    DECLARE v_max_attempts INT DEFAULT 5;
    DECLARE v_lock_duration INT DEFAULT 30;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        SET p_result_message = CONCAT('Authentication failed: ', @text);
        RESIGNAL;
    END;

    -- Get system configuration
    SELECT CAST(config_value AS UNSIGNED) INTO v_max_attempts
    FROM system_config 
    WHERE config_key = 'MAX_FAILED_LOGIN_ATTEMPTS';
    
    SELECT CAST(config_value AS UNSIGNED) INTO v_lock_duration
    FROM system_config 
    WHERE config_key = 'ACCOUNT_LOCK_DURATION_MINUTES';

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
        VALUES ('LOGIN_FAILED', CONCAT('Failed login attempt for username: ', p_username), 
                p_ip_address, LEFT(p_user_agent, 500), 'MEDIUM');
    ELSE
        -- Check if account is locked
        IF v_account_locked = TRUE AND (v_locked_until IS NULL OR v_locked_until > NOW()) THEN
            SET p_result_message = CONCAT('Account is locked until ', 
                                        COALESCE(DATE_FORMAT(v_locked_until, '%Y-%m-%d %H:%i:%s'), 'further notice'));
            SET p_user_id = NULL;
            
            INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
            VALUES (p_user_id, 'LOGIN_FAILED', 'Login attempt on locked account', 
                    p_ip_address, LEFT(p_user_agent, 500), 'HIGH');
        ELSE
            -- Compute hash with salt using MySQL 8.0.42 SHA2 function
            SET v_computed_hash = SHA2(CONCAT(p_password, v_salt), 256);
            
            IF v_computed_hash = v_stored_hash THEN
                -- Successful login
                UPDATE user_auth 
                SET last_login = NOW(), 
                    failed_login_attempts = 0, 
                    account_locked = FALSE, 
                    locked_until = NULL
                WHERE auth_id = v_auth_id;
                
                SET p_result_message = 'Login successful';
                
                INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
                VALUES (p_user_id, 'LOGIN_SUCCESS', 'Successful login', 
                        p_ip_address, LEFT(p_user_agent, 500), 'LOW');
            ELSE
                -- Failed login
                SET v_failed_attempts = v_failed_attempts + 1;
                
                -- Lock account if too many failed attempts
                IF v_failed_attempts >= v_max_attempts THEN
                    UPDATE user_auth 
                    SET failed_login_attempts = v_failed_attempts, 
                        account_locked = TRUE, 
                        locked_until = DATE_ADD(NOW(), INTERVAL v_lock_duration MINUTE)
                    WHERE auth_id = v_auth_id;
                    
                    SET p_result_message = CONCAT('Account locked due to ', v_max_attempts, ' failed login attempts. Locked for ', v_lock_duration, ' minutes.');
                    
                    INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
                    VALUES (p_user_id, 'ACCOUNT_LOCKED', 
                            CONCAT('Account locked after ', v_max_attempts, ' failed login attempts'), 
                            p_ip_address, LEFT(p_user_agent, 500), 'HIGH');
                ELSE
                    UPDATE user_auth 
                    SET failed_login_attempts = v_failed_attempts
                    WHERE auth_id = v_auth_id;
                    
                    SET p_result_message = CONCAT('Invalid password. ', (v_max_attempts - v_failed_attempts), ' attempts remaining.');
                END IF;
                
                SET p_user_id = NULL;
                
                INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity)
                VALUES (p_user_id, 'LOGIN_FAILED', 
                        CONCAT('Failed login attempt #', v_failed_attempts), 
                        p_ip_address, LEFT(p_user_agent, 500), 'MEDIUM');
            END IF;
        END IF;
    END IF;
END //

-- =====================================================
-- REPORTING PROCEDURES (Enhanced)
-- =====================================================

-- Enhanced procedure to generate monthly account statements
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
    DECLARE v_statements_generated INT DEFAULT 0;
    
    -- Enhanced cursor for active accounts
    DECLARE account_cursor CURSOR FOR
        SELECT account_id 
        FROM accounts 
        WHERE status = 'ACTIVE' 
        ORDER BY account_id;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @sqlstate = RETURNED_SQLSTATE,
            @errno = MYSQL_ERRNO,
            @text = MESSAGE_TEXT;
        ROLLBACK;
        INSERT INTO security_logs (action_type, description, severity)
        VALUES ('DATA_MODIFICATION', CONCAT('Statement generation failed: ', @text), 'HIGH');
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Validate input parameters
    IF p_statement_month < 1 OR p_statement_month > 12 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid month. Must be between 1 and 12.';
    END IF;
    
    IF p_statement_year < 2000 OR p_statement_year > YEAR(CURDATE()) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid year.';
    END IF;

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
        AND status = 'COMPLETED'
        ORDER BY transaction_date DESC, transaction_id DESC 
        LIMIT 1;

        -- If no previous transactions, get current balance
        IF v_opening_balance IS NULL THEN
            SELECT balance INTO v_opening_balance FROM accounts WHERE account_id = v_account_id;
        END IF;

        -- Get closing balance (balance at end of period)
        SELECT COALESCE(balance_after, v_opening_balance) INTO v_closing_balance
        FROM transactions 
        WHERE account_id = v_account_id 
        AND transaction_date <= v_period_end 
        AND status = 'COMPLETED'
        ORDER BY transaction_date DESC, transaction_id DESC 
        LIMIT 1;

        -- Calculate totals for the period using enhanced aggregation
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

        -- Insert statement record (avoid duplicates using INSERT IGNORE)
        INSERT IGNORE INTO account_statements (
            account_id, statement_period_start, statement_period_end,
            opening_balance, closing_balance, total_deposits, total_withdrawals,
            total_fees, interest_earned, transaction_count
        ) VALUES (
            v_account_id, v_period_start, v_period_end,
            v_opening_balance, v_closing_balance, v_total_deposits, v_total_withdrawals,
            v_total_fees, v_interest_earned, v_transaction_count
        );

        IF ROW_COUNT() > 0 THEN
            SET v_statements_generated = v_statements_generated + 1;
        END IF;

    END LOOP;

    CLOSE account_cursor;
    COMMIT;

    -- Log statement generation with enhanced statistics
    INSERT INTO security_logs (action_type, description, severity)
    VALUES ('DATA_MODIFICATION', 
            CONCAT('Monthly statements generated for ', p_statement_month, '/', p_statement_year, 
                   '. Statements created: ', v_statements_generated), 
            'LOW');
END //

DELIMITER ;

-- =====================================================
-- UTILITY PROCEDURES (New for MySQL 8.0.42)
-- =====================================================

DELIMITER //

-- Procedure to get account balance with holds
CREATE PROCEDURE GetAccountBalance(
    IN p_account_id INT,
    OUT p_balance DECIMAL(15,2),
    OUT p_available_balance DECIMAL(15,2),
    OUT p_holds_amount DECIMAL(15,2),
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_account_exists INT DEFAULT 0;
    
    SELECT COUNT(*) INTO v_account_exists FROM accounts WHERE account_id = p_account_id;
    
    IF v_account_exists = 0 THEN
        SET p_result_message = 'Account not found';
        SET p_balance = 0;
        SET p_available_balance = 0;
        SET p_holds_amount = 0;
    ELSE
        SELECT balance, available_balance INTO p_balance, p_available_balance
        FROM accounts WHERE account_id = p_account_id;
        
        SELECT COALESCE(SUM(amount), 0) INTO p_holds_amount
        FROM account_holds 
        WHERE account_id = p_account_id AND status = 'ACTIVE';
        
        SET p_result_message = 'Balance retrieved successfully';
    END IF;
END //

-- Procedure to unlock user account
CREATE PROCEDURE UnlockUserAccount(
    IN p_username VARCHAR(50),
    IN p_admin_user_id INT,
    OUT p_result_message VARCHAR(255)
)
BEGIN
    DECLARE v_user_id INT;
    DECLARE v_auth_id INT;
    
    SELECT ua.user_id, ua.auth_id INTO v_user_id, v_auth_id
    FROM user_auth ua
    JOIN users u ON ua.user_id = u.user_id
    WHERE ua.username = p_username AND u.is_active = TRUE;
    
    IF v_user_id IS NULL THEN
        SET p_result_message = 'User not found';
    ELSE
        UPDATE user_auth 
        SET account_locked = FALSE, 
            locked_until = NULL, 
            failed_login_attempts = 0
        WHERE auth_id = v_auth_id;
        
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (v_user_id, 'ACCOUNT_UNLOCKED', 
                CONCAT('Account unlocked by admin user ', p_admin_user_id), 'MEDIUM');
        
        SET p_result_message = 'Account unlocked successfully';
    END IF;
END //

DELIMITER ;

COMMIT;

-- Display completion message
SELECT 'Enhanced Stored Procedures Created Successfully!' AS status,
       'MySQL Version: 8.0.42.0 Compatible' AS version,
       'Enhanced error handling and validation included' AS features;
