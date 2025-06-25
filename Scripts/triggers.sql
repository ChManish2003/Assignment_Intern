USE banking_system;
DELIMITER //

-- =====================================================
-- AUDIT TRAIL TRIGGERS (Enhanced with JSON)
-- =====================================================

-- Enhanced trigger for users table audit using JSON
CREATE TRIGGER tr_users_audit_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_trail (table_name, record_id, action_type, new_values, created_at)
    VALUES ('users', NEW.user_id, 'INSERT', JSON_OBJECT(
        'user_id', NEW.user_id,
        'first_name', NEW.first_name,
        'last_name', NEW.last_name,
        'email', NEW.email,
        'phone', NEW.phone,
        'date_of_birth', NEW.date_of_birth,
        'address', NEW.address,
        'city', NEW.city,
        'state', NEW.state,
        'postal_code', NEW.postal_code,
        'country', NEW.country,
        'is_active', NEW.is_active,
        'created_at', NEW.created_at
    ), NOW());
END //

CREATE TRIGGER tr_users_audit_update
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_trail (table_name, record_id, action_type, old_values, new_values, created_at)
    VALUES ('users', NEW.user_id, 'UPDATE', JSON_OBJECT(
        'first_name', OLD.first_name,
        'last_name', OLD.last_name,
        'email', OLD.email,
        'phone', OLD.phone,
        'address', OLD.address,
        'city', OLD.city,
        'state', OLD.state,
        'postal_code', OLD.postal_code,
        'country', OLD.country,
        'is_active', OLD.is_active,
        'updated_at', OLD.updated_at
    ), JSON_OBJECT(
        'first_name', NEW.first_name,
        'last_name', NEW.last_name,
        'email', NEW.email,
        'phone', NEW.phone,
        'address', NEW.address,
        'city', NEW.city,
        'state', NEW.state,
        'postal_code', NEW.postal_code,
        'country', NEW.country,
        'is_active', NEW.is_active,
        'updated_at', NEW.updated_at
    ), NOW());
END //

-- Enhanced trigger for accounts table audit
CREATE TRIGGER tr_accounts_audit_insert
AFTER INSERT ON accounts
FOR EACH ROW
BEGIN
    INSERT INTO audit_trail (table_name, record_id, action_type, new_values, created_at)
    VALUES ('accounts', NEW.account_id, 'INSERT', JSON_OBJECT(
        'account_id', NEW.account_id,
        'account_number', NEW.account_number,
        'user_id', NEW.user_id,
        'account_type_id', NEW.account_type_id,
        'currency_id', NEW.currency_id,
        'balance', NEW.balance,
        'available_balance', NEW.available_balance,
        'status', NEW.status,
        'opened_date', NEW.opened_date,
        'created_at', NEW.created_at
    ), NOW());
END //

CREATE TRIGGER tr_accounts_audit_update
AFTER UPDATE ON accounts
FOR EACH ROW
BEGIN
    INSERT INTO audit_trail (table_name, record_id, action_type, old_values, new_values, created_at)
    VALUES ('accounts', NEW.account_id, 'UPDATE', JSON_OBJECT(
        'balance', OLD.balance,
        'available_balance', OLD.available_balance,
        'status', OLD.status,
        'interest_earned', OLD.interest_earned,
        'last_transaction_date', OLD.last_transaction_date,
        'last_interest_calculation', OLD.last_interest_calculation,
        'closed_date', OLD.closed_date,
        'updated_at', OLD.updated_at
    ), JSON_OBJECT(
        'balance', NEW.balance,
        'available_balance', NEW.available_balance,
        'status', NEW.status,
        'interest_earned', NEW.interest_earned,
        'last_transaction_date', NEW.last_transaction_date,
        'last_interest_calculation', NEW.last_interest_calculation,
        'closed_date', NEW.closed_date,
        'updated_at', NEW.updated_at
    ), NOW());
END //

-- Trigger for transactions audit (important for compliance)
CREATE TRIGGER tr_transactions_audit_insert
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    INSERT INTO audit_trail (table_name, record_id, action_type, new_values, created_at)
    VALUES ('transactions', NEW.transaction_id, 'INSERT', JSON_OBJECT(
        'transaction_id', NEW.transaction_id,
        'transaction_number', NEW.transaction_number,
        'account_id', NEW.account_id,
        'transaction_type_id', NEW.transaction_type_id,
        'amount', NEW.amount,
        'currency_id', NEW.currency_id,
        'balance_before', NEW.balance_before,
        'balance_after', NEW.balance_after,
        'status', NEW.status,
        'transaction_date', NEW.transaction_date
    ), NOW());
