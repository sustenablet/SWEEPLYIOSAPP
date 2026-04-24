-- Force PostgREST schema cache refresh by creating and dropping a dummy function
CREATE OR REPLACE FUNCTION public._force_schema_refresh()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- This function's existence forces PostgREST to refresh its schema cache
  -- The columns already exist; this just triggers a refresh
  PERFORM 1 FROM information_schema.columns WHERE table_name = 'invoices' AND column_name = 'paid_amount';
END;
$$;

-- Call it
SELECT public._force_schema_refresh();

-- Drop it immediately after
DROP FUNCTION IF EXISTS public._force_schema_refresh();