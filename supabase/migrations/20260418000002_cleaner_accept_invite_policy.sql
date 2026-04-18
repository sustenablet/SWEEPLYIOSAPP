-- Allow cleaners to accept/decline their own invite by updating their team_members row
DROP POLICY IF EXISTS "Cleaners can update own membership" ON public.team_members;
CREATE POLICY "Cleaners can update own membership"
    ON public.team_members FOR UPDATE
    USING (cleaner_user_id = auth.uid())
    WITH CHECK (cleaner_user_id = auth.uid());