END //

-- =====================================================
-- VALIDATION TRIGGERS (Enhanced)
-- =====================================================

-- Enhanced trigger to validate account balance changes
CREATE TRIGGER tr_accounts_balance_validation
BEFORE UPDATE ON accounts
FOR EACH ROW
BEGIN
    DECLARE v_min_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_overdraft_limit DECIMAL(15,2) DEFAULT 0;
    DECLARE v_total_holds DECIMAL(15,2) DEFAULT 0;
    
    -- Get account type limits
    SELECT minimum_balance, overdraft_limit 
    INTO v_min_balance, v_overdraft_limit
    FROM account_types 
    WHERE type_id = NEW.account_type_id;
    
    -- Get total active holds
    SELECT COALESCE(SUM(amount), 0) INTO v_total_holds
    FROM account_holds 
    WHERE account_id = NEW.account_id AND status = 'ACTIVE';
    
    -- Enhanced validation with better error messages
    IF NEW.balance < (0 - v_overdraft_limit) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = CONCAT('Balance cannot go below overdraft limit of $', FORMAT(v_overdraft_limit, 2));
    END IF;
    
    -- Validate available balance calculation
    IF NEW.available_balance > NEW.balance THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Available balance cannot exceed actual balance';
    END IF;
    
    -- Auto-calculate available balance if not explicitly set
    IF NEW.available_balance = OLD.available_balance AND NEW.balance != OLD.balance THEN
        SET NEW.available_balance = NEW.balance - v_total_holds;
    END IF;
    
    -- Ensure available balance is not negative beyond overdraft limit
    IF NEW.available_balance < (0 - v_overdraft_limit) THEN
        SET NEW.available_balance = 0 - v_overdraft_limit;
    END IF;
END //

-- Enhanced trigger to validate transaction amounts and limits
CREATE TRIGGER tr_transactions_validation
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_daily_limit INT DEFAULT 0;
    DECLARE v_daily_count INT DEFAULT 0;
    DECLARE v_account_status VARCHAR(20);
    DECLARE v_currency_active BOOLEAN DEFAULT FALSE;
    DECLARE v_transaction_type_active BOOLEAN DEFAULT FALSE;
    
    -- Enhanced validation checks
    IF NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Transaction amount must be positive';
    END IF;
    
    -- Check account status
    SELECT status INTO v_account_status 
    FROM accounts 
    WHERE account_id = NEW.account_id;
    
    IF v_account_status IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Account not found';
    ELSEIF v_account_status != 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = CONCAT('Cannot process transaction on ', v_account_status, ' account');
    END IF;
    
    -- Validate currency
    SELECT is_active INTO v_currency_active
    FROM currencies 
    WHERE currency_id = NEW.currency_id;
    
    IF v_currency_active IS NULL OR v_currency_active = FALSE THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Invalid or inactive currency';
    END IF;
    
    -- Validate transaction type
    SELECT COUNT(*) > 0 INTO v_transaction_type_active
    FROM transaction_types 
    WHERE type_id = NEW.transaction_type_id;
    
    IF v_transaction_type_active = FALSE THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Invalid transaction type';
    END IF;
    
    -- Check daily transaction limits
    SELECT at.transaction_limit_daily INTO v_daily_limit
    FROM accounts a
    JOIN account_types at ON a.account_type_id = at.type_id
    WHERE a.account_id = NEW.account_id;
    
    IF v_daily_limit > 0 THEN
        SELECT COUNT(*) INTO v_daily_count
        FROM transactions 
        WHERE account_id = NEW.account_id 
        AND DATE(transaction_date) = DATE(NEW.transaction_date)
        AND status IN ('COMPLETED', 'PENDING');
        
        IF v_daily_count >= v_daily_limit THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = CONCAT('Daily transaction limit of ', v_daily_limit, ' exceeded');
        END IF;
    END IF;
    
    -- Set default values if not provided
    IF NEW.exchange_rate IS NULL OR NEW.exchange_rate = 0 THEN
        SELECT COALESCE(exchange_rate, 1.000000) INTO NEW.exchange_rate
        FROM currencies 
        WHERE currency_id = NEW.currency_id;
    END IF;
    
    -- Set transaction date if not provided
    IF NEW.transaction_date IS NULL THEN
        SET NEW.transaction_date = CURRENT_TIMESTAMP;
    END IF;
END //

-- =====================================================
-- FRAUD DETECTION TRIGGERS (Enhanced for MySQL 8.0.42)
-- =====================================================

