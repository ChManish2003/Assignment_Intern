-- =====================================================
-- DevifyX Banking System - Views
-- =====================================================
-- This script creates views for reporting and data access
-- =====================================================

USE banking_system;

-- =====================================================
-- ACCOUNT OVERVIEW VIEWS
-- =====================================================

-- View for account summary with user details
CREATE VIEW vw_account_summary AS
SELECT 
    a.account_id,
    a.account_number,
    CONCAT(u.first_name, ' ', u.last_name) AS account_holder,
    u.email,
    u.phone,
    at.type_name AS account_type,
    c.currency_code,
    c.symbol AS currency_symbol,
    a.balance,
    a.available_balance,
    a.status,
    a.opened_date,
    a.last_transaction_date,
    a.interest_earned,
    at.interest_rate,
    at.minimum_balance,
    at.overdraft_limit
FROM accounts a
JOIN users u ON a.user_id = u.user_id
JOIN account_types at ON a.account_type_id = at.type_id
JOIN currencies c ON a.currency_id = c.currency_id;

-- View for joint account relationships
CREATE VIEW vw_joint_accounts AS
SELECT 
    a.account_id,
    a.account_number,
    CONCAT(primary_user.first_name, ' ', primary_user.last_name) AS primary_holder,
    CONCAT(joint_user.first_name, ' ', joint_user.last_name) AS joint_holder,
    ao.ownership_type,
    ao.permissions,
    a.balance,
    a.status
FROM accounts a
JOIN account_owners ao_primary ON a.account_id = ao_primary.account_id AND ao_primary.ownership_type = 'PRIMARY'
JOIN users primary_user ON ao_primary.user_id = primary_user.user_id
JOIN account_owners ao ON a.account_id = ao.account_id AND ao.ownership_type != 'PRIMARY'
JOIN users joint_user ON ao.user_id = joint_user.user_id;

-- =====================================================
-- TRANSACTION VIEWS
-- =====================================================

-- View for transaction history with details
CREATE VIEW vw_transaction_history AS
SELECT 
    t.transaction_id,
    t.transaction_number,
    a.account_number,
    CONCAT(u.first_name, ' ', u.last_name) AS account_holder,
    tt.type_name AS transaction_type,
    t.amount,
    c.currency_code,
    c.symbol AS currency_symbol,
    t.balance_before,
    t.balance_after,
    t.description,
    t.reference_number,
    related_acc.account_number AS related_account,
    t.status,
    t.transaction_date,
    t.processed_date
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN users u ON a.user_id = u.user_id
JOIN transaction_types tt ON t.transaction_type_id = tt.type_id
JOIN currencies c ON t.currency_id = c.currency_id
LEFT JOIN accounts related_acc ON t.related_account_id = related_acc.account_id
ORDER BY t.transaction_date DESC;

-- View for daily transaction summary
CREATE VIEW vw_daily_transaction_summary AS
SELECT 
    DATE(t.transaction_date) AS transaction_date,
    a.account_id,
    a.account_number,
    COUNT(*) AS transaction_count,
    SUM(CASE WHEN tt.type_name IN ('DEPOSIT', 'TRANSFER_IN', 'INTEREST_CREDIT', 'DIRECT_DEPOSIT') THEN t.amount ELSE 0 END) AS total_credits,
    SUM(CASE WHEN tt.type_name IN ('WITHDRAWAL', 'TRANSFER_OUT', 'ATM_WITHDRAWAL', 'BILL_PAYMENT') THEN t.amount ELSE 0 END) AS total_debits,
    SUM(CASE WHEN tt.type_name LIKE '%FEE%' THEN t.amount ELSE 0 END) AS total_fees
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN transaction_types tt ON t.transaction_type_id = tt.type_id
WHERE t.status = 'COMPLETED'
GROUP BY DATE(t.transaction_date), a.account_id, a.account_number;

-- =====================================================
-- SECURITY AND AUDIT VIEWS
-- =====================================================

-- View for security incidents
CREATE VIEW vw_security_incidents AS
SELECT 
    sl.log_id,
    CONCAT(u.first_name, ' ', u.last_name) AS user_name,
    u.email,
    sl.action_type,
    sl.description,
    sl.ip_address,
    sl.severity,
    sl.created_at
