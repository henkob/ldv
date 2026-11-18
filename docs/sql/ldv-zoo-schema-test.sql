-- Schema foundation applied to LDV-TEST ONLY (wtrrdxurgxyvfahhgbsh).
-- Official assignments and scoring functions must be implemented and reviewed before app integration.
create table if not exists public.ldv_zoo_rounds (
 id bigint generated always as identity primary key,
 trip_id bigint not null references public.trips(id) on delete cascade,
 round_index smallint not null check (round_index between 0 and 5),
 unlock_at timestamptz,
 unique(trip_id,round_index)
);
create table if not exists public.ldv_zoo_questions (
 id bigint generated always as identity primary key,
 round_id bigint not null references public.ldv_zoo_rounds(id) on delete cascade,
 position smallint not null check(position between 1 and 14),
 person_id uuid not null references public.people(id),
 unique(round_id,position),unique(round_id,person_id)
);
create table if not exists public.ldv_zoo_answers (
 id bigint generated always as identity primary key,
 question_id bigint not null references public.ldv_zoo_questions(id) on delete cascade,
 player_id uuid not null references public.people(id),
 guess text not null check(length(guess) between 1 and 100),
 correct boolean not null,
 submitted_at timestamptz not null default now(),
 unique(question_id,player_id)
);
create index if not exists ldv_zoo_answers_player_idx on public.ldv_zoo_answers(player_id);
alter table public.ldv_zoo_rounds enable row level security;
alter table public.ldv_zoo_questions enable row level security;
alter table public.ldv_zoo_answers enable row level security;
revoke all on public.ldv_zoo_rounds,public.ldv_zoo_questions,public.ldv_zoo_answers from anon,authenticated;
grant select on public.ldv_zoo_answers to authenticated;
drop policy if exists ldv_zoo_answers_own_read on public.ldv_zoo_answers;
create policy ldv_zoo_answers_own_read on public.ldv_zoo_answers
 for select to authenticated
 using (auth.uid() is not null and player_id=public.ldv_my_person_id() and public.ldv_is_participant());
