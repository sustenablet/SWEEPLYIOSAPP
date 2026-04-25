-- Add is_read column to messages table for read receipts
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false;