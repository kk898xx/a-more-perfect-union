-- ============================================================
-- "A More Perfect Union" — Supabase schema
-- Project: uiicjupdfdrjihcpnnuj
--
-- This file documents what has already been applied to the live
-- database via the Supabase MCP (migration: rebuild_amore_perfect_union_schema).
-- It's kept here for reference / version control — re-running it
-- is safe (it drops and recreates laws/submissions from scratch).
-- ============================================================

-- 1. DROP OLD / INCOMPATIBLE OBJECTS -----------------------------
drop function if exists increment_vote(bigint, boolean);
drop function if exists increment_vote(uuid, boolean);
drop function if exists increment_free_vote(bigint);
drop function if exists increment_free_vote(uuid);
drop table if exists visitors cascade;
drop table if exists laws cascade;
drop table if exists submissions cascade;

-- 2. TABLES -------------------------------------------------------

create table laws (
  id bigint generated always as identity primary key,
  text text not null,
  source text not null default 'submitted',
  free_votes bigint not null default 0,
  paid_votes bigint not null default 0,
  approved boolean not null default true,
  secured boolean not null default false,
  created_at timestamptz not null default now()
);

create table submissions (
  id bigint generated always as identity primary key,
  text text not null,
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

-- 3. ROW LEVEL SECURITY ---------------------------------------------
-- Anon-key-only app (no login). Policies are scoped to exactly what
-- the client does: read approved laws, insert a secured ($10) law
-- directly, insert a submission ($1) for moderation. Vote counts can
-- only change through the increment_free_vote() function below —
-- there is no direct UPDATE policy on laws for anon.

alter table laws enable row level security;
alter table submissions enable row level security;

grant select, insert on laws to anon, authenticated;
grant insert on submissions to anon, authenticated;

create policy "public read approved laws" on laws
  for select using (approved = true);

create policy "public insert secured laws" on laws
  for insert with check (secured = true and approved = true);

create policy "public insert submissions" on submissions
  for insert with check (true);

-- 4. VOTE COUNTER (atomic, avoids race conditions on concurrent swipes) --

create or replace function increment_free_vote(law_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update laws set free_votes = free_votes + 1 where id = law_id and approved = true;
end;
$$;

grant execute on function increment_free_vote(bigint) to anon, authenticated;

-- 5. REALTIME -------------------------------------------------------
-- Lets the leaderboard (and results screen, while open) update live
-- as people swipe, without a page refresh.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'laws'
  ) then
    alter publication supabase_realtime add table laws;
  end if;
end $$;

-- 6. SEED DATA (source = "manifesto") --------------------------------

insert into laws (text, source, approved) values
('Everything must be beautiful', 'manifesto', true),
('Live by the sun, honor the moon', 'manifesto', true),
('New year begins in spring', 'manifesto', true),
('Artists receive subsidized housing if they teach or contribute to their community', 'manifesto', true),
('AI takes over infrastructure and administrative jobs', 'manifesto', true),
('Every person has the right to one acre of farmable land if they maintain it', 'manifesto', true),
('Native Americans own their land outright instead of leasing from the federal government', 'manifesto', true),
('Decriminalize psychedelic medicines and resource the traditions they come from', 'manifesto', true),
('Social media algorithms must prioritize quality of information over time spent', 'manifesto', true),
('Protect prairie land and let people lay in meadows', 'manifesto', true),
('Farmers are incentivized to prioritize soil quality over yield', 'manifesto', true),
('All dogs go to heaven', 'manifesto', true),
('They must invent cigarettes that are good for you', 'manifesto', true),
('The military budget is cut in half and redirected to education and housing', 'manifesto', true),
('Voting is mandatory', 'manifesto', true),
('Billionaires do not exist', 'manifesto', true),
('No one may own more than three properties', 'manifesto', true),
('Prisons are abolished within 20 years', 'manifesto', true),
('The work week is four days', 'manifesto', true),
('Healthcare is free and funded by a wealth tax', 'manifesto', true),
('College debt is cancelled and higher education is free', 'manifesto', true),
('Every town must have a dance floor', 'manifesto', true),
('Silence is a protected right', 'manifesto', true),
('Beauty sleep is federally mandated', 'manifesto', true),
('Fast food is a controlled substance', 'manifesto', true),
('Every public building must have a garden', 'manifesto', true),
('Corporations are not people', 'manifesto', true),
('The news must be true', 'manifesto', true);

-- ============================================================
-- Done. The app (index.html) reads/writes this schema directly
-- using the Supabase anon key — no server needed.
--
-- Manual step still required in Stripe: set each Payment Link's
-- post-payment redirect to this site's URL with the matching
-- query param —
--   $1 link  -> https://<your-deployed-site>/?action=submit
--   $10 link -> https://<your-deployed-site>/?action=secure
-- ============================================================
