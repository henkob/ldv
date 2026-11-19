create function ldv_private.zoo_guess_matches(p_guess text,p_first_name text,p_nickname text)
returns boolean language sql immutable set search_path to ''
as $$
  with guess as (select public.ldv_zoo_normalize(p_guess) as value)
  select exists (
    select 1 from guess, (values (public.ldv_zoo_normalize(p_first_name)),
                                  (public.ldv_zoo_normalize(p_nickname))) aliases(name)
    where name <> '' and (name = guess.value or (
      length(name) between 5 and 100 and abs(length(name)-length(guess.value)) <= 1
      and extensions.levenshtein_less_equal(left(name,100),left(guess.value,100),1) <= 1
    ))
  )
$$;
revoke all on function ldv_private.zoo_guess_matches(text,text,text)
from public, anon, authenticated;

create table ldv_private.zoo_test_weeks (
  id bigint generated always as identity primary key,
  starts_on date not null
);

create table ldv_private.zoo_test_answers (
  week_id bigint not null references ldv_private.zoo_test_weeks(id) on delete cascade,
  question_id bigint not null references public.ldv_zoo_questions(id) on delete cascade,
  admin_id uuid not null references auth.users(id) on delete cascade,
  correct boolean not null,
  primary key (week_id, admin_id, question_id)
);

alter table ldv_private.zoo_test_weeks enable row level security;
alter table ldv_private.zoo_test_answers enable row level security;
revoke all on ldv_private.zoo_test_weeks, ldv_private.zoo_test_answers
from public, anon, authenticated;

insert into ldv_private.zoo_test_weeks (starts_on) values (date '2026-11-23');

create function ldv_private.zoo_test_midnight(p_day date)
returns timestamptz language sql stable set search_path to ''
as $$
  select p_day::timestamp at time zone 'Europe/Stockholm'
$$;

create function ldv_private.zoo_require_test_admin()
returns void language plpgsql stable set search_path to ''
as $$
begin
  if auth.uid() is null or not public.ldv_is_admin() then
    raise exception 'Admin required' using errcode='42501';
  end if;
end
$$;

revoke all on function ldv_private.zoo_require_test_admin(), ldv_private.zoo_test_midnight(date)
from public, anon, authenticated;

create function public.ldv_zoo_schedule_test_week(p_starts_on date)
returns void language plpgsql security definer set search_path to ''
as $$
begin
  perform ldv_private.zoo_require_test_admin();

  if p_starts_on is null
    or p_starts_on < (now() at time zone 'Europe/Stockholm')::date
    or p_starts_on + 7 > date '2027-01-30' then
    raise exception 'Select a test week before departure' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(8272028);
  if p_starts_on is distinct from (
    select starts_on from ldv_private.zoo_test_weeks order by id desc limit 1
  ) then
    insert into ldv_private.zoo_test_weeks(starts_on) values(p_starts_on);
  end if;
end
$$;

create function public.ldv_zoo_test_week()
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare
  v_week ldv_private.zoo_test_weeks%rowtype;
  v_rounds jsonb;
  v_cutoff timestamptz;
  v_player uuid := auth.uid();
begin
  perform ldv_private.zoo_require_test_admin();
  select * into strict v_week from ldv_private.zoo_test_weeks order by id desc limit 1;
  v_cutoff := ldv_private.zoo_test_midnight(v_week.starts_on + 6);

  select coalesce(jsonb_agg(jsonb_build_object(
    'roundIndex', r.round_index,
    'unlockAt', schedule.opens_at,
    'isUnlocked', now() >= schedule.opens_at,
    'questions', case when now() >= schedule.opens_at then coalesce((
      select jsonb_agg(jsonb_build_object(
        'questionId', q.id,
        'answered', a.question_id is not null
      ) order by md5(v_player::text||':'||q.id::text))
      from public.ldv_zoo_questions q
      left join ldv_private.zoo_test_answers a on a.question_id=q.id
        and a.week_id=v_week.id and a.admin_id=v_player
      where q.round_id=r.id
    ), '[]'::jsonb) else '[]'::jsonb end
  ) order by r.round_index), '[]'::jsonb)
  into v_rounds
  from public.ldv_zoo_rounds r
  join public.trips t on t.id=r.trip_id and t.is_current and t.year=2027
  cross join lateral (
    select ldv_private.zoo_test_midnight(v_week.starts_on + r.round_index::integer) as opens_at
  ) schedule;

  return jsonb_build_object(
    'available', true,
    'testWeekId', v_week.id,
    'startsOn', v_week.starts_on,
    'endsOn', v_week.starts_on + 6,
    'earliestStart', (now() at time zone 'Europe/Stockholm')::date,
    'rounds', v_rounds,
    'finished', now() >= v_cutoff,
    'leaderboard', case when now() >= v_cutoff then (
      select coalesce(jsonb_agg(to_jsonb(scores) order by points desc, name),'[]'::jsonb)
      from (
        select coalesce(nullif(btrim(p.nickname),''),p.first_name,'Administratör') as name,
          count(*) filter (where a.correct) as points
        from ldv_private.zoo_test_answers a
        join auth.users u on u.id=a.admin_id
        left join lateral (
          select first_name,nickname from public.people
          where lower(btrim(email))=lower(btrim(u.email))
          order by id limit 1
        ) p on true
        where a.week_id=v_week.id
        group by a.admin_id, p.first_name, p.nickname
      ) scores
    ) end,
    'totalPoints', (select count(*) from ldv_private.zoo_test_answers a
      where a.week_id=v_week.id and a.admin_id=v_player and a.correct)
  );
