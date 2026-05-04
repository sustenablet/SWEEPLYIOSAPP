-- ── Fix notification triggers ─────────────────────────────────────────────
-- CRITICAL: previous triggers used team_members.id as notifications.user_id
-- causing FK violations and rolling back every job INSERT with an assignment.

-- ============================================================
-- 1. Fix: job created → notify assigned cleaner (look up cleaner_user_id)
-- ============================================================
CREATE OR REPLACE FUNCTION notify_on_job_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cleaner_user_id uuid;
BEGIN
  IF NEW.assigned_member_id IS NOT NULL THEN
    SELECT cleaner_user_id INTO v_cleaner_user_id
    FROM public.team_members
    WHERE id = NEW.assigned_member_id;

    IF v_cleaner_user_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, title, message, kind, job_id)
      VALUES (
        v_cleaner_user_id,
        'New Job Assigned',
        NEW.service_type || ' for ' || NEW.client_name
          || ' on ' || to_char(NEW.scheduled_at, 'Mon DD, YYYY'),
        'jobs',
        NEW.id
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_job_created ON public.jobs;
CREATE TRIGGER on_job_created
  AFTER INSERT ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION notify_on_job_created();

-- ============================================================
-- 2. Fix: job status changed
--    - Cleaner marks complete → notify OWNER (use jobs.user_id ✓)
--    - Job marked in-progress → notify CLEANER (look up cleaner_user_id)
-- ============================================================
CREATE OR REPLACE FUNCTION notify_on_job_status_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cleaner_user_id uuid;
BEGIN
  -- Cleaner completed job → notify owner
  IF NEW.assigned_member_id IS NOT NULL
     AND NEW.status = 'Completed'
     AND OLD.status != 'Completed' THEN
    INSERT INTO public.notifications (user_id, title, message, kind, job_id)
    VALUES (
      NEW.user_id,
      'Job Completed',
      COALESCE(NEW.assigned_member_name, 'Your cleaner')
        || ' completed ' || NEW.service_type || ' for ' || NEW.client_name || '.',
      'jobs',
      NEW.id
    );
  END IF;

  -- Job marked in-progress → notify cleaner
  IF NEW.assigned_member_id IS NOT NULL
     AND NEW.status = 'InProgress'
     AND OLD.status = 'Scheduled' THEN
    SELECT cleaner_user_id INTO v_cleaner_user_id
    FROM public.team_members
    WHERE id = NEW.assigned_member_id;

    IF v_cleaner_user_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, title, message, kind, job_id)
      VALUES (
        v_cleaner_user_id,
        'Job Started',
        NEW.service_type || ' for ' || NEW.client_name || ' is now in progress.',
        'jobs',
        NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_job_status_changed ON public.jobs;
CREATE TRIGGER on_job_status_changed
  AFTER UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION notify_on_job_status_changed();

-- ============================================================
-- 3. Remove: invoice paid trigger (app-side already handles this)
-- ============================================================
DROP TRIGGER IF EXISTS on_invoice_paid ON public.invoices;
DROP FUNCTION IF EXISTS notify_on_invoice_paid();

-- ============================================================
-- 4. Remove: client added trigger (fires on every client, too noisy)
-- ============================================================
DROP TRIGGER IF EXISTS on_client_added ON public.clients;
DROP FUNCTION IF EXISTS notify_on_client_added();