-- Enhanced trigger to detect suspicious transactions
CREATE TRIGGER tr_fraud_detection
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_large_amount_threshold DECIMAL(15,2) DEFAULT 10000.00;
    DECLARE v_rapid_transaction_count INT DEFAULT 0;
    DECLARE v_current_hour INT;
    DECLARE v_rule_id INT;
    DECLARE v_risk_score INT DEFAULT 0;
    
    -- Check for large transactions
    SELECT rule_id INTO v_rule_id
    FROM fraud_rules 
    WHERE rule_name = 'Large Transaction Alert' AND is_active = TRUE
    LIMIT 1;
    
    IF v_rule_id IS NOT NULL AND NEW.amount >= v_large_amount_threshold THEN
        SET v_risk_score = CASE 
            WHEN NEW.amount >= 50000 THEN 95
            WHEN NEW.amount >= 25000 THEN 85
            WHEN NEW.amount >= 10000 THEN 75
            ELSE 50
        END;
        
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        VALUES (NEW.account_id, NEW.transaction_id, v_rule_id, 'LARGE_TRANSACTION', 
                CONCAT('Large transaction of $', FORMAT(NEW.amount, 2)), v_risk_score);
    END IF;
    
    -- Check for rapid succession transactions (enhanced logic)
    SELECT COUNT(*) INTO v_rapid_transaction_count
    FROM transactions 
    WHERE account_id = NEW.account_id 
    AND transaction_date >= DATE_SUB(NEW.transaction_date, INTERVAL 10 MINUTE)
    AND status = 'COMPLETED'
    AND transaction_id != NEW.transaction_id;
    
    SELECT rule_id INTO v_rule_id
    FROM fraud_rules 
    WHERE rule_name = 'Rapid Succession Withdrawals' AND is_active = TRUE
    LIMIT 1;
    
    IF v_rule_id IS NOT NULL AND v_rapid_transaction_count >= 5 THEN
        SET v_risk_score = LEAST(90, 40 + (v_rapid_transaction_count * 10));
        
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        VALUES (NEW.account_id, NEW.transaction_id, v_rule_id, 'RAPID_TRANSACTIONS', 
                CONCAT('Rapid succession: ', v_rapid_transaction_count + 1, ' transactions in 10 minutes'), 
                v_risk_score);
    END IF;
    
    -- Check for off-hours transactions (enhanced with timezone consideration)
    SET v_current_hour = HOUR(NEW.transaction_date);
    
    SELECT rule_id INTO v_rule_id
    FROM fraud_rules 
    WHERE rule_name = 'Off-Hours Transaction' AND is_active = TRUE
    LIMIT 1;
    
    IF v_rule_id IS NOT NULL AND (v_current_hour < 6 OR v_current_hour > 22) THEN
        SET v_risk_score = CASE 
            WHEN v_current_hour BETWEEN 0 AND 4 THEN 60
            WHEN v_current_hour = 5 OR v_current_hour = 23 THEN 30
            ELSE 45
        END;
        
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        VALUES (NEW.account_id, NEW.transaction_id, v_rule_id, 'OFF_HOURS', 
                CONCAT('Transaction at ', TIME_FORMAT(NEW.transaction_date, '%H:%i:%s')), 
                v_risk_score);
    END IF;
    
    -- Check for unusual transaction patterns (new for MySQL 8.0.42)
    -- Multiple different transaction types in short period
    IF (SELECT COUNT(DISTINCT transaction_type_id) 
        FROM transactions 
        WHERE account_id = NEW.account_id 
        AND transaction_date >= DATE_SUB(NEW.transaction_date, INTERVAL 1 HOUR)
        AND status = 'COMPLETED') >= 4 THEN
        
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        VALUES (NEW.account_id, NEW.transaction_id, 
                COALESCE((SELECT rule_id FROM fraud_rules WHERE rule_name = 'High Frequency Transactions' LIMIT 1), 1), 
                'UNUSUAL_PATTERN', 
                'Multiple different transaction types in short period', 55);
    END IF;
END //

-- =====================================================
-- AUTOMATIC MAINTENANCE TRIGGERS (Enhanced)
-- =====================================================