end
$$;

create function public.ldv_zoo_submit_test_answer(
  p_week_id bigint, p_question_id bigint, p_guess text
)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_week ldv_private.zoo_test_weeks%rowtype;
  v_round smallint;
  v_first_name text;
  v_nickname text;
  v_correct boolean;
  v_player uuid := auth.uid();
begin
  perform ldv_private.zoo_require_test_admin();
  if p_guess is null or length(btrim(p_guess)) not between 1 and 100 then
    raise exception 'Invalid answer' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock_shared(8272028);
  select * into strict v_week from ldv_private.zoo_test_weeks order by id desc limit 1;
  if v_week.id is distinct from p_week_id then
    raise exception 'Test schedule changed' using errcode='22023';
  end if;

  select r.round_index,p.first_name,p.nickname into v_round,v_first_name,v_nickname
  from public.ldv_zoo_questions q
  join public.ldv_zoo_rounds r on r.id=q.round_id
  join public.trips t on t.id=r.trip_id and t.is_current and t.year=2027
  join public.people p on p.id=q.person_id
  where q.id=p_question_id;
  if not found
    or now() < ldv_private.zoo_test_midnight(v_week.starts_on + v_round::integer)
    or now() >= ldv_private.zoo_test_midnight(v_week.starts_on + 6) then
    raise exception 'Test round not available' using errcode='22023';
  end if;

  insert into ldv_private.zoo_test_answers(week_id,question_id,admin_id,correct)
  values(v_week.id,p_question_id,v_player,ldv_private.zoo_guess_matches(p_guess,v_first_name,v_nickname))
  on conflict (week_id,admin_id,question_id) do nothing;

  select a.correct into strict v_correct from ldv_private.zoo_test_answers a
  where a.week_id=v_week.id and a.question_id=p_question_id and a.admin_id=v_player;

  return jsonb_build_object('correct',v_correct,'first_name',v_first_name,
    'total_points',(select count(*) from ldv_private.zoo_test_answers a
      where a.week_id=v_week.id and a.admin_id=v_player and a.correct));
end
$$;

revoke all on function public.ldv_zoo_schedule_test_week(date), public.ldv_zoo_test_week(),
  public.ldv_zoo_submit_test_answer(bigint,bigint,text) from public, anon;
grant execute on function public.ldv_zoo_schedule_test_week(date), public.ldv_zoo_test_week(),
  public.ldv_zoo_submit_test_answer(bigint,bigint,text) to authenticated;

CREATE OR REPLACE FUNCTION public.ldv_zoo_submit_answer(p_question_id bigint, p_guess text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_player uuid; v_person public.people%rowtype; v_round public.ldv_zoo_rounds%rowtype; v_correct boolean; v_saved public.ldv_zoo_answers%rowtype; v_cutoff timestamptz;
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
 v_correct := ldv_private.zoo_guess_matches(p_guess,v_person.first_name,v_person.nickname);
 insert into public.ldv_zoo_answers(question_id,player_id,guess,correct) values(p_question_id,v_player,btrim(p_guess),v_correct) on conflict(question_id,player_id) do nothing returning * into v_saved;
 if v_saved.id is null then select * into v_saved from public.ldv_zoo_answers where question_id=p_question_id and player_id=v_player; end if;
 return jsonb_build_object('question_id',v_saved.question_id,'correct',v_saved.correct,'points',case when v_saved.correct then 1 else 0 end,'first_name',v_person.first_name,'submitted_at',v_saved.submitted_at,
  'total_points',(select count(*) from public.ldv_zoo_answers a
    join public.ldv_zoo_questions q on q.id=a.question_id
    join public.ldv_zoo_rounds r on r.id=q.round_id
    where a.player_id=v_player and a.correct and r.trip_id=v_round.trip_id));
end $function$;
