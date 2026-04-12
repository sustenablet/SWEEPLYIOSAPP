-- Fix schema gaps: add missing columns to invoices, clients, and jobs tables

-- invoices: add notes and line_items (JSON-encoded array)
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS line_items text;

-- clients: add geocoding and soft-delete columns
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

-- jobs: ensure all expected columns exist
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS is_recurring boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS recurrence_rule_id UUID REFERENCES public.recurrence_rules(id) ON DELETE SET NULL;
