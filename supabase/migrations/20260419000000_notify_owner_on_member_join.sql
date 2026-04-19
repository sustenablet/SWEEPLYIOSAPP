-- Notify owner with an in-app notification when a member accepts their team invite.
-- Uses SECURITY DEFINER so the trigger can insert into `notifications` for the owner
-- even though the cleaner's session (not the owner's) is the active auth context.

CREATE OR REPLACE FUNCTION notify_owner_on_member_join()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only fire when status transitions from 'invited' → 'active'
  IF OLD.status = 'invited' AND NEW.status = 'active' THEN
    INSERT INTO notifications (user_id, title, message, kind)
    VALUES (
      NEW.owner_id,
      'New Team Member',
      NEW.name || ' accepted your invite and joined your team as ' || NEW.role || '.',
      'team'
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Drop trigger first in case it already exists (idempotent)
DROP TRIGGER IF EXISTS on_member_join ON team_members;

CREATE TRIGGER on_member_join
  AFTER UPDATE ON team_members
  FOR EACH ROW
  EXECUTE FUNCTION notify_owner_on_member_join();
