-- Zoo quiz for St. Anton 2027. Existing portraits stay private.
create table public.ldv_zoo_rounds (
 id bigint generated always as identity primary key,
 trip_id bigint not null references public.trips(id) on delete cascade,
 round_index smallint not null check (round_index between 0 and 5),
 unlock_at timestamptz not null,
 unique(trip_id,round_index)
);
create table public.ldv_zoo_questions (
 id bigint generated always as identity primary key,
 round_id bigint not null references public.ldv_zoo_rounds(id) on delete cascade,
 position smallint not null check(position between 1 and 14),
 person_id uuid not null references public.people(id) on delete cascade,
 unique(round_id,position),unique(round_id,person_id)
);
create table public.ldv_zoo_answers (
 id bigint generated always as identity primary key,
 question_id bigint not null references public.ldv_zoo_questions(id) on delete cascade,
 player_id uuid not null references public.people(id) on delete cascade,
 guess text not null check(length(guess) between 1 and 100),
 correct boolean not null,
 submitted_at timestamptz not null default now(),
 unique(question_id,player_id)
);
create index ldv_zoo_answers_player_idx on public.ldv_zoo_answers(player_id);
alter table public.ldv_zoo_rounds enable row level security;
alter table public.ldv_zoo_questions enable row level security;
alter table public.ldv_zoo_answers enable row level security;
revoke all on public.ldv_zoo_rounds,public.ldv_zoo_questions,public.ldv_zoo_answers from anon,authenticated;

create function ldv_private.zoo_is_open()
returns boolean language sql stable set search_path to ''
as $$
  select auth.uid() is not null
    and now() >= (timestamp '2027-01-30 00:00' at time zone 'Europe/Stockholm')
    and exists (
      select 1 from public.app_access_settings s
      join public.trips t on t.id=s.active_trip_id
      where s.is_open and t.is_current and t.year=2027
    )
$$;

create function ldv_private.zoo_cutoff()
returns timestamptz language sql immutable set search_path to ''
as $$
  select timestamp '2027-02-05 00:00' at time zone 'Europe/Stockholm'
$$;
revoke all on function ldv_private.zoo_is_open(), ldv_private.zoo_cutoff()
from public, anon, authenticated;

create function public.ldv_zoo_can_view_question(p_question_id bigint)
returns boolean language sql stable security definer set search_path to ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.ldv_zoo_questions q
    join public.ldv_zoo_rounds r on r.id=q.round_id
    join public.trips t on t.id=r.trip_id
    where q.id=p_question_id and t.is_current and t.year=2027
    and (
      (not ldv_private.zoo_is_open() and public.ldv_is_admin())
      or (
        ldv_private.zoo_is_open() and now()>=r.unlock_at
        and exists (
          select 1 from public.trip_participation tp
          where tp.trip_id=t.id and tp.person_id=public.ldv_my_person_id()
            and tp.status='confirmed'
        )
      )
    )
  )
$$;
revoke all on function public.ldv_zoo_can_view_question(bigint) from public, anon;
grant execute on function public.ldv_zoo_can_view_question(bigint) to authenticated;

create function public.ldv_zoo_portrait_source(p_question_id bigint)
returns text language sql stable security invoker set search_path to ''
as $$
  select o.name from public.ldv_zoo_questions q
  join storage.objects o on o.bucket_id='ldv-avatars'
    and o.name in (q.person_id::text||'/avatar',q.person_id::text||'/avatar-full')
  where q.id=p_question_id
    and o.metadata->>'mimetype' in ('image/jpeg','image/png')
  order by (o.name=q.person_id::text||'/avatar') desc
  limit 1
$$;
revoke all on function public.ldv_zoo_portrait_source(bigint) from public, anon, authenticated;
grant execute on function public.ldv_zoo_portrait_source(bigint) to service_role;
grant select on public.ldv_zoo_questions to service_role;
CREATE OR REPLACE FUNCTION public.ldv_zoo_my_rounds()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_player uuid;
 v_trip bigint;
 v_preview boolean;
 v_cutoff timestamptz;
 v_result jsonb;
