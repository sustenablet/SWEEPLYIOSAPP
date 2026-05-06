-- Add per-service pay rates to team members.
-- Maps ServiceType.rawValue → dollar amount (e.g. {"Standard Clean": 45, "Deep Clean": 65}).
-- Only used when pay_rate_type = 'per_job'.

ALTER TABLE team_members
  ADD COLUMN IF NOT EXISTS service_rates jsonb DEFAULT '{}';
