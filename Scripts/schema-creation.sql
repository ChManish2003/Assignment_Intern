-- =====================================================
-- DevifyX Banking System - Database Schema Creation
-- =====================================================
-- This script creates the complete database schema for the banking system
-- Author: DevifyX MySQL Core Assignment
-- Version: 1.0
-- =====================================================

-- Create the banking database
DROP DATABASE IF EXISTS banking_system;
CREATE DATABASE banking_system;
USE banking_system;

-- =====================================================
-- CORE TABLES
-- =====================================================

-- Users table - stores customer personal information
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE NOT NULL,
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    postal_code VARCHAR(10),
    country VARCHAR(50) DEFAULT 'USA',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    
    -- Constraints
    CONSTRAINT chk_email_format CHECK (email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_age CHECK (DATEDIFF(CURDATE(), date_of_birth) >= 6570) -- Must be 18+ years old
);

-- User authentication table - stores login credentials
CREATE TABLE user_auth (
    auth_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- Store hashed passwords
    salt VARCHAR(32) NOT NULL,
    last_login TIMESTAMP NULL,
    failed_login_attempts INT DEFAULT 0,
    account_locked BOOLEAN DEFAULT FALSE,
    locked_until TIMESTAMP NULL,
    password_changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Account types lookup table
CREATE TABLE account_types (
    type_id INT PRIMARY KEY AUTO_INCREMENT,
    type_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    interest_rate DECIMAL(5,4) DEFAULT 0.0000, -- Annual interest rate
    minimum_balance DECIMAL(15,2) DEFAULT 0.00,
    overdraft_limit DECIMAL(15,2) DEFAULT 0.00,
    monthly_fee DECIMAL(10,2) DEFAULT 0.00,
    transaction_limit_daily INT DEFAULT 0, -- 0 means unlimited
    is_active BOOLEAN DEFAULT TRUE
);

-- Currencies table for multi-currency support
CREATE TABLE currencies (
    currency_id INT PRIMARY KEY AUTO_INCREMENT,
    currency_code VARCHAR(3) NOT NULL UNIQUE,
    currency_name VARCHAR(50) NOT NULL,
    symbol VARCHAR(5),
    exchange_rate DECIMAL(10,6) DEFAULT 1.000000, -- Rate to base currency (USD)
    is_active BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Bank accounts table
CREATE TABLE accounts (
    account_id INT PRIMARY KEY AUTO_INCREMENT,
    account_number VARCHAR(20) NOT NULL UNIQUE,
    user_id INT NOT NULL,
    account_type_id INT NOT NULL,
    currency_id INT NOT NULL DEFAULT 1,
    balance DECIMAL(15,2) DEFAULT 0.00,
    available_balance DECIMAL(15,2) DEFAULT 0.00, -- Balance minus holds
    status ENUM('ACTIVE', 'INACTIVE', 'FROZEN', 'CLOSED') DEFAULT 'ACTIVE',
    opened_date DATE NOT NULL DEFAULT (CURDATE()),
    closed_date DATE NULL,
    last_transaction_date TIMESTAMP NULL,
    interest_earned DECIMAL(15,2) DEFAULT 0.00,
    last_interest_calculation DATE NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (account_type_id) REFERENCES account_types(type_id),
    FOREIGN KEY (currency_id) REFERENCES currencies(currency_id),
    
    -- Constraints
    CONSTRAINT chk_balance_positive CHECK (balance >= 0 OR account_type_id IN (SELECT type_id FROM account_types WHERE overdraft_limit > 0)),
    CONSTRAINT chk_available_balance CHECK (available_balance <= balance)
);

-- Joint account owners (bonus feature)
CREATE TABLE account_owners (
    owner_id INT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NOT NULL,
    user_id INT NOT NULL,
    ownership_type ENUM('PRIMARY', 'JOINT', 'BENEFICIARY') DEFAULT 'JOINT',
    permissions SET('VIEW', 'DEPOSIT', 'WITHDRAW', 'TRANSFER', 'CLOSE') DEFAULT 'VIEW,DEPOSIT',
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    
    UNIQUE KEY unique_account_user (account_id, user_id)
);

-- Transaction types lookup
CREATE TABLE transaction_types (
    type_id INT PRIMARY KEY AUTO_INCREMENT,
    type_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    affects_balance BOOLEAN DEFAULT TRUE,
    requires_approval BOOLEAN DEFAULT FALSE
);

-- Transactions table
CREATE TABLE transactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    transaction_number VARCHAR(50) NOT NULL UNIQUE,
    account_id INT NOT NULL,
    transaction_type_id INT NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    currency_id INT NOT NULL,
    exchange_rate DECIMAL(10,6) DEFAULT 1.000000,
    balance_before DECIMAL(15,2) NOT NULL,
    balance_after DECIMAL(15,2) NOT NULL,
    description TEXT,
    reference_number VARCHAR(100),
    related_account_id INT NULL, -- For transfers
    status ENUM('PENDING', 'COMPLETED', 'FAILED', 'CANCELLED') DEFAULT 'PENDING',
    processed_by INT NULL, -- User who processed (for manual transactions)
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_date TIMESTAMP NULL,
    
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    FOREIGN KEY (transaction_type_id) REFERENCES transaction_types(type_id),
    FOREIGN KEY (currency_id) REFERENCES currencies(currency_id),
    FOREIGN KEY (related_account_id) REFERENCES accounts(account_id),
    FOREIGN KEY (processed_by) REFERENCES users(user_id),
    
    -- Constraints
    CONSTRAINT chk_amount_positive CHECK (amount > 0),
    
    -- Indexes for performance
    INDEX idx_account_date (account_id, transaction_date),
    INDEX idx_transaction_number (transaction_number),
    INDEX idx_status_date (status, transaction_date)
);

-- =====================================================
-- AUDIT AND SECURITY TABLES
-- =====================================================

-- Security logs table
CREATE TABLE security_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NULL,
    action_type ENUM('LOGIN_SUCCESS', 'LOGIN_FAILED', 'LOGOUT', 'PASSWORD_CHANGE', 
                     'ACCOUNT_LOCKED', 'ACCOUNT_UNLOCKED', 'TRANSACTION_FAILED', 
                     'SUSPICIOUS_ACTIVITY', 'DATA_MODIFICATION') NOT NULL,
    description TEXT,
    ip_address VARCHAR(45), -- Supports IPv6
    user_agent TEXT,
    session_id VARCHAR(100),
    severity ENUM('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') DEFAULT 'LOW',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    
    -- Indexes
    INDEX idx_user_action (user_id, action_type),
    INDEX idx_severity_date (severity, created_at),
    INDEX idx_action_date (action_type, created_at)
);