begin
 v_preview := auth.uid() is not null and public.ldv_is_admin()
   and not ldv_private.zoo_is_open();
 if not v_preview and not ldv_private.zoo_is_open() then
   return jsonb_build_object('available',false,'rounds','[]'::jsonb);
 end if;
 v_player := public.ldv_my_person_id();
 select t.id into v_trip
 from public.trips t
 where t.is_current and t.year=2027
   and exists(select 1 from public.ldv_zoo_rounds r where r.trip_id=t.id)
   and (v_preview or exists(
     select 1 from public.trip_participation tp where tp.trip_id=t.id
     and tp.person_id=v_player and tp.status='confirmed'
   ))
 limit 1;
 if v_trip is null then
   return jsonb_build_object('available',false,'rounds','[]'::jsonb);
 end if;
 v_cutoff := ldv_private.zoo_cutoff();
 select coalesce(jsonb_agg(jsonb_build_object(
   'roundIndex',r.round_index,
   'unlockAt',r.unlock_at,
   'isUnlocked',(v_preview or now()>=r.unlock_at),
   'questions',case when (v_preview or now()>=r.unlock_at)
     then coalesce((select jsonb_agg(jsonb_build_object(
       'questionId',q.id,
       'answered',a.id is not null,
       'correct',case when a.id is not null then a.correct else null end,
       'points',case when a.id is not null then (case when a.correct then 1 else 0 end) else null end,
       'firstName',case when a.id is not null then p.first_name end,
       'answeredAt',a.submitted_at
     ) order by md5(coalesce(v_player,auth.uid())::text||':'||q.id::text))
     from public.ldv_zoo_questions q
     join public.people p on p.id=q.person_id
     left join public.ldv_zoo_answers a on a.question_id=q.id and a.player_id=v_player
     where q.round_id=r.id),'[]'::jsonb)
     else '[]'::jsonb end
 ) order by r.round_index),'[]'::jsonb) into v_result
 from public.ldv_zoo_rounds r where r.trip_id=v_trip;
 return jsonb_build_object('available',true,'preview',v_preview,'tripId',v_trip,'rounds',v_result,
   'cutoffAt',v_cutoff,
   'finished',v_cutoff is not null and now()>=v_cutoff,
   'leaderboard',case when now()>=v_cutoff then (
     select coalesce(jsonb_agg(to_jsonb(scores) order by points desc, name),'[]'::jsonb)
     from (
       select coalesce(nullif(btrim(p.nickname),''),p.first_name) as name,
         count(*) filter (where a.correct) as points
       from public.ldv_zoo_answers a
       join public.people p on p.id=a.player_id
       join public.ldv_zoo_questions q on q.id=a.question_id
       join public.ldv_zoo_rounds r on r.id=q.round_id and r.trip_id=v_trip
       group by p.id
     ) scores
   ) end,
   'totalPoints',(select count(*) from public.ldv_zoo_answers a
      join public.ldv_zoo_questions q on q.id=a.question_id
      join public.ldv_zoo_rounds r on r.id=q.round_id
      where a.player_id=v_player and a.correct=true and r.trip_id=v_trip));
end $function$;

revoke all on function public.ldv_zoo_my_rounds() from public,anon;
grant execute on function public.ldv_zoo_my_rounds() to authenticated;

create extension if not exists fuzzystrmatch with schema extensions;

create or replace function public.ldv_zoo_normalize(p_guess text)
returns text language sql immutable strict set search_path to ''
as $$
  select regexp_replace(
    regexp_replace(lower(normalize(p_guess, NFKD)), U&'[\0300-\036F]', '', 'g'),
    '[[:space:]‐‑-]+', '', 'g')
$$;

