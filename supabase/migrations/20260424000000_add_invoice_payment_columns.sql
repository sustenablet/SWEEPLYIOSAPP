-- Add payment tracking columns to invoices table
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS paid_amount DOUBLE PRECISION;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE;