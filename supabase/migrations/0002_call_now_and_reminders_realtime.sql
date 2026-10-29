-- A "Call now" moves the next pending call to the present; this remembers which scheduled
-- time it stood in for, so the app and the API can tell that slot has already been called.
alter table public.call_occurrences add column called_early_for timestamptz;
create index call_occurrences_called_early_idx
  on public.call_occurrences (reminder_id, called_early_for) where called_early_for is not null;

-- Reminders added or removed on one phone now reach the other tabs and the parent's phone live.
alter publication supabase_realtime add table public.reminders;
