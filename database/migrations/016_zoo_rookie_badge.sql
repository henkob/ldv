-- Share only rookie status. When the count is missing, use the same
-- previous-trip history as the Who is Who participant list.
create function ldv_private.zoo_is_rookie(p_person_id uuid, p_previous_trip_count integer)
returns boolean language sql stable set search_path to ''
as $$
  select coalesce(p_previous_trip_count = 0, not exists (
    select 1 from public.trip_participation tp
    join public.trips t on t.id=tp.trip_id
    where tp.person_id=p_person_id
      and t.year < public.ldv_current_trip_year()
      and not (t.year=2021 and t.destination='Pandemiåret')
      and tp.status in ('confirmed','completed')
  ))
$$;

revoke all on function ldv_private.zoo_is_rookie(uuid,integer) from public, anon, authenticated;

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
       'rookie',ldv_private.zoo_is_rookie(p.id,p.previous_trip_count),
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
        'rookie', ldv_private.zoo_is_rookie(p.id,p.previous_trip_count),
        'answered', a.question_id is not null,
        'correct', a.correct
      ) order by md5(v_player::text||':'||q.id::text))
      from public.ldv_zoo_questions q
      join public.people p on p.id=q.person_id
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
