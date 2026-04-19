-- Fix: change expenses.date from DATE to TIMESTAMPTZ so the Supabase Swift SDK
-- can decode it correctly as a Swift Date (ISO8601 full timestamp).
ALTER TABLE public.expenses
  ALTER COLUMN date TYPE timestamptz USING date::timestamptz;

-- Reset the default to now() for consistency
ALTER TABLE public.expenses
  ALTER COLUMN date SET DEFAULT now();
