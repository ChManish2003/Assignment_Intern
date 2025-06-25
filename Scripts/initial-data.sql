USE banking_system;

-- =====================================================
-- REFERENCE DATA
-- =====================================================

-- Insert currency data
INSERT INTO currencies (currency_code, currency_name, symbol, exchange_rate, is_active) VALUES
('USD', 'US Dollar', '$', 1.000000, TRUE),
('EUR', 'Euro', '€', 0.850000, TRUE),
('GBP', 'British Pound', '£', 0.750000, TRUE),
('CAD', 'Canadian Dollar', 'C$', 1.250000, TRUE),
('JPY', 'Japanese Yen', '¥', 110.000000, TRUE),
('AUD', 'Australian Dollar', 'A$', 1.350000, TRUE),
('CHF', 'Swiss Franc', 'CHF', 0.920000, TRUE),
('CNY', 'Chinese Yuan', '¥', 6.450000, TRUE);

-- Insert account types
INSERT INTO account_types (type_name, description, interest_rate, minimum_balance, overdraft_limit, monthly_fee, transaction_limit_daily, is_active) VALUES
('SAVINGS', 'Standard savings account with interest', 0.0250, 100.00, 0.00, 0.00, 10, TRUE),
('CHECKING', 'Standard checking account for daily transactions', 0.0050, 25.00, 500.00, 5.00, 50, TRUE),
('PREMIUM_SAVINGS', 'High-yield savings account', 0.0450, 1000.00, 0.00, 0.00, 15, TRUE),
('BUSINESS_CHECKING', 'Business checking account', 0.0100, 500.00, 2000.00, 15.00, 100, TRUE),
('FIXED_DEPOSIT', 'Fixed deposit account with locked funds', 0.0550, 1000.00, 0.00, 0.00, 2, TRUE),
('MONEY_MARKET', 'Money market account with higher interest', 0.0350, 2500.00, 0.00, 10.00, 6, TRUE),
('STUDENT', 'Student account with no fees', 0.0150, 0.00, 100.00, 0.00, 20, TRUE);

-- Insert transaction types
INSERT INTO transaction_types (type_name, description, affects_balance, requires_approval) VALUES
('DEPOSIT', 'Money deposited into account', TRUE, FALSE),
('WITHDRAWAL', 'Money withdrawn from account', TRUE, FALSE),
('TRANSFER_IN', 'Money transferred into account', TRUE, FALSE),
('TRANSFER_OUT', 'Money transferred out of account', TRUE, FALSE),
('INTEREST_CREDIT', 'Interest credited to account', TRUE, FALSE),
('FEE_DEBIT', 'Fee charged to account', TRUE, FALSE),
('OVERDRAFT_FEE', 'Overdraft fee charged', TRUE, FALSE),
('MONTHLY_MAINTENANCE', 'Monthly maintenance fee', TRUE, FALSE),
('ATM_WITHDRAWAL', 'ATM withdrawal', TRUE, FALSE),
('ONLINE_TRANSFER', 'Online transfer', TRUE, FALSE),
('WIRE_TRANSFER', 'Wire transfer', TRUE, TRUE),
('CHECK_DEPOSIT', 'Check deposit', TRUE, FALSE),
('DIRECT_DEPOSIT', 'Direct deposit (payroll, etc.)', TRUE, FALSE),
('BILL_PAYMENT', 'Bill payment', TRUE, FALSE),
('REFUND', 'Transaction refund', TRUE, FALSE);

-- Insert fraud detection rules using JSON (MySQL 8.0 feature)
INSERT INTO fraud_rules (rule_name, rule_type, parameters, severity, is_active) VALUES
('Large Transaction Alert', 'AMOUNT_LIMIT', JSON_OBJECT('max_amount', 10000, 'currency', 'USD'), 'HIGH', TRUE),
('High Frequency Transactions', 'FREQUENCY_LIMIT', JSON_OBJECT('max_transactions', 20, 'time_period', '1 hour'), 'MEDIUM', TRUE),
('Multiple Failed Logins', 'FREQUENCY_LIMIT', JSON_OBJECT('max_attempts', 5, 'time_period', '15 minutes'), 'HIGH', TRUE),
('Off-Hours Transaction', 'TIME_RESTRICTION', JSON_OBJECT('allowed_hours', '06:00-22:00', 'timezone', 'UTC'), 'LOW', TRUE),
('Rapid Succession Withdrawals', 'FREQUENCY_LIMIT', JSON_OBJECT('max_withdrawals', 5, 'time_period', '10 minutes'), 'MEDIUM', TRUE),
('Large Cash Withdrawal', 'AMOUNT_LIMIT', JSON_OBJECT('max_amount', 5000, 'transaction_type', 'ATM_WITHDRAWAL'), 'MEDIUM', TRUE);

-- =====================================================
-- SAMPLE USER DATA
-- =====================================================