FROM security_logs sl
LEFT JOIN users u ON sl.user_id = u.user_id
WHERE sl.severity IN ('HIGH', 'CRITICAL')
ORDER BY sl.created_at DESC;

-- View for failed login attempts
CREATE VIEW vw_failed_logins AS
SELECT 
    sl.log_id,
    CONCAT(u.first_name, ' ', u.last_name) AS user_name,
    u.email,
    ua.username,
    sl.ip_address,
    sl.user_agent,
    sl.created_at,
    ua.failed_login_attempts,
    ua.account_locked
FROM security_logs sl
LEFT JOIN users u ON sl.user_id = u.user_id
LEFT JOIN user_auth ua ON u.user_id = ua.user_id
WHERE sl.action_type = 'LOGIN_FAILED'
ORDER BY sl.created_at DESC;

-- View for audit trail summary
CREATE VIEW vw_audit_summary AS
SELECT 
    at.audit_id,
    at.table_name,
    at.record_id,
    at.action_type,
    CONCAT(u.first_name, ' ', u.last_name) AS changed_by_user,
    at.change_reason,
    at.created_at
FROM audit_trail at
LEFT JOIN users u ON at.changed_by = u.user_id
ORDER BY at.created_at DESC;

-- =====================================================
-- FRAUD DETECTION VIEWS
-- =====================================================

-- View for active fraud alerts
CREATE VIEW vw_active_fraud_alerts AS
SELECT 
    fa.alert_id,
    a.account_number,
    CONCAT(u.first_name, ' ', u.last_name) AS account_holder,
    fa.alert_type,
    fa.description,
    fa.risk_score,
    fa.status,
    fa.created_at,
    t.transaction_number,
    t.amount AS transaction_amount,
    fr.rule_name
FROM fraud_alerts fa
JOIN accounts a ON fa.account_id = a.account_id
JOIN users u ON a.user_id = u.user_id
LEFT JOIN transactions t ON fa.transaction_id = t.transaction_id
JOIN fraud_rules fr ON fa.rule_id = fr.rule_id
WHERE fa.status IN ('OPEN', 'INVESTIGATING')
ORDER BY fa.risk_score DESC, fa.created_at DESC;

-- View for fraud statistics
CREATE VIEW vw_fraud_statistics AS
SELECT 
    DATE(fa.created_at) AS alert_date,
    fa.alert_type,
    COUNT(*) AS alert_count,
    AVG(fa.risk_score) AS avg_risk_score,
    SUM(CASE WHEN fa.status = 'RESOLVED' THEN 1 ELSE 0 END) AS resolved_count,
    SUM(CASE WHEN fa.status = 'FALSE_POSITIVE' THEN 1 ELSE 0 END) AS false_positive_count
FROM fraud_alerts fa
GROUP BY DATE(fa.created_at), fa.alert_type
ORDER BY alert_date DESC;

-- =====================================================
-- FINANCIAL REPORTING VIEWS
-- =====================================================

-- View for account balances by type
CREATE VIEW vw_balance_by_account_type AS
SELECT 
    at.type_name,
    c.currency_code,
    COUNT(a.account_id) AS account_count,
    SUM(a.balance) AS total_balance,
    AVG(a.balance) AS average_balance,
    MIN(a.balance) AS minimum_balance,
    MAX(a.balance) AS maximum_balance,
    SUM(a.interest_earned) AS total_interest_earned
FROM accounts a
JOIN account_types at ON a.account_type_id = at.type_id
JOIN currencies c ON a.currency_id = c.currency_id
WHERE a.status = 'ACTIVE'
GROUP BY at.type_name, c.currency_code;

-- View for monthly transaction volume
CREATE VIEW vw_monthly_transaction_volume AS
SELECT 
    YEAR(t.transaction_date) AS transaction_year,
    MONTH(t.transaction_date) AS transaction_month,
    MONTHNAME(t.transaction_date) AS month_name,
    tt.type_name AS transaction_type,
    COUNT(*) AS transaction_count,
    SUM(t.amount) AS total_amount,
    AVG(t.amount) AS average_amount