-- Audit trail table
CREATE TABLE audit_trail (
    audit_id INT PRIMARY KEY AUTO_INCREMENT,
    table_name VARCHAR(50) NOT NULL,
    record_id INT NOT NULL,
    action_type ENUM('INSERT', 'UPDATE', 'DELETE') NOT NULL,
    old_values JSON NULL,
    new_values JSON NULL,
    changed_by INT NULL,
    change_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (changed_by) REFERENCES users(user_id),
    
    -- Indexes
    INDEX idx_table_record (table_name, record_id),
    INDEX idx_changed_by_date (changed_by, created_at),
    INDEX idx_action_date (action_type, created_at)
);

-- Account holds table (for pending transactions, fraud prevention)
CREATE TABLE account_holds (
    hold_id INT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    hold_type ENUM('TRANSACTION', 'FRAUD', 'LEGAL', 'MAINTENANCE') DEFAULT 'TRANSACTION',
    description TEXT,
    placed_by INT NULL,
    placed_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    release_date TIMESTAMP NULL,
    status ENUM('ACTIVE', 'RELEASED', 'EXPIRED') DEFAULT 'ACTIVE',
    
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    FOREIGN KEY (placed_by) REFERENCES users(user_id),
    
    CONSTRAINT chk_hold_amount_positive CHECK (amount > 0)
);