CREATE OR REPLACE FUNCTION public.ldv_zoo_submit_answer(p_question_id bigint, p_guess text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_player uuid; v_person public.people%rowtype; v_round public.ldv_zoo_rounds%rowtype; v_correct boolean; v_saved public.ldv_zoo_answers%rowtype; v_cutoff timestamptz; v_guess text;
begin
 if not ldv_private.zoo_is_open() then raise exception 'Not an authorized participant' using errcode='42501'; end if;
 v_player:=public.ldv_my_person_id();
 if v_player is null or not public.ldv_is_participant() then
   raise exception 'Not an authorized participant' using errcode='42501';
 end if;
 if p_guess is null or length(btrim(p_guess)) not between 1 and 100 then raise exception 'Invalid answer'; end if;
 select p.* into v_person from public.ldv_zoo_questions q join public.people p on p.id=q.person_id where q.id=p_question_id;
 if not found then raise exception 'Question not found'; end if;
 select r.* into v_round from public.ldv_zoo_questions q join public.ldv_zoo_rounds r on r.id=q.round_id where q.id=p_question_id;
 v_cutoff := ldv_private.zoo_cutoff();
 if v_round.unlock_at is null or v_cutoff is null or now()<v_round.unlock_at or now()>=v_cutoff then raise exception 'Round not available'; end if;
 if not exists(select 1 from public.trip_participation tp join public.trips t on t.id=tp.trip_id where tp.person_id=v_player and tp.trip_id=v_round.trip_id and tp.status='confirmed' and t.is_current and t.year=2027) then raise exception 'Not a participant in this trip' using errcode='42501'; end if;
 v_guess:=public.ldv_zoo_normalize(p_guess);
 select exists (
   select from (values (public.ldv_zoo_normalize(v_person.first_name)),
                       (public.ldv_zoo_normalize(v_person.nickname))) aliases(name)
   where name<>'' and (name=v_guess or (
     length(name) between 5 and 100 and abs(length(name)-length(v_guess))<=1
     and extensions.levenshtein_less_equal(left(name,100),left(v_guess,100),1)<=1))
 ) into v_correct;
 insert into public.ldv_zoo_answers(question_id,player_id,guess,correct) values(p_question_id,v_player,btrim(p_guess),v_correct) on conflict(question_id,player_id) do nothing returning * into v_saved;
 if v_saved.id is null then select * into v_saved from public.ldv_zoo_answers where question_id=p_question_id and player_id=v_player; end if;
 return jsonb_build_object('question_id',v_saved.question_id,'correct',v_saved.correct,'points',case when v_saved.correct then 1 else 0 end,'first_name',v_person.first_name,'submitted_at',v_saved.submitted_at,
  'total_points',(select count(*) from public.ldv_zoo_answers a
    join public.ldv_zoo_questions q on q.id=a.question_id
    join public.ldv_zoo_rounds r on r.id=q.round_id
    where a.player_id=v_player and a.correct and r.trip_id=v_round.trip_id));
end $function$;

revoke all on function public.ldv_zoo_submit_answer(bigint,text) from public,anon;
grant execute on function public.ldv_zoo_submit_answer(bigint,text) to authenticated;

-- Select the confirmed St. Anton participants with supported portraits. Cycle
-- only after using the full pool, so repeats always fall in different rounds.
do $$
declare
  trip bigint;
  portraits uuid[];
  round_id bigint;
  round_number integer;
begin
  select id into strict trip from public.trips where is_current and year=2027;
  select array_agg(id order by md5('zoo-st-anton-2027:'||id::text)) into portraits
  from (
    select distinct p.id
    from public.people p join public.trip_participation tp on tp.person_id=p.id
    where tp.trip_id=trip and tp.status='confirmed' and nullif(btrim(p.first_name),'') is not null
      and exists (
        select 1 from storage.objects o
        where o.bucket_id='ldv-avatars'
          and o.name in (p.id::text||'/avatar',p.id::text||'/avatar-full')
          and o.metadata->>'mimetype' in ('image/jpeg','image/png')
      )
  ) eligible;
  if coalesce(cardinality(portraits),0)<14 then
    raise exception 'Zoo requires at least 14 distinct portraits';
  end if;

  for round_number in 0..5 loop
    insert into public.ldv_zoo_rounds(trip_id,round_index,unlock_at)
    values(trip,round_number,(date '2027-01-30'+round_number)::timestamp at time zone 'Europe/Stockholm')
    returning id into round_id;

    insert into public.ldv_zoo_questions(round_id,position,person_id)
    select round_id,position,portraits[1+((round_number*14+position-1)%cardinality(portraits))]
    from generate_series(1,14) as slots(position);
  end loop;
end
$$;
