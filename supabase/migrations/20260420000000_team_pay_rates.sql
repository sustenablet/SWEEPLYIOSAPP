-- Add pay rate fields to team_members table
ALTER TABLE public.team_members
ADD COLUMN IF NOT EXISTS pay_rate_type text DEFAULT 'per_job',
ADD COLUMN IF NOT EXISTS pay_rate_amount numeric(10,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS pay_rate_enabled boolean DEFAULT false;

-- Create team_member_payments table for tracking payments
CREATE TABLE IF NOT EXISTS public.team_member_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id uuid REFERENCES public.team_members(id) ON DELETE CASCADE,
    owner_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    amount numeric(10,2) NOT NULL,
    period_start date,
    period_end date,
    notes text DEFAULT '',
    paid_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS team_member_payments_member_id_idx ON public.team_member_payments (member_id);
CREATE INDEX IF NOT EXISTS team_member_payments_owner_id_idx ON public.team_member_payments (owner_id);

-- Enable RLS
ALTER TABLE public.team_member_payments ENABLE ROW LEVEL SECURITY;

-- Policy: Owners can manage their team payments
DROP POLICY IF EXISTS "Owners manage team payments" ON public.team_member_payments;
CREATE POLICY "Owners manage team payments"
    ON public.team_member_payments FOR ALL
    USING (auth.uid() = owner_id);

-- Policy: Cleaners can read their own payments
DROP POLICY IF EXISTS "Cleaners read own payments" ON public.team_member_payments;
CREATE POLICY "Cleaners read own payments"
    ON public.team_member_payments FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.team_members tm
            WHERE tm.id = member_id
            AND tm.cleaner_user_id = auth.uid()
        )
    );
