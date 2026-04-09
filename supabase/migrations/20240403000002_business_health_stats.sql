-- RPC to get business health statistics comparing current week to previous week.
-- Run this in your Supabase SQL Editor.

create or replace function public.get_business_health_stats(user_id_param uuid)
returns json as $$
declare
  curr_week_start timestamptz;
  last_week_start timestamptz;
  next_week_start timestamptz;
  
  curr_rev double precision;
  last_rev double precision;
  curr_count int;
  last_count int;
  
  rev_trend_val text;
  job_trend_val text;
begin
  -- Boundaries (Start of current week, start of last week, start of next week)
  curr_week_start := date_trunc('week', now()); -- Monday start by default in Postgres
  last_week_start := curr_week_start - interval '7 days';
  next_week_start := curr_week_start + interval '7 days';
  
  -- Current Week Stats
  select coalesce(sum(price), 0), count(*)
  into curr_rev, curr_count
  from public.jobs
  where user_id = user_id_param
    and status = 'completed'
    and scheduled_at >= curr_week_start
    and scheduled_at < next_week_start;
    
  -- Last Week Stats
  select coalesce(sum(price), 0), count(*)
  into last_rev, last_count
  from public.jobs
  where user_id = user_id_param
    and status = 'completed'
    and scheduled_at >= last_week_start
    and scheduled_at < curr_week_start;
    
  -- Calculate Revenue Trend (%)
  if last_rev = 0 then
    if curr_rev > 0 then rev_trend_val := '+100%'; else rev_trend_val := '0%'; end if;
  else
    rev_trend_val := round(((curr_rev - last_rev) / last_rev * 100)::numeric, 0)::text || '%';
    if (curr_rev - last_rev) >= 0 then rev_trend_val := '+' || rev_trend_val; end if;
  end if;
  
  -- Calculate Job Trend (%)
  if last_count = 0 then
    if curr_count > 0 then job_trend_val := '+100%'; else job_trend_val := '0%'; end if;
  else
    job_trend_val := round(((curr_count - last_count)::numeric / last_count * 100)::numeric, 0)::text || '%';
    if (curr_count - last_count) >= 0 then job_trend_val := '+' || job_trend_val; end if;
  end if;
  
  return json_build_object(
    'revenue', curr_rev,
    'revenue_trend', rev_trend_val,
    'job_count', curr_count,
    'job_trend', job_trend_val,
    'is_rev_positive', (curr_rev >= last_rev),
    'is_job_positive', (curr_count >= last_count)
  );
end;
$$ language plpgsql security definer;
