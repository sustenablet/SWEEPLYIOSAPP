-- Server-side triggers to auto-create in-app notifications for owners.
-- This ensures notifications reach users even when the app is closed.
-- The 'notifications' table already has RLS, so this uses SECURITY DEFINER
-- to insert into the owner's notifications row.

-- ============================================================
-- 1. Job created → notify assigned cleaner (if any)
-- ============================================================

CREATE OR REPLACE FUNCTION notify_on_job_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.assigned_member_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, title, message, kind, job_id)
    VALUES (
      NEW.assigned_member_id,
      'New Job Assigned',
      NEW.service_type || ' for ' || NEW.client_name || ' on ' || to_char(NEW.scheduled_at, 'MMM D, YYYY'),
      'jobs',
      NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_job_created ON jobs;
CREATE TRIGGER on_job_created
  AFTER INSERT ON jobs
  FOR EACH ROW
  EXECUTE FUNCTION notify_on_job_created();

-- ============================================================
-- 2. Job status changed → notify owner & cleaner
-- ============================================================

CREATE OR REPLACE FUNCTION notify_on_job_status_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Cleaner completed → notify owner
  IF NEW.assigned_member_id IS NOT NULL
     AND NEW.status = 'completed'
     AND OLD.status != 'completed' THEN
    INSERT INTO notifications (user_id, title, message, kind, job_id)
    VALUES (
      NEW.user_id,
      'Job Completed',
      NEW.assigned_member_name || ' finished ' || NEW.service_type || ' for ' || NEW.client_name || '.',
      'jobs',
      NEW.id
    );
  END IF;

  -- Owner started job → notify cleaner
  IF NEW.assigned_member_id IS NOT NULL
     AND NEW.status = 'inProgress'
     AND OLD.status = 'scheduled' THEN
    INSERT INTO notifications (user_id, title, message, kind, job_id)
    VALUES (
      NEW.assigned_member_id,
      'Job Started',
      NEW.service_type || ' for ' || NEW.client_name || ' is now in progress.',
      'jobs',
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_job_status_changed ON jobs;
CREATE TRIGGER on_job_status_changed
  AFTER UPDATE ON jobs
  FOR EACH ROW
  EXECUTE FUNCTION notify_on_job_status_changed();

-- ============================================================
-- 3. Invoice paid → notify owner (cleared payment)
-- ============================================================

CREATE OR REPLACE FUNCTION notify_on_invoice_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'paid' AND OLD.status != 'paid' THEN
    INSERT INTO notifications (user_id, title, message, kind, invoice_id)
    VALUES (
      NEW.user_id,
      'Payment Received',
      'Invoice ' || NEW.invoice_number || ' for ' || NEW.client_name || ' has been marked as paid.',
      'billing',
      NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_invoice_paid ON invoices;
CREATE TRIGGER on_invoice_paid
  AFTER UPDATE ON invoices
  FOR EACH ROW
  EXECUTE FUNCTION notify_on_invoice_paid();

-- ============================================================
-- 4. Client added → welcome notification
-- ============================================================

CREATE OR REPLACE FUNCTION notify_on_client_added()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications (user_id, title, message, kind)
  VALUES (
    NEW.user_id,
    'New Client Added',
    NEW.name || ' has been added to your clients. Schedule their first job!',
    'system'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_client_added ON clients;
CREATE TRIGGER on_client_added
  AFTER INSERT ON clients
  FOR EACH ROW
  EXECUTE FUNCTION notify_on_client_added();