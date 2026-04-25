-- Add pay_day_of_week to team_members
-- Calendar weekday convention: 1=Sunday, 2=Monday, 3=Tuesday, 4=Wednesday, 5=Thursday, 6=Friday, 7=Saturday
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS pay_day_of_week smallint DEFAULT NULL;
