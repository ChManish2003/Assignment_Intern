# DevifyX Banking System - MySQL Core Assignment

## Overview

This is a comprehensive MySQL-based banking system that supports user accounts, transactions, interest calculations, security logging, and fraud detection. The system is designed to be robust, secure, and efficient with proper data integrity constraints and audit trails.

## Features

### Core Features
- **User Account Management**: Create, update, and delete user accounts with personal information
- **Multiple Account Types**: Support for Savings, Checking, Premium Savings, Business Checking, Fixed Deposit, Money Market, and Student accounts
- **Transaction Processing**: Deposits, withdrawals, and transfers with complete transaction history
- **Interest Calculation**: Automated monthly interest calculation and crediting
- **Balance Validation**: Prevents overdrafts and ensures transactional integrity
- **Security Logging**: Records all critical actions and failed transactions
- **Audit Trail**: Complete audit trail for all transactions and modifications
- **User Authentication**: Secure password storage with salt hashing

### Bonus Features
- **Joint Accounts**: Support for multiple account owners with different permission levels
- **Account Locking**: Automatic account locking after failed login attempts
- **Monthly Statements**: Automated statement generation via stored procedures
- **Fraud Detection**: Real-time fraud detection with configurable rules
- **Multi-Currency Support**: Support for multiple currencies with exchange rates

## Database Schema

### Core Tables
- `users` - Customer personal information
- `user_auth` - Authentication credentials and security settings
- `accounts` - Bank account details and balances
- `account_types` - Account type definitions with interest rates and limits
- `transactions` - All transaction records with complete details
- `currencies` - Multi-currency support with exchange rates

### Security Tables
- `security_logs` - Security events and login attempts
- `audit_trail` - Complete audit trail of all data changes
- `fraud_alerts` - Fraud detection alerts and investigations
- `account_holds` - Account holds for fraud prevention

### Supporting Tables
- `account_owners` - Joint account ownership relationships
- `transaction_types` - Transaction type definitions
- `fraud_rules` - Configurable fraud detection rules
- `account_statements` - Monthly account statements
- `system_config` - System configuration parameters

## Installation and Setup

### Prerequisites
- MySQL 8.0 or higher
- Sufficient privileges to create databases and execute stored procedures

### Installation Steps