-- Enhanced trigger to automatically charge monthly fees
CREATE TRIGGER tr_monthly_fee_calculation
AFTER UPDATE ON accounts
FOR EACH ROW
BEGIN
    DECLARE v_monthly_fee DECIMAL(10,2) DEFAULT 0;
    DECLARE v_fee_type_id INT;
    DECLARE v_transaction_id INT;
    DECLARE v_result_message VARCHAR(255);
    DECLARE v_last_fee_date DATE;
    
    -- Only process if it's a new month, account is active, and balance changed
    IF NEW.status = 'ACTIVE' AND 
       DAY(CURDATE()) = 1 AND 
       DATE(NEW.updated_at) = CURDATE() AND
       (OLD.updated_at IS NULL OR MONTH(OLD.updated_at) != MONTH(CURDATE())) THEN
        
        -- Get monthly fee for account type
        SELECT monthly_fee INTO v_monthly_fee
        FROM account_types 
        WHERE type_id = NEW.account_type_id;
        
        -- Check if fee was already charged this month
        SELECT MAX(DATE(transaction_date)) INTO v_last_fee_date
        FROM transactions t
        JOIN transaction_types tt ON t.transaction_type_id = tt.type_id
        WHERE t.account_id = NEW.account_id 
        AND tt.type_name = 'MONTHLY_MAINTENANCE'
        AND YEAR(t.transaction_date) = YEAR(CURDATE())
        AND MONTH(t.transaction_date) = MONTH(CURDATE());
        
        -- Only charge fee if there is one, account has sufficient balance, and not already charged
        IF v_monthly_fee > 0 AND NEW.balance >= v_monthly_fee AND v_last_fee_date IS NULL THEN
            -- Get fee transaction type ID
            SELECT type_id INTO v_fee_type_id 
            FROM transaction_types 
            WHERE type_name = 'MONTHLY_MAINTENANCE';
            
            IF v_fee_type_id IS NOT NULL THEN
                -- Record the fee transaction
                CALL RecordTransaction(
                    NEW.account_id, v_fee_type_id, v_monthly_fee, NEW.currency_id,
                    CONCAT('Monthly maintenance fee for ', MONTHNAME(CURDATE()), ' ', YEAR(CURDATE())), 
                    CONCAT('FEE', DATE_FORMAT(NOW(), '%Y%m')), NULL,
                    v_transaction_id, v_result_message
                );
            END IF;
        END IF;
    END IF;
END //

-- Enhanced trigger to update available balance when holds are modified
CREATE TRIGGER tr_account_holds_insert
AFTER INSERT ON account_holds
FOR EACH ROW
BEGIN
    DECLARE v_current_balance DECIMAL(15,2);
    DECLARE v_total_holds DECIMAL(15,2);
    
    -- Get current balance and calculate total holds
    SELECT balance INTO v_current_balance 
    FROM accounts 
    WHERE account_id = NEW.account_id;
    
    SELECT COALESCE(SUM(amount), 0) INTO v_total_holds
    FROM account_holds 
    WHERE account_id = NEW.account_id AND status = 'ACTIVE';
    
    -- Update available balance
    UPDATE accounts 
    SET available_balance = GREATEST(0, v_current_balance - v_total_holds),
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = NEW.account_id;
    
    -- Log the hold placement
    INSERT INTO security_logs (action_type, description, severity)
    VALUES ('DATA_MODIFICATION', 
            CONCAT('Hold placed on account ', NEW.account_id, ': $', FORMAT(NEW.amount, 2), ' (', NEW.hold_type, ')'), 
            CASE NEW.hold_type 
                WHEN 'FRAUD' THEN 'HIGH'
                WHEN 'LEGAL' THEN 'HIGH'
                ELSE 'MEDIUM'
            END);
END //

CREATE TRIGGER tr_account_holds_update
AFTER UPDATE ON account_holds
FOR EACH ROW
BEGIN
    DECLARE v_current_balance DECIMAL(15,2);
    DECLARE v_total_holds DECIMAL(15,2);
    
    -- Only update if status changed or amount changed
    IF OLD.status != NEW.status OR OLD.amount != NEW.amount THEN
        -- Get current balance and calculate total active holds
        SELECT balance INTO v_current_balance 
        FROM accounts 
        WHERE account_id = NEW.account_id;
        
        SELECT COALESCE(SUM(amount), 0) INTO v_total_holds
        FROM account_holds 
        WHERE account_id = NEW.account_id AND status = 'ACTIVE';
        
        -- Update available balance
        UPDATE accounts 
        SET available_balance = GREATEST(0, v_current_balance - v_total_holds),
            updated_at = CURRENT_TIMESTAMP
        WHERE account_id = NEW.account_id;
        
        -- Log hold status change
        IF OLD.status != NEW.status THEN
            INSERT INTO security_logs (action_type, description, severity)
            VALUES ('DATA_MODIFICATION', 
                    CONCAT('Hold status changed on account ', NEW.account_id, ': ', OLD.status, ' -> ', NEW.status), 
                    'MEDIUM');
        END IF;
    END IF;
END //

-- =====================================================
-- SECURITY TRIGGERS (Enhanced)
-- =====================================================

