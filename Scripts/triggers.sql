-- =====================================================
-- DevifyX Banking System - Triggers
-- =====================================================
-- This script contains all triggers for audit trails, validation, and automation
-- =====================================================

USE banking_system;

DELIMITER //

-- =====================================================
-- AUDIT TRAIL TRIGGERS
-- =====================================================

-- Trigger for users table audit
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
        'is_active', NEW.is_active
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
        'is_active', OLD.is_active
    ), JSON_OBJECT(
        'first_name', NEW.first_name,
        'last_name', NEW.last_name,
        'email', NEW.email,
        'phone', NEW.phone,
        'address', NEW.address,
        'is_active', NEW.is_active
    ), NOW());
END //

-- Trigger for accounts table audit
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
        'balance', NEW.balance,
        'status', NEW.status
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
        'interest_earned', OLD.interest_earned
    ), JSON_OBJECT(
        'balance', NEW.balance,
        'available_balance', NEW.available_balance,
        'status', NEW.status,
        'interest_earned', NEW.interest_earned
    ), NOW());
END //

-- =====================================================
-- VALIDATION TRIGGERS
-- =====================================================

-- Trigger to validate account balance changes
CREATE TRIGGER tr_accounts_balance_validation
BEFORE UPDATE ON accounts
FOR EACH ROW
BEGIN
    DECLARE v_min_balance DECIMAL(15,2) DEFAULT 0;
    DECLARE v_overdraft_limit DECIMAL(15,2) DEFAULT 0;
    
    -- Get account type limits
    SELECT minimum_balance, overdraft_limit 
    INTO v_min_balance, v_overdraft_limit
    FROM account_types 
    WHERE type_id = NEW.account_type_id;
    
    -- Validate minimum balance (considering overdraft)
    IF NEW.balance < (0 - v_overdraft_limit) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Balance cannot go below overdraft limit';
    END IF;
    
    -- Validate available balance
    IF NEW.available_balance > NEW.balance THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Available balance cannot exceed actual balance';
    END IF;
    
    -- Update available balance calculation (subtract any active holds)
    SELECT NEW.balance - COALESCE(SUM(amount), 0) INTO NEW.available_balance
    FROM account_holds 
    WHERE account_id = NEW.account_id AND status = 'ACTIVE';
END //

-- Trigger to validate transaction amounts
CREATE TRIGGER tr_transactions_validation
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_daily_limit INT DEFAULT 0;
    DECLARE v_daily_count INT DEFAULT 0;
    DECLARE v_account_status VARCHAR(20);
    
    -- Check if amount is positive
    IF NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Transaction amount must be positive';
    END IF;
    
    -- Check account status
    SELECT status INTO v_account_status FROM accounts WHERE account_id = NEW.account_id;
    IF v_account_status != 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Cannot process transaction on inactive account';
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
        AND DATE(transaction_date) = CURDATE()
        AND status = 'COMPLETED';
        
        IF v_daily_count >= v_daily_limit THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Daily transaction limit exceeded';
        END IF;
    END IF;
END //

-- =====================================================
-- FRAUD DETECTION TRIGGERS
-- =====================================================

-- Trigger to detect suspicious transactions
CREATE TRIGGER tr_fraud_detection
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_large_amount_threshold DECIMAL(15,2) DEFAULT 10000.00;
    DECLARE v_rapid_transaction_count INT DEFAULT 0;
    DECLARE v_off_hours BOOLEAN DEFAULT FALSE;
    DECLARE v_current_hour INT;
    
    -- Check for large transactions
    IF NEW.amount >= v_large_amount_threshold THEN
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        SELECT NEW.account_id, NEW.transaction_id, rule_id, 'LARGE_TRANSACTION', 
               CONCAT('Large transaction of $', NEW.amount), 80
        FROM fraud_rules 
        WHERE rule_name = 'Large Transaction Alert' AND is_active = TRUE;
    END IF;
    
    -- Check for rapid succession transactions (more than 5 in 10 minutes)
    SELECT COUNT(*) INTO v_rapid_transaction_count
    FROM transactions 
    WHERE account_id = NEW.account_id 
    AND transaction_date >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
    AND status = 'COMPLETED';
    
    IF v_rapid_transaction_count > 5 THEN
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        SELECT NEW.account_id, NEW.transaction_id, rule_id, 'RAPID_TRANSACTIONS', 
               CONCAT('Rapid succession transactions: ', v_rapid_transaction_count, ' in 10 minutes'), 70
        FROM fraud_rules 
        WHERE rule_name = 'Rapid Succession Withdrawals' AND is_active = TRUE;
    END IF;
    
    -- Check for off-hours transactions (before 6 AM or after 10 PM)
    SET v_current_hour = HOUR(NOW());
    IF v_current_hour < 6 OR v_current_hour > 22 THEN
        INSERT INTO fraud_alerts (account_id, transaction_id, rule_id, alert_type, description, risk_score)
        SELECT NEW.account_id, NEW.transaction_id, rule_id, 'OFF_HOURS', 
               CONCAT('Transaction at ', TIME(NOW())), 30
        FROM fraud_rules 
        WHERE rule_name = 'Off-Hours Transaction' AND is_active = TRUE;
    END IF;
