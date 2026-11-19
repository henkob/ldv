-- Continue the current admin test regardless of its former start date.
-- Retain earlier sessions and their answers. Keep date fields in the response
-- for already-loaded clients until they refresh to the unscheduled test.
revoke execute on function public.ldv_zoo_schedule_test_week(date) from authenticated;

create or replace function public.ldv_zoo_test_week()
returns jsonb language plpgsql stable security definer set search_path to ''
as $$
declare
  v_week ldv_private.zoo_test_weeks%rowtype;
  v_rounds jsonb;
  v_finished boolean;
  v_player uuid := auth.uid();
begin
  perform ldv_private.zoo_require_test_admin();
  select * into strict v_week from ldv_private.zoo_test_weeks order by id desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'roundIndex', r.round_index,
    'isUnlocked', true,
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'questionId', q.id,
        'answered', a.question_id is not null,
        'correct', a.correct
      ) order by md5(v_player::text||':'||q.id::text))
      from public.ldv_zoo_questions q
      left join ldv_private.zoo_test_answers a on a.question_id=q.id
        and a.week_id=v_week.id and a.admin_id=v_player
      where q.round_id=r.id
    ), '[]'::jsonb)
  ) order by r.round_index), '[]'::jsonb)
  into v_rounds
  from public.ldv_zoo_rounds r
  join public.trips t on t.id=r.trip_id and t.is_current and t.year=2027;

  v_finished := jsonb_array_length(v_rounds) = 6 and not exists (
    select 1
    from jsonb_array_elements(v_rounds) as round(data)
    cross join lateral jsonb_array_elements(round.data->'questions') as question(data)
    where question.data->>'answered' = 'false'
  );

  return jsonb_build_object(
    'available', true,
    'testWeekId', v_week.id,
    'startsOn', v_week.starts_on,
    'endsOn', v_week.starts_on + 6,
    'earliestStart', (now() at time zone 'Europe/Stockholm')::date,
    'rounds', v_rounds,
    'finished', v_finished,
    'leaderboard', case when v_finished then (
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

create or replace function public.ldv_zoo_submit_test_answer(
  p_week_id bigint, p_question_id bigint, p_guess text
)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_week ldv_private.zoo_test_weeks%rowtype;
  v_first_name text;
  v_nickname text;
  v_correct boolean;
  v_player uuid := auth.uid();
begin
  perform ldv_private.zoo_require_test_admin();
  if p_guess is null or length(btrim(p_guess)) not between 1 and 100 then
    raise exception 'Invalid answer' using errcode='22023';
  end if;

  select * into strict v_week from ldv_private.zoo_test_weeks order by id desc limit 1;
  if v_week.id is distinct from p_week_id then
    raise exception 'Test session changed' using errcode='22023';
  end if;

  select p.first_name,p.nickname into v_first_name,v_nickname
  from public.ldv_zoo_questions q
  join public.ldv_zoo_rounds r on r.id=q.round_id
  join public.trips t on t.id=r.trip_id and t.is_current and t.year=2027
  join public.people p on p.id=q.person_id
  where q.id=p_question_id;
  if not found then
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