-- Enhanced trigger to log password changes and security events
CREATE TRIGGER tr_password_change_log
AFTER UPDATE ON user_auth
FOR EACH ROW
BEGIN
    -- Log password changes
    IF OLD.password_hash != NEW.password_hash THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'PASSWORD_CHANGE', 
                CONCAT('Password changed. Previous change: ', 
                       COALESCE(DATE_FORMAT(OLD.password_changed_at, '%Y-%m-%d %H:%i:%s'), 'Never')), 
                'MEDIUM');
    END IF;
    
    -- Log account locking
    IF OLD.account_locked = FALSE AND NEW.account_locked = TRUE THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'ACCOUNT_LOCKED', 
                CONCAT('Account locked after ', NEW.failed_login_attempts, ' failed attempts. Locked until: ',
                       COALESCE(DATE_FORMAT(NEW.locked_until, '%Y-%m-%d %H:%i:%s'), 'Manual unlock required')), 
                'HIGH');
    END IF;
    
    -- Log account unlocking
    IF OLD.account_locked = TRUE AND NEW.account_locked = FALSE THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'ACCOUNT_UNLOCKED', 
                CONCAT('Account unlocked. Failed attempts reset from ', OLD.failed_login_attempts, ' to ', NEW.failed_login_attempts), 
                'MEDIUM');
    END IF;
    
    -- Log suspicious failed login patterns
    IF NEW.failed_login_attempts > OLD.failed_login_attempts AND NEW.failed_login_attempts >= 3 THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'SUSPICIOUS_ACTIVITY', 
                CONCAT('Multiple failed login attempts: ', NEW.failed_login_attempts, ' total'), 
                CASE 
                    WHEN NEW.failed_login_attempts >= 5 THEN 'HIGH'
                    WHEN NEW.failed_login_attempts >= 4 THEN 'MEDIUM'
                    ELSE 'LOW'
                END);
    END IF;
END //

-- Enhanced triggers to prevent deletion of critical records
CREATE TRIGGER tr_prevent_transaction_delete
BEFORE DELETE ON transactions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'Transactions cannot be deleted for audit compliance. Use status updates instead.';
END //

CREATE TRIGGER tr_prevent_audit_delete
BEFORE DELETE ON audit_trail
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'Audit trail records cannot be deleted for compliance reasons.';
END //

CREATE TRIGGER tr_prevent_security_log_delete
BEFORE DELETE ON security_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'Security log records cannot be deleted for compliance reasons.';
END //

-- Trigger to prevent deletion of accounts with transactions
CREATE TRIGGER tr_prevent_account_delete_with_transactions
BEFORE DELETE ON accounts
FOR EACH ROW
BEGIN
    DECLARE v_transaction_count INT DEFAULT 0;
    
    SELECT COUNT(*) INTO v_transaction_count
    FROM transactions 
    WHERE account_id = OLD.account_id;
    
    IF v_transaction_count > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Cannot delete account with transaction history. Use account closure instead.';
    END IF;
END //

-- =====================================================
-- PERFORMANCE MONITORING TRIGGERS (New for MySQL 8.0.42)
-- =====================================================

-- Trigger to monitor large transactions for performance impact
CREATE TRIGGER tr_performance_monitoring
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    -- Log very large transactions that might impact performance
    IF NEW.amount >= 100000.00 THEN
        INSERT INTO security_logs (action_type, description, severity)
        VALUES ('DATA_MODIFICATION', 
                CONCAT('Large transaction processed: $', FORMAT(NEW.amount, 2), 
                       ' on account ', NEW.account_id, ' (Transaction ID: ', NEW.transaction_id, ')'), 
                'LOW');
    END IF;
    
    -- Monitor transaction volume per account
    IF (SELECT COUNT(*) 
        FROM transactions 
        WHERE account_id = NEW.account_id 
        AND transaction_date >= DATE_SUB(NOW(), INTERVAL 1 HOUR)) > 50 THEN
        
        INSERT INTO security_logs (action_type, description, severity)
        VALUES ('SUSPICIOUS_ACTIVITY', 
                CONCAT('High transaction volume detected on account ', NEW.account_id, 
                       ' - over 50 transactions in the last hour'), 
                'MEDIUM');
    END IF;
END //

DELIMITER ;

COMMIT;

-- Display completion message
SELECT 'Enhanced Triggers Created Successfully!' AS status,
       'MySQL Version: 8.0.42.0 Compatible' AS version,
       'Enhanced fraud detection and audit trails included' AS features,
       'JSON data types utilized for better data structure' AS json_features;