END //

-- =====================================================
-- AUTOMATIC MAINTENANCE TRIGGERS
-- =====================================================

-- Trigger to automatically charge monthly fees
CREATE TRIGGER tr_monthly_fee_calculation
AFTER UPDATE ON accounts
FOR EACH ROW
BEGIN
    DECLARE v_monthly_fee DECIMAL(10,2) DEFAULT 0;
    DECLARE v_last_fee_date DATE;
    DECLARE v_fee_type_id INT;
    DECLARE v_transaction_id INT;
    DECLARE v_result_message VARCHAR(255);
    
    -- Only process if it's a new month and account is active
    IF NEW.status = 'ACTIVE' AND DAY(CURDATE()) = 1 AND 
       (OLD.updated_at IS NULL OR MONTH(OLD.updated_at) != MONTH(CURDATE())) THEN
        
        -- Get monthly fee for account type
        SELECT monthly_fee INTO v_monthly_fee
        FROM account_types 
        WHERE type_id = NEW.account_type_id;
        
        -- Only charge fee if there is one and account has sufficient balance
        IF v_monthly_fee > 0 AND NEW.balance >= v_monthly_fee THEN
            -- Get fee transaction type ID
            SELECT type_id INTO v_fee_type_id FROM transaction_types WHERE type_name = 'MONTHLY_MAINTENANCE';
            
            -- Record the fee transaction
            CALL RecordTransaction(
                NEW.account_id, v_fee_type_id, v_monthly_fee, NEW.currency_id,
                'Monthly maintenance fee', CONCAT('FEE', DATE_FORMAT(NOW(), '%Y%m')), NULL,
                v_transaction_id, v_result_message
            );
        END IF;
    END IF;
END //

-- Trigger to update available balance when holds are added/removed
CREATE TRIGGER tr_account_holds_insert
AFTER INSERT ON account_holds
FOR EACH ROW
BEGIN
    UPDATE accounts 
    SET available_balance = balance - (
        SELECT COALESCE(SUM(amount), 0) 
        FROM account_holds 
        WHERE account_id = NEW.account_id AND status = 'ACTIVE'
    )
    WHERE account_id = NEW.account_id;
END //

CREATE TRIGGER tr_account_holds_update
AFTER UPDATE ON account_holds
FOR EACH ROW
BEGIN
    UPDATE accounts 
    SET available_balance = balance - (
        SELECT COALESCE(SUM(amount), 0) 
        FROM account_holds 
        WHERE account_id = NEW.account_id AND status = 'ACTIVE'
    )
    WHERE account_id = NEW.account_id;
END //

-- =====================================================
-- SECURITY TRIGGERS
-- =====================================================

-- Trigger to log password changes
CREATE TRIGGER tr_password_change_log
AFTER UPDATE ON user_auth
FOR EACH ROW
BEGIN
    IF OLD.password_hash != NEW.password_hash THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'PASSWORD_CHANGE', 'User password changed', 'MEDIUM');
    END IF;
    
    IF OLD.account_locked = FALSE AND NEW.account_locked = TRUE THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'ACCOUNT_LOCKED', 'User account locked due to failed login attempts', 'HIGH');
    END IF;
    
    IF OLD.account_locked = TRUE AND NEW.account_locked = FALSE THEN
        INSERT INTO security_logs (user_id, action_type, description, severity)
        VALUES (NEW.user_id, 'ACCOUNT_UNLOCKED', 'User account unlocked', 'MEDIUM');
    END IF;
END //

-- Trigger to prevent deletion of critical records
CREATE TRIGGER tr_prevent_transaction_delete
BEFORE DELETE ON transactions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'Transactions cannot be deleted for audit compliance';
END //

CREATE TRIGGER tr_prevent_audit_delete
BEFORE DELETE ON audit_trail
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'Audit trail records cannot be deleted';
END //

CREATE TRIGGER tr_prevent_security_log_delete
BEFORE DELETE ON security_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = 'Security log records cannot be deleted';
END //

DELIMITER ;

COMMIT;
