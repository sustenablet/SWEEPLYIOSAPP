-- Allow cleaners to read their owner's business profile (needed for cleaner profile screen)
DROP POLICY IF EXISTS "Cleaners read owner profile" ON public.profiles;
CREATE POLICY "Cleaners read owner profile"
    ON public.profiles FOR SELECT
    USING (
        id IN (
            SELECT owner_id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
    );