1. **Create the Database Schema**
   \`\`\`sql
   mysql -u root -p < scripts/01-schema-creation.sql
   \`\`\`

2. **Load Initial Data**
   \`\`\`sql
   mysql -u root -p < scripts/02-initial-data.sql
   \`\`\`

3. **Create Stored Procedures**
   \`\`\`sql
   mysql -u root -p < scripts/03-stored-procedures.sql
   \`\`\`

4. **Create Triggers**
   \`\`\`sql
   mysql -u root -p < scripts/04-triggers.sql
   \`\`\`

5. **Create Views**
   \`\`\`sql
   mysql -u root -p < scripts/05-views.sql
   \`\`\`

6. **Load Sample Transactions**
   \`\`\`sql
   mysql -u root -p < scripts/06-sample-transactions.sql
   \`\`\`

7. **Run Tests (Optional)**
   \`\`\`sql
   mysql -u root -p < scripts/07-test-procedures.sql
   \`\`\`

## Usage Examples

### Creating a New Account
\`\`\`sql
CALL CreateAccount(1, 1, 1, 1000.00, @account_id, @account_number, @result);
SELECT @account_id, @account_number, @result;
\`\`\`

### Making a Deposit
\`\`\`sql
CALL MakeDeposit(1, 500.00, 1, 'Payroll deposit', 'PAY001', @trans_id, @result);
SELECT @trans_id, @result;
\`\`\`

### Making a Withdrawal
\`\`\`sql
CALL MakeWithdrawal(1, 200.00, 1, 'ATM withdrawal', 'ATM001', @trans_id, @result);
SELECT @trans_id, @result;
\`\`\`

### Transferring Funds
\`\`\`sql
CALL TransferFunds(1, 2, 300.00, 1, 'Transfer to checking', 'TRANS001', @from_trans, @to_trans, @result);
SELECT @from_trans, @to_trans, @result;
\`\`\`

### User Authentication
\`\`\`sql
CALL AuthenticateUser('johndoe', 'password123', '192.168.1.100', 'Mozilla/5.0', @user_id, @result);
SELECT @user_id, @result;
\`\`\`

### Calculating Monthly Interest
\`\`\`sql
CALL CalculateMonthlyInterest();
\`\`\`

### Generating Monthly Statements
\`\`\`sql
CALL GenerateMonthlyStatements(12, 2024);
\`\`\`

## Key Views for Reporting

### Account Summary
\`\`\`sql
SELECT * FROM vw_account_summary WHERE account_holder = 'John Doe';
\`\`\`

### Transaction History
\`\`\`sql
SELECT * FROM vw_transaction_history WHERE account_number = 'ACC001000001' 
ORDER BY transaction_date DESC LIMIT 10;
\`\`\`

### Security Incidents
\`\`\`sql
SELECT * FROM vw_security_incidents WHERE severity = 'HIGH';
\`\`\`

### Active Fraud Alerts
\`\`\`sql
SELECT * FROM vw_active_fraud_alerts ORDER BY risk_score DESC;
\`\`\`

### Customer Portfolio
\`\`\`sql
SELECT * FROM vw_customer_portfolio WHERE customer_name LIKE '%John%';
\`\`\`

## Security Features

### Password Security
- Passwords are hashed using SHA2 with unique salts
- Account lockout after 5 failed login attempts
- Automatic unlock after 30 minutes

### Fraud Detection
- Large transaction alerts (>$10,000)
- Rapid transaction detection (>5 transactions in 10 minutes)
- Off-hours transaction monitoring
- Configurable fraud rules and thresholds

### Audit Trail
- Complete audit trail for all data modifications
- Security event logging with severity levels
- Transaction history preservation (cannot be deleted)

### Data Integrity
- Foreign key constraints ensure referential integrity
- Check constraints validate data ranges and formats
- Triggers prevent unauthorized data deletion
- Balance validation prevents overdrafts beyond limits

## Testing

Run the comprehensive test suite:
\`\`\`sql
USE banking_system;
CALL RunAllTests();
\`\`\`

The test suite validates:
- Account creation functionality
- Transaction processing
- Fraud detection triggers
- Interest calculation
- User authentication
- Transfer functionality

## Configuration

System configuration can be modified through the `system_config` table:

\`\`\`sql
-- Update interest calculation day
UPDATE system_config 
SET config_value = '15' 
WHERE config_key = 'INTEREST_CALCULATION_DAY';

-- Update fraud alert threshold
UPDATE system_config 
SET config_value = '80' 
WHERE config_key = 'FRAUD_ALERT_THRESHOLD';
\`\`\`

## Performance Considerations

### Indexes
The system includes optimized indexes for:
- Account lookups by user and status
- Transaction history queries
- Security log searches
- Audit trail queries

### Partitioning (Recommended for Production)
For large-scale deployments, consider partitioning:
- `transactions` table by date
- `security_logs` table by date
- `audit_trail` table by date

## Maintenance Procedures

### Monthly Tasks
\`\`\`sql
-- Calculate interest for all accounts
CALL CalculateMonthlyInterest();

-- Generate monthly statements
CALL GenerateMonthlyStatements(MONTH(CURDATE()), YEAR(CURDATE()));
\`\`\`

### Weekly Tasks
\`\`\`sql
-- Review fraud alerts
SELECT * FROM vw_active_fraud_alerts;

-- Check system health
SELECT * FROM vw_system_health_metrics;
\`\`\`

## Troubleshooting

### Common Issues

1. **Transaction Failures**
   - Check account status and balance
   - Verify transaction limits
   - Review fraud alerts

2. **Authentication Issues**
   - Check account lock status
   - Verify password hash generation
   - Review security logs

3. **Interest Calculation Problems**
   - Verify account type interest rates
   - Check last calculation dates
   - Review system configuration

### Error Codes
- `45000`: Custom validation error (check error message)
- Foreign key constraint errors: Data integrity violation
- Duplicate key errors: Unique constraint violation

## Future Enhancements

Potential improvements for production deployment:
- Integration with external payment systems
- Mobile banking API endpoints
- Advanced fraud detection using machine learning
- Real-time transaction processing
- Automated regulatory reporting
- Customer notification system

## License

This project is created for educational purposes as part of the DevifyX MySQL Core Assignment.

## Support

For technical support or questions about the banking system implementation, please refer to the inline SQL comments and stored procedure documentation within the code files.
