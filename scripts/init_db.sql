-- Customers table
CREATE TABLE IF NOT EXISTS customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Users table for login
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL, -- WARNING: In a real app, this MUST be a hashed password!
  customer_id INTEGER REFERENCES customers(id)
);
-- Accounts table
CREATE TABLE IF NOT EXISTS accounts (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  account_number TEXT NOT NULL UNIQUE,
  balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Insert some sample data
INSERT INTO customers (name, email) VALUES ('Alice Johnson', 'alice@example.com') ON CONFLICT (email) DO NOTHING;
INSERT INTO customers (name, email) VALUES ('Bob Smith', 'bob@example.com') ON CONFLICT (email) DO NOTHING;
-- Insert a user for Alice (password: password123)
-- NOTE: Storing plaintext passwords is a major security risk. Use a library like Werkzeug or passlib to hash passwords.
INSERT INTO users (username, password, customer_id)
SELECT 'alice', 'password123', id FROM customers WHERE email = 'alice@example.com'
ON CONFLICT (username) DO NOTHING;
-- Insert accounts for customers
INSERT INTO accounts (customer_id, account_number, balance)
SELECT id, 'ACC001', 1500.75 FROM customers WHERE email = 'alice@example.com'
ON CONFLICT (account_number) DO NOTHING;