FROM transactions t
JOIN transaction_types tt ON t.transaction_type_id = tt.type_id
WHERE t.status = 'COMPLETED'
GROUP BY YEAR(t.transaction_date), MONTH(t.transaction_date), tt.type_name
ORDER BY transaction_year DESC, transaction_month DESC;

-- View for customer account portfolio
CREATE VIEW vw_customer_portfolio AS
SELECT 
    u.user_id,
    CONCAT(u.first_name, ' ', u.last_name) AS customer_name,
    u.email,
    COUNT(a.account_id) AS total_accounts,
    SUM(a.balance) AS total_balance,
    SUM(a.interest_earned) AS total_interest_earned,
    MIN(a.opened_date) AS first_account_date,
    MAX(a.last_transaction_date) AS last_activity_date,
    GROUP_CONCAT(DISTINCT at.type_name ORDER BY at.type_name) AS account_types
FROM users u
JOIN accounts a ON u.user_id = a.user_id
JOIN account_types at ON a.account_type_id = at.type_id
WHERE u.is_active = TRUE AND a.status = 'ACTIVE'
GROUP BY u.user_id, u.first_name, u.last_name, u.email;

-- =====================================================
-- OPERATIONAL VIEWS
-- =====================================================

-- View for accounts requiring attention
CREATE VIEW vw_accounts_requiring_attention AS
SELECT 
    a.account_id,
    a.account_number,
    CONCAT(u.first_name, ' ', u.last_name) AS account_holder,
    u.email,
    a.balance,
    at.minimum_balance,
    a.status,
    CASE 
        WHEN a.balance < at.minimum_balance THEN 'Below Minimum Balance'
        WHEN a.balance < 0 THEN 'Negative Balance'
        WHEN a.last_transaction_date < DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 'Inactive Account'
        WHEN EXISTS (SELECT 1 FROM fraud_alerts fa WHERE fa.account_id = a.account_id AND fa.status = 'OPEN') THEN 'Fraud Alert'
        ELSE 'Other'
    END AS attention_reason,
    a.last_transaction_date
FROM accounts a
JOIN users u ON a.user_id = u.user_id
JOIN account_types at ON a.account_type_id = at.type_id
WHERE a.status = 'ACTIVE' AND (
    a.balance < at.minimum_balance OR
    a.balance < 0 OR
    a.last_transaction_date < DATE_SUB(CURDATE(), INTERVAL 90 DAY) OR
    EXISTS (SELECT 1 FROM fraud_alerts fa WHERE fa.account_id = a.account_id AND fa.status = 'OPEN')
);

-- View for system health metrics
CREATE VIEW vw_system_health_metrics AS
SELECT 
    'Total Active Users' AS metric_name,
    COUNT(*) AS metric_value,
    CURDATE() AS metric_date
FROM users WHERE is_active = TRUE
UNION ALL
SELECT 
    'Total Active Accounts' AS metric_name,
    COUNT(*) AS metric_value,
    CURDATE() AS metric_date
FROM accounts WHERE status = 'ACTIVE'
UNION ALL
SELECT 
    'Total System Balance' AS metric_name,
    ROUND(SUM(balance), 2) AS metric_value,
    CURDATE() AS metric_date
FROM accounts WHERE status = 'ACTIVE'
UNION ALL
SELECT 
    'Transactions Today' AS metric_name,
    COUNT(*) AS metric_value,
    CURDATE() AS metric_date
FROM transactions WHERE DATE(transaction_date) = CURDATE() AND status = 'COMPLETED'
UNION ALL
SELECT 
    'Open Fraud Alerts' AS metric_name,
    COUNT(*) AS metric_value,
    CURDATE() AS metric_date
FROM fraud_alerts WHERE status IN ('OPEN', 'INVESTIGATING')
UNION ALL
SELECT 
    'Failed Logins Today' AS metric_name,
    COUNT(*) AS metric_value,
    CURDATE() AS metric_date
FROM security_logs WHERE action_type = 'LOGIN_FAILED' AND DATE(created_at) = CURDATE();

COMMIT;
