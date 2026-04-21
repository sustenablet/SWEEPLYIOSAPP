-- Migrate period_start and period_end from DATE to TIMESTAMPTZ
-- so the Supabase Swift SDK can decode them as Swift Date directly.
ALTER TABLE public.team_member_payments
  ALTER COLUMN period_start TYPE timestamptz USING period_start::timestamptz,
  ALTER COLUMN period_end   TYPE timestamptz USING period_end::timestamptz;