-- Insert sample users
INSERT INTO users (first_name, last_name, email, phone, date_of_birth, address, city, state, postal_code, country, is_active) VALUES
('John', 'Doe', 'john.doe@email.com', '+1-555-0101', '1985-03-15', '123 Main St', 'New York', 'NY', '10001', 'USA', TRUE),
('Jane', 'Smith', 'jane.smith@email.com', '+1-555-0102', '1990-07-22', '456 Oak Ave', 'Los Angeles', 'CA', '90210', 'USA', TRUE),
('Michael', 'Johnson', 'michael.johnson@email.com', '+1-555-0103', '1982-11-08', '789 Pine Rd', 'Chicago', 'IL', '60601', 'USA', TRUE),
('Emily', 'Davis', 'emily.davis@email.com', '+1-555-0104', '1988-05-30', '321 Elm St', 'Houston', 'TX', '77001', 'USA', TRUE),
('David', 'Wilson', 'david.wilson@email.com', '+1-555-0105', '1975-09-12', '654 Maple Dr', 'Phoenix', 'AZ', '85001', 'USA', TRUE),
('Sarah', 'Brown', 'sarah.brown@email.com', '+1-555-0106', '1992-01-18', '987 Cedar Ln', 'Philadelphia', 'PA', '19101', 'USA', TRUE),
('Robert', 'Taylor', 'robert.taylor@email.com', '+1-555-0107', '1980-12-03', '147 Birch St', 'San Antonio', 'TX', '78201', 'USA', TRUE),
('Lisa', 'Anderson', 'lisa.anderson@email.com', '+1-555-0108', '1987-04-25', '258 Spruce Ave', 'San Diego', 'CA', '92101', 'USA', TRUE);

-- Insert authentication data (using SHA2 function available in MySQL 8.0.42)
INSERT INTO user_auth (user_id, username, password_hash, salt) VALUES
(1, 'johndoe', SHA2(CONCAT('password123', 'salt1'), 256), 'salt1'),
(2, 'janesmith', SHA2(CONCAT('securepass456', 'salt2'), 256), 'salt2'),
(3, 'mjohnson', SHA2(CONCAT('mypassword789', 'salt3'), 256), 'salt3'),
(4, 'emilyd', SHA2(CONCAT('strongpass321', 'salt4'), 256), 'salt4'),
(5, 'dwilson', SHA2(CONCAT('password654', 'salt5'), 256), 'salt5'),
(6, 'sarahb', SHA2(CONCAT('securekey987', 'salt6'), 256), 'salt6'),
(7, 'rtaylor', SHA2(CONCAT('mykey147', 'salt7'), 256), 'salt7'),
(8, 'lisaa', SHA2(CONCAT('password258', 'salt8'), 256), 'salt8');

-- =====================================================
-- SAMPLE ACCOUNTS
-- =====================================================

-- Insert sample accounts
INSERT INTO accounts (account_number, user_id, account_type_id, currency_id, balance, available_balance, opened_date, status) VALUES
('ACC001000001', 1, 1, 1, 5000.00, 5000.00, '2023-01-15', 'ACTIVE'), -- John's Savings
('ACC001000002', 1, 2, 1, 2500.00, 2000.00, '2023-01-15', 'ACTIVE'), -- John's Checking
('ACC001000003', 2, 1, 1, 7500.00, 7500.00, '2023-02-20', 'ACTIVE'), -- Jane's Savings
('ACC001000004', 2, 2, 1, 1800.00, 1300.00, '2023-02-20', 'ACTIVE'), -- Jane's Checking
('ACC001000005', 3, 3, 1, 15000.00, 15000.00, '2023-03-10', 'ACTIVE'), -- Michael's Premium Savings
('ACC001000006', 3, 4, 1, 8500.00, 6500.00, '2023-03-10', 'ACTIVE'), -- Michael's Business Checking
('ACC001000007', 4, 1, 1, 3200.00, 3200.00, '2023-04-05', 'ACTIVE'), -- Emily's Savings
('ACC001000008', 4, 2, 1, 950.00, 450.00, '2023-04-05', 'ACTIVE'), -- Emily's Checking
('ACC001000009', 5, 5, 1, 25000.00, 25000.00, '2023-05-12', 'ACTIVE'), -- David's Fixed Deposit
('ACC001000010', 6, 7, 1, 800.00, 800.00, '2023-06-18', 'ACTIVE'), -- Sarah's Student Account
('ACC001000011', 7, 6, 1, 12000.00, 12000.00, '2023-07-22', 'ACTIVE'), -- Robert's Money Market
('ACC001000012', 8, 1, 2, 4500.00, 4500.00, '2023-08-30', 'ACTIVE'); -- Lisa's EUR Savings

-- Insert joint account relationships
INSERT INTO account_owners (account_id, user_id, ownership_type, permissions) VALUES
(1, 1, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(2, 1, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(3, 2, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(4, 2, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(5, 3, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(5, 4, 'JOINT', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER'), -- Emily as joint owner of Michael's account
(6, 3, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(7, 4, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(8, 4, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(9, 5, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(10, 6, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(11, 7, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE'),
(11, 8, 'JOINT', 'VIEW,DEPOSIT'), -- Lisa as joint owner with limited permissions
(12, 8, 'PRIMARY', 'VIEW,DEPOSIT,WITHDRAW,TRANSFER,CLOSE');

COMMIT;

-- Display data loading completion message
SELECT 'Initial Data Loaded Successfully!' AS status,
       'MySQL Version: 8.0.42.0 Compatible' AS version,
       (SELECT COUNT(*) FROM users) AS users_created,
       (SELECT COUNT(*) FROM accounts) AS accounts_created,
       (SELECT COUNT(*) FROM currencies) AS currencies_loaded,
       (SELECT COUNT(*) FROM account_types) AS account_types_loaded;
