-- =====================================================
-- DevifyX Banking System - Sample Transactions
-- =====================================================
-- This script creates sample transactions to demonstrate system functionality
-- =====================================================

USE banking_system;

-- =====================================================
-- SAMPLE DEPOSITS
-- =====================================================

-- John Doe deposits
CALL MakeDeposit(1, 1000.00, 1, 'Payroll deposit', 'PAY001', @trans_id, @result);
CALL MakeDeposit(2, 500.00, 1, 'Cash deposit', 'CASH001', @trans_id, @result);

-- Jane Smith deposits
CALL MakeDeposit(3, 2000.00, 1, 'Business income', 'BIZ001', @trans_id, @result);
CALL MakeDeposit(4, 300.00, 1, 'Gift deposit', 'GIFT001', @trans_id, @result);

-- Michael Johnson deposits
CALL MakeDeposit(5, 5000.00, 1, 'Investment return', 'INV001', @trans_id, @result);
CALL MakeDeposit(6, 1200.00, 1, 'Consulting fee', 'CONS001', @trans_id, @result);

-- =====================================================
-- SAMPLE WITHDRAWALS
-- =====================================================

-- John Doe withdrawals
CALL MakeWithdrawal(2, 200.00, 1, 'ATM withdrawal', 'ATM001', @trans_id, @result);
CALL MakeWithdrawal(2, 150.00, 1, 'Grocery shopping', 'POS001', @trans_id, @result);

-- Jane Smith withdrawals
CALL MakeWithdrawal(4, 100.00, 1, 'Gas station', 'POS002', @trans_id, @result);

-- Emily Davis withdrawals
CALL MakeWithdrawal(8, 50.00, 1, 'Coffee shop', 'POS003', @trans_id, @result);

-- =====================================================
-- SAMPLE TRANSFERS
-- =====================================================

-- Transfer from John's checking to savings
CALL TransferFunds(2, 1, 500.00, 1, 'Monthly savings transfer', 'TRANS001', @from_trans, @to_trans, @result);

-- Transfer from Jane's savings to checking
CALL TransferFunds(3, 4, 800.00, 1, 'Bill payment preparation', 'TRANS002', @from_trans, @to_trans, @result);

-- Transfer from Michael's premium savings to business checking
CALL TransferFunds(5, 6, 2000.00, 1, 'Business expense funding', 'TRANS003', @from_trans, @to_trans, @result);

-- Transfer between different users (Jane to Emily)
CALL TransferFunds(3, 7, 300.00, 1, 'Loan repayment', 'TRANS004', @from_trans, @to_trans, @result);

-- =====================================================
-- SAMPLE BILL PAYMENTS AND OTHER TRANSACTIONS
-- =====================================================

-- Insert some bill payment transactions manually to show variety
INSERT INTO transactions (
    transaction_number, account_id, transaction_type_id, amount, currency_id,
    balance_before, balance_after, description, reference_number, status, transaction_date
) VALUES 
-- John's bill payments
('TXN20241201001', 2, (SELECT type_id FROM transaction_types WHERE type_name = 'BILL_PAYMENT'), 
 120.00, 1, 1650.00, 1530.00, 'Electric bill payment', 'ELEC001', 'COMPLETED', '2024-12-01 09:30:00'),

('TXN20241201002', 2, (SELECT type_id FROM transaction_types WHERE type_name = 'BILL_PAYMENT'), 
 80.00, 1, 1530.00, 1450.00, 'Internet bill payment', 'NET001', 'COMPLETED', '2024-12-01 14:15:00'),

-- Jane's online purchases
('TXN20241201003', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'BILL_PAYMENT'), 
 250.00, 1, 1400.00, 1150.00, 'Online shopping', 'SHOP001', 'COMPLETED', '2024-12-01 16:45:00'),

-- Michael's business expenses
('TXN20241201004', 6, (SELECT type_id FROM transaction_types WHERE type_name = 'BILL_PAYMENT'), 
 500.00, 1, 7700.00, 7200.00, 'Office supplies', 'OFF001', 'COMPLETED', '2024-12-01 11:20:00'),

-- Direct deposits (payroll)
('TXN20241201005', 1, (SELECT type_id FROM transaction_types WHERE type_name = 'DIRECT_DEPOSIT'), 
 3200.00, 1, 6000.00, 9200.00, 'Salary deposit', 'SAL001', 'COMPLETED', '2024-12-01 08:00:00'),

('TXN20241201006', 3, (SELECT type_id FROM transaction_types WHERE type_name = 'DIRECT_DEPOSIT'), 
 2800.00, 1, 8700.00, 11500.00, 'Salary deposit', 'SAL002', 'COMPLETED', '2024-12-01 08:00:00');

-- Update account balances to match the transactions
UPDATE accounts SET balance = 9200.00, available_balance = 9200.00 WHERE account_id = 1;
UPDATE accounts SET balance = 1450.00, available_balance = 1450.00 WHERE account_id = 2;
UPDATE accounts SET balance = 11500.00, available_balance = 11500.00 WHERE account_id = 3;
UPDATE accounts SET balance = 1150.00, available_balance = 1150.00 WHERE account_id = 4;
UPDATE accounts SET balance = 18000.00, available_balance = 18000.00 WHERE account_id = 5;
UPDATE accounts SET balance = 7200.00, available_balance = 7200.00 WHERE account_id = 6;
UPDATE accounts SET balance = 3500.00, available_balance = 3500.00 WHERE account_id = 7;
UPDATE accounts SET balance = 900.00, available_balance = 900.00 WHERE account_id = 8;

