-- Add settings_json to profiles table to store business address, catalogs, and app defaults.
alter table public.profiles add column if not exists settings_json text;
