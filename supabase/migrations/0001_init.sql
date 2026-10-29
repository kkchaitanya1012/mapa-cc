-- Mapa foundations: schema, row-level security, and the two atomic operations
-- the server relies on (redeem a pairing code, claim due calls).
--
-- Access model: the Flutter apps talk to Supabase as the signed-in user and are
-- limited by RLS below. The Python service connects with the database owner
-- role (DATABASE_URL), which bypasses RLS, and performs every privileged write.

-- ---------------------------------------------------------------- enums

create type public.user_role as enum ('caretaker', 'recipient');
create type public.voice_lang as enum ('en', 'te');
create type public.person_tone as enum ('peach', 'mint', 'butter', 'lilac');
create type public.occurrence_status as enum
  ('pending', 'ringing', 'in_call', 'completed', 'no_answer', 'failed');
create type public.medicine_status as enum
  ('taken', 'not_taken', 'will_take_later', 'unclear');
create type public.wellbeing as enum ('good', 'okay', 'unwell');
create type public.alert_kind as enum ('missed_dose', 'no_answer', 'unwell');

-- ---------------------------------------------------------------- tables

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  role            public.user_role not null,
  display_name    text not null default '',
  language        public.voice_lang not null default 'en',
  timezone        text not null default 'Asia/Kolkata',
  fcm_token       text,
  onboarding_done boolean not null default false,
  created_at      timestamptz not null default now()
);

create table public.pairing_codes (
  code            text primary key check (code ~ '^[0-9]{6}$'),
  caretaker_id    uuid not null references public.profiles (id) on delete cascade,
  recipient_label text not null check (char_length(recipient_label) between 1 and 40),
  expires_at      timestamptz not null default now() + interval '15 minutes',
  used_at         timestamptz,
  used_by         uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now()
);
create index pairing_codes_caretaker_idx on public.pairing_codes (caretaker_id);

create table public.care_links (
  id            uuid primary key default gen_random_uuid(),
  caretaker_id  uuid not null references public.profiles (id) on delete cascade,
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  nickname      text not null check (char_length(nickname) between 1 and 40),
  tone          public.person_tone not null,
  created_at    timestamptz not null default now(),
  unique (caretaker_id, recipient_id),
  check (caretaker_id <> recipient_id)
);
create index care_links_recipient_idx on public.care_links (recipient_id);