-- =====================================================
-- SAMPLE FRAUD SCENARIOS (for testing)
-- =====================================================

-- Large transaction that should trigger fraud alert
INSERT INTO transactions (
    transaction_number, account_id, transaction_type_id, amount, currency_id,
    balance_before, balance_after, description, reference_number, status, transaction_date
) VALUES 
('TXN20241201007', 5, (SELECT type_id FROM transaction_types WHERE type_name = 'WITHDRAWAL'), 
 15000.00, 1, 18000.00, 3000.00, 'Large cash withdrawal', 'LARGE001', 'COMPLETED', '2024-12-01 23:30:00');

-- Update balance for the large transaction
UPDATE accounts SET balance = 3000.00, available_balance = 3000.00 WHERE account_id = 5;

-- Multiple rapid transactions (should trigger fraud alert)
INSERT INTO transactions (
    transaction_number, account_id, transaction_type_id, amount, currency_id,
    balance_before, balance_after, description, reference_number, status, transaction_date
) VALUES 
('TXN20241201008', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'ATM_WITHDRAWAL'), 
 200.00, 1, 1150.00, 950.00, 'ATM withdrawal #1', 'ATM001', 'COMPLETED', '2024-12-01 22:00:00'),
('TXN20241201009', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'ATM_WITHDRAWAL'), 
 200.00, 1, 950.00, 750.00, 'ATM withdrawal #2', 'ATM002', 'COMPLETED', '2024-12-01 22:02:00'),
('TXN20241201010', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'ATM_WITHDRAWAL'), 
 200.00, 1, 750.00, 550.00, 'ATM withdrawal #3', 'ATM003', 'COMPLETED', '2024-12-01 22:04:00'),
('TXN20241201011', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'ATM_WITHDRAWAL'), 
 200.00, 1, 550.00, 350.00, 'ATM withdrawal #4', 'ATM004', 'COMPLETED', '2024-12-01 22:06:00'),
('TXN20241201012', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'ATM_WITHDRAWAL'), 
 200.00, 1, 350.00, 150.00, 'ATM withdrawal #5', 'ATM005', 'COMPLETED', '2024-12-01 22:08:00'),
('TXN20241201013', 4, (SELECT type_id FROM transaction_types WHERE type_name = 'ATM_WITHDRAWAL'), 
 150.00, 1, 150.00, 0.00, 'ATM withdrawal #6', 'ATM006', 'COMPLETED', '2024-12-01 22:10:00');

-- Update balance for rapid transactions
UPDATE accounts SET balance = 0.00, available_balance = 0.00 WHERE account_id = 4;

-- =====================================================
-- SAMPLE ACCOUNT HOLDS
-- =====================================================

-- Place a hold on an account for fraud investigation
INSERT INTO account_holds (account_id, amount, hold_type, description, placed_date) VALUES
(5, 1000.00, 'FRAUD', 'Hold placed due to large transaction alert', '2024-12-01 23:45:00'),
(4, 500.00, 'FRAUD', 'Hold placed due to rapid transaction pattern', '2024-12-01 22:15:00');

-- Update available balances to reflect holds
UPDATE accounts SET available_balance = balance - 1000.00 WHERE account_id = 5;
UPDATE accounts SET available_balance = balance - 500.00 WHERE account_id = 4;

-- =====================================================
-- SAMPLE SECURITY LOG ENTRIES
-- =====================================================

-- Sample login attempts
INSERT INTO security_logs (user_id, action_type, description, ip_address, user_agent, severity, created_at) VALUES
(1, 'LOGIN_SUCCESS', 'Successful login', '192.168.1.100', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'LOW', '2024-12-01 08:00:00'),
(2, 'LOGIN_SUCCESS', 'Successful login', '192.168.1.101', 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0)', 'LOW', '2024-12-01 09:15:00'),
(3, 'LOGIN_FAILED', 'Invalid password', '192.168.1.102', 'Mozilla/5.0 (Android 10)', 'MEDIUM', '2024-12-01 10:30:00'),
(3, 'LOGIN_SUCCESS', 'Successful login after password reset', '192.168.1.102', 'Mozilla/5.0 (Android 10)', 'LOW', '2024-12-01 10:35:00'),
(NULL, 'LOGIN_FAILED', 'Failed login attempt for username: hackuser', '10.0.0.1', 'curl/7.68.0', 'HIGH', '2024-12-01 02:30:00'),
(4, 'SUSPICIOUS_ACTIVITY', 'Multiple rapid ATM withdrawals detected', '192.168.1.103', 'ATM Terminal', 'HIGH', '2024-12-01 22:15:00');

COMMIT;

-- Display summary of sample data created
SELECT 'Sample data creation completed successfully' AS status;

SELECT 
    'Accounts Created' AS item,
    COUNT(*) AS count
FROM accounts
UNION ALL
SELECT 
    'Users Created' AS item,
    COUNT(*) AS count
FROM users
UNION ALL
SELECT 
    'Transactions Created' AS item,
    COUNT(*) AS count
FROM transactions
UNION ALL
SELECT 
    'Security Log Entries' AS item,
    COUNT(*) AS count
FROM security_logs;