-- Fraud detection rules
CREATE TABLE fraud_rules (
    rule_id INT PRIMARY KEY AUTO_INCREMENT,
    rule_name VARCHAR(100) NOT NULL,
    rule_type ENUM('AMOUNT_LIMIT', 'FREQUENCY_LIMIT', 'LOCATION_CHECK', 'TIME_RESTRICTION') NOT NULL,
    parameters JSON NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    severity ENUM('LOW', 'MEDIUM', 'HIGH') DEFAULT 'MEDIUM',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Fraud alerts
CREATE TABLE fraud_alerts (
    alert_id INT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NOT NULL,
    transaction_id INT NULL,
    rule_id INT NOT NULL,
    alert_type VARCHAR(50) NOT NULL,
    description TEXT,
    risk_score INT DEFAULT 0, -- 0-100
    status ENUM('OPEN', 'INVESTIGATING', 'RESOLVED', 'FALSE_POSITIVE') DEFAULT 'OPEN',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    resolved_by INT NULL,
    
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id),
    FOREIGN KEY (rule_id) REFERENCES fraud_rules(rule_id),
    FOREIGN KEY (resolved_by) REFERENCES users(user_id)
);

-- =====================================================
-- REPORTING AND STATEMENTS TABLES
-- =====================================================

-- Account statements
CREATE TABLE account_statements (
    statement_id INT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NOT NULL,
    statement_period_start DATE NOT NULL,
    statement_period_end DATE NOT NULL,
    opening_balance DECIMAL(15,2) NOT NULL,
    closing_balance DECIMAL(15,2) NOT NULL,
    total_deposits DECIMAL(15,2) DEFAULT 0.00,
    total_withdrawals DECIMAL(15,2) DEFAULT 0.00,
    total_fees DECIMAL(15,2) DEFAULT 0.00,
    interest_earned DECIMAL(15,2) DEFAULT 0.00,
    transaction_count INT DEFAULT 0,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    
    UNIQUE KEY unique_account_period (account_id, statement_period_start, statement_period_end)
);

-- System configuration table
CREATE TABLE system_config (
    config_id INT PRIMARY KEY AUTO_INCREMENT,
    config_key VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    updated_by INT NULL,
    
    FOREIGN KEY (updated_by) REFERENCES users(user_id)
);

-- =====================================================
-- INDEXES FOR PERFORMANCE OPTIMIZATION
-- =====================================================

-- Additional indexes for better query performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_active ON users(is_active);
CREATE INDEX idx_accounts_user ON accounts(user_id);
CREATE INDEX idx_accounts_status ON accounts(status);
CREATE INDEX idx_accounts_type ON accounts(account_type_id);
CREATE INDEX idx_transactions_account_date ON transactions(account_id, transaction_date DESC);
CREATE INDEX idx_security_logs_user_date ON security_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_trail_table_date ON audit_trail(table_name, created_at DESC);

-- =====================================================
-- INITIAL SYSTEM CONFIGURATION
-- =====================================================

-- Insert system configuration values
INSERT INTO system_config (config_key, config_value, description) VALUES
('INTEREST_CALCULATION_DAY', '1', 'Day of month to calculate interest (1-28)'),
('MAX_DAILY_TRANSACTIONS', '50', 'Maximum transactions per account per day'),
('MAX_FAILED_LOGIN_ATTEMPTS', '5', 'Maximum failed login attempts before account lock'),
('ACCOUNT_LOCK_DURATION_MINUTES', '30', 'Duration to lock account after max failed attempts'),
('FRAUD_ALERT_THRESHOLD', '75', 'Risk score threshold for fraud alerts'),
('STATEMENT_GENERATION_DAY', '1', 'Day of month to generate statements'),
('BASE_CURRENCY', 'USD', 'Base currency for the system'),
('MINIMUM_AGE_YEARS', '18', 'Minimum age to open an account');

COMMIT;
