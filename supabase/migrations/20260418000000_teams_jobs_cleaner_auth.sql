-- ── Teams & Jobs: missing columns + cleaner auth foundation ──────────────────

-- 1. team_members: add phone + cleaner_user_id
ALTER TABLE public.team_members
    ADD COLUMN IF NOT EXISTS phone           text NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS cleaner_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS team_members_cleaner_user_id_idx
    ON public.team_members (cleaner_user_id);

-- 2. jobs: add assignment columns
ALTER TABLE public.jobs
    ADD COLUMN IF NOT EXISTS assigned_member_id   uuid REFERENCES public.team_members (id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS assigned_member_name text;

CREATE INDEX IF NOT EXISTS jobs_assigned_member_id_idx
    ON public.jobs (assigned_member_id);

-- 3. RLS: cleaners can read their own team_member row
DROP POLICY IF EXISTS "Cleaners read own membership" ON public.team_members;
CREATE POLICY "Cleaners read own membership"
    ON public.team_members FOR SELECT
    USING (auth.uid() = cleaner_user_id);

-- 4. RLS: cleaners can read jobs assigned to them
DROP POLICY IF EXISTS "Cleaners read assigned jobs" ON public.jobs;
CREATE POLICY "Cleaners read assigned jobs"
    ON public.jobs FOR SELECT
    USING (
        assigned_member_id IN (
            SELECT id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
    );

-- 5. RLS: cleaners can update the status of their own assigned jobs
--    (mark as in-progress or completed from their view)
DROP POLICY IF EXISTS "Cleaners update assigned job status" ON public.jobs;
CREATE POLICY "Cleaners update assigned job status"
    ON public.jobs FOR UPDATE
    USING (
        assigned_member_id IN (
            SELECT id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
    )
    WITH CHECK (
        assigned_member_id IN (
            SELECT id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
    );

-- 6. Auto-link trigger: when a new user signs up, check if their email
--    matches any pending team_member invite and link cleaner_user_id
CREATE OR REPLACE FUNCTION public.handle_cleaner_signup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE public.team_members
    SET    cleaner_user_id = new.id
    WHERE  lower(email) = lower(new.email)
      AND  cleaner_user_id IS NULL;
    RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_cleaner_signup ON auth.users;
CREATE TRIGGER on_cleaner_signup
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_cleaner_signup();

-- 7. Back-fill: link existing users to any matching pending invites
UPDATE public.team_members tm
SET    cleaner_user_id = u.id
FROM   auth.users u
WHERE  lower(tm.email) = lower(u.email)
  AND  tm.cleaner_user_id IS NULL;
