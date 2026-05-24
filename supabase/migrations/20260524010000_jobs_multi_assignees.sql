-- Multi-member job assignments
-- Adds array-based assignees while keeping legacy single-assignee columns
-- for backward compatibility.

ALTER TABLE public.jobs
    ADD COLUMN IF NOT EXISTS assigned_member_ids uuid[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS assigned_member_names text[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS jobs_assigned_member_ids_gin_idx
    ON public.jobs USING gin (assigned_member_ids);

-- Cleaners can read jobs where they are either the legacy assignee
-- or included in the new assignee array.
DROP POLICY IF EXISTS "Cleaners read assigned jobs" ON public.jobs;
CREATE POLICY "Cleaners read assigned jobs"
    ON public.jobs FOR SELECT
    USING (
        assigned_member_id IN (
            SELECT id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1
            FROM public.team_members tm
            WHERE tm.cleaner_user_id = auth.uid()
              AND tm.id = ANY(public.jobs.assigned_member_ids)
        )
    );

-- Cleaners can update status for jobs assigned to them (legacy or array).
DROP POLICY IF EXISTS "Cleaners update assigned job status" ON public.jobs;
CREATE POLICY "Cleaners update assigned job status"
    ON public.jobs FOR UPDATE
    USING (
        assigned_member_id IN (
            SELECT id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1
            FROM public.team_members tm
            WHERE tm.cleaner_user_id = auth.uid()
              AND tm.id = ANY(public.jobs.assigned_member_ids)
        )
    )
    WITH CHECK (
        assigned_member_id IN (
            SELECT id FROM public.team_members
            WHERE cleaner_user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1
            FROM public.team_members tm
            WHERE tm.cleaner_user_id = auth.uid()
              AND tm.id = ANY(public.jobs.assigned_member_ids)
        )
    );
