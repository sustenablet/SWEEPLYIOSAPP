-- RPC called after inserting an invite to immediately link an existing auth user
CREATE OR REPLACE FUNCTION public.link_existing_cleaner(invite_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    UPDATE public.team_members tm
    SET    cleaner_user_id = u.id
    FROM   auth.users u
    WHERE  tm.id = invite_id
      AND  lower(tm.email) = lower(u.email)
      AND  tm.cleaner_user_id IS NULL;
END;
$$;