create table public.reminders (
  id            uuid primary key default gen_random_uuid(),
  link_id       uuid not null references public.care_links (id) on delete cascade,
  medicine      text not null check (char_length(medicine) between 1 and 80),
  dose          text check (char_length(dose) <= 80),
  instructions  text check (char_length(instructions) <= 200),
  time_of_day   time not null,
  -- bit 0 = Monday ... bit 6 = Sunday (matches Python's date.weekday())
  days_mask     smallint not null default 127 check (days_mask between 1 and 127),
  start_date    date not null,
  end_date      date check (end_date is null or end_date >= start_date),
  active        boolean not null default true,
  source        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index reminders_link_idx on public.reminders (link_id) where active;

create table public.call_occurrences (
  id            uuid primary key default gen_random_uuid(),
  reminder_id   uuid not null references public.reminders (id) on delete cascade,
  scheduled_at  timestamptz not null,
  status        public.occurrence_status not null default 'pending',
  attempt       smallint not null default 1 check (attempt between 1 and 3),
  room_name     text,
  started_at    timestamptz,
  ended_at      timestamptz,
  created_at    timestamptz not null default now(),
  unique (reminder_id, scheduled_at, attempt)
);
create index call_occurrences_due_idx
  on public.call_occurrences (scheduled_at) where status = 'pending';

create table public.call_results (
  occurrence_id   uuid primary key references public.call_occurrences (id) on delete cascade,
  medicine_status public.medicine_status not null,
  wellbeing       public.wellbeing,
  note            text,
  transcript      jsonb not null default '[]'::jsonb,
  duration_s      integer,
  created_at      timestamptz not null default now()
);

create table public.alerts (
  id            uuid primary key default gen_random_uuid(),
  caretaker_id  uuid not null references public.profiles (id) on delete cascade,
  link_id       uuid not null references public.care_links (id) on delete cascade,
  occurrence_id uuid references public.call_occurrences (id) on delete set null,
  kind          public.alert_kind not null,
  message       text not null,
  seen_at       timestamptz,
  created_at    timestamptz not null default now()
);
create index alerts_caretaker_idx on public.alerts (caretaker_id, created_at desc);

-- ---------------------------------------------------------------- RLS helpers
-- security definer so policies can look across tables without recursing into RLS

create function public.is_caretaker_of(p_link uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from care_links where id = p_link and caretaker_id = auth.uid());
$$;

create function public.is_recipient_of(p_link uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from care_links where id = p_link and recipient_id = auth.uid());
$$;

create function public.is_linked_to(p_profile uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from care_links
    where (caretaker_id = auth.uid() and recipient_id = p_profile)
       or (recipient_id = auth.uid() and caretaker_id = p_profile)
  );
$$;

-- ---------------------------------------------------------------- RLS

alter table public.profiles         enable row level security;
alter table public.pairing_codes    enable row level security;
alter table public.care_links       enable row level security;
alter table public.reminders        enable row level security;
alter table public.call_occurrences enable row level security;
alter table public.call_results     enable row level security;
alter table public.alerts           enable row level security;

-- profiles: your own row, plus the people you're linked to (read only)
create policy profiles_select on public.profiles
  for select using (id = auth.uid() or public.is_linked_to(id));
create policy profiles_insert on public.profiles
  for insert with check (id = auth.uid());
create policy profiles_update on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- pairing codes: caretakers can see their own; creating and redeeming go through the server
create policy pairing_codes_select on public.pairing_codes
  for select using (caretaker_id = auth.uid());

-- links: both sides can read; the caretaker can rename or unpair
create policy care_links_select on public.care_links
  for select using (caretaker_id = auth.uid() or recipient_id = auth.uid());
create policy care_links_update on public.care_links
  for update using (caretaker_id = auth.uid()) with check (caretaker_id = auth.uid());
create policy care_links_delete on public.care_links
  for delete using (caretaker_id = auth.uid());

-- reminders: the caretaker manages them; the recipient can read theirs
create policy reminders_select on public.reminders
  for select using (public.is_caretaker_of(link_id) or public.is_recipient_of(link_id));
create policy reminders_insert on public.reminders
  for insert with check (public.is_caretaker_of(link_id));
create policy reminders_update on public.reminders
  for update using (public.is_caretaker_of(link_id)) with check (public.is_caretaker_of(link_id));
create policy reminders_delete on public.reminders
  for delete using (public.is_caretaker_of(link_id));

-- occurrences and results: read only for both sides; the server writes them
create policy call_occurrences_select on public.call_occurrences
  for select using (exists (
    select 1 from public.reminders r
    where r.id = reminder_id
      and (public.is_caretaker_of(r.link_id) or public.is_recipient_of(r.link_id))
  ));

create policy call_results_select on public.call_results
  for select using (exists (
    select 1 from public.call_occurrences o
    join public.reminders r on r.id = o.reminder_id
    where o.id = occurrence_id
      and (public.is_caretaker_of(r.link_id) or public.is_recipient_of(r.link_id))
  ));

-- alerts: caretaker only; they may mark them seen
create policy alerts_select on public.alerts
  for select using (caretaker_id = auth.uid());
create policy alerts_update on public.alerts
  for update using (caretaker_id = auth.uid()) with check (caretaker_id = auth.uid());

-- ---------------------------------------------------------------- operations

-- Redeem a pairing code atomically. Locks the code row so two phones can't
-- both claim it. Picks the caretaker's least-used phone colour for the new link.
create function public.redeem_pairing_code(p_code text, p_recipient uuid)
returns public.care_links
language plpgsql security definer set search_path = public as $$
declare
  v_code  public.pairing_codes;
  v_tone  public.person_tone;
  v_link  public.care_links;
begin
  select * into v_code from pairing_codes where code = p_code for update;
  if not found then raise exception 'invalid_code'; end if;
  if v_code.used_at is not null then raise exception 'code_used'; end if;
  if v_code.expires_at < now() then raise exception 'code_expired'; end if;
  if v_code.caretaker_id = p_recipient then raise exception 'self_pair'; end if;

  select t.tone into v_tone
  from unnest(enum_range(null::person_tone)) with ordinality as t(tone, ord)
  order by (select count(*) from care_links l
            where l.caretaker_id = v_code.caretaker_id and l.tone = t.tone), t.ord
  limit 1;

  update pairing_codes set used_at = now(), used_by = p_recipient where code = p_code;

  insert into care_links (caretaker_id, recipient_id, nickname, tone)
  values (v_code.caretaker_id, p_recipient, v_code.recipient_label, v_tone)
  on conflict (caretaker_id, recipient_id)
    do update set nickname = excluded.nickname
  returning * into v_link;

  return v_link;
end $$;

-- Claim due calls for dispatch. SKIP LOCKED makes this safe with more than one
-- scheduler running, and a restart can't double-dial.
create function public.claim_due_occurrences(p_limit integer default 20)
returns setof public.call_occurrences
language sql security definer set search_path = public as $$
  update call_occurrences o
     set status = 'ringing', started_at = now()
   where o.id in (
     select id from call_occurrences
      where status = 'pending' and scheduled_at <= now()
      order by scheduled_at
      limit p_limit
      for update skip locked)
  returning o.*;
$$;

revoke all on function public.redeem_pairing_code(text, uuid) from public, anon, authenticated;
revoke all on function public.claim_due_occurrences(integer) from public, anon, authenticated;

-- ---------------------------------------------------------------- realtime
-- The caretaker app listens for new links, call progress, results and alerts.

alter publication supabase_realtime add table
  public.care_links, public.call_occurrences, public.call_results, public.alerts;
