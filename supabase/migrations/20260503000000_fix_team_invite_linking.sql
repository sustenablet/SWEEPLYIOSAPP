-- ── Fix team invite linking ────────────────────────────────────────────────
-- Ensures all invite-linking functions, triggers, and RLS policies exist.
-- Safe to re-run: uses CREATE OR REPLACE / DROP IF EXISTS throughout.

-- 1. Add cleaner_user_id column if it doesn't exist yet
ALTER TABLE public.team_members
    ADD COLUMN IF NOT EXISTS cleaner_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS team_members_cleaner_user_id_idx
    ON public.team_members (cleaner_user_id);

-- 2. RLS: owners manage everything on their team
DROP POLICY IF EXISTS "Owners manage their team" ON public.team_members;
CREATE POLICY "Owners manage their team"
    ON public.team_members FOR ALL
    USING  (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- 3. RLS: cleaners can SELECT their own membership row (by cleaner_user_id)
DROP POLICY IF EXISTS "Cleaners read own membership" ON public.team_members;
CREATE POLICY "Cleaners read own membership"
    ON public.team_members FOR SELECT
    USING (auth.uid() = cleaner_user_id);

-- 4. RLS: cleaners can UPDATE their own membership row (accept/decline)
DROP POLICY IF EXISTS "Cleaners can update own membership" ON public.team_members;
CREATE POLICY "Cleaners can update own membership"
    ON public.team_members FOR UPDATE
    USING  (cleaner_user_id = auth.uid())
    WITH CHECK (cleaner_user_id = auth.uid());

-- 5. Trigger function: auto-link when a NEW user signs up
CREATE OR REPLACE FUNCTION public.handle_cleaner_signup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
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

-- 6. RPC: link a specific invite by invite_id (called at invite time)
CREATE OR REPLACE FUNCTION public.link_existing_cleaner(invite_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
    UPDATE public.team_members tm
    SET    cleaner_user_id = u.id
    FROM   auth.users u
    WHERE  tm.id = invite_id
      AND  lower(tm.email) = lower(u.email)
      AND  tm.cleaner_user_id IS NULL;
END;
$$;

-- 7. RPC: called on every login — links any unlinked invites for the current user's email
CREATE OR REPLACE FUNCTION public.link_invites_by_email()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_user_id    uuid;
    v_user_email text;
BEGIN
    v_user_id := auth.uid();
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    UPDATE public.team_members
    SET    cleaner_user_id = v_user_id
    WHERE  lower(email) = lower(v_user_email)
      AND  cleaner_user_id IS NULL;
END;
$$;

-- 8. Back-fill: link all existing users to any pending invites right now
UPDATE public.team_members tm
SET    cleaner_user_id = u.id
FROM   auth.users u
WHERE  lower(tm.email) = lower(u.email)
  AND  tm.cleaner_user_id IS NULL;
