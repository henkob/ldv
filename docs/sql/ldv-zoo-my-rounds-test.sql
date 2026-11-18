-- LDV test only. Read-only player API. Requires authenticated confirmed participant.
CREATE OR REPLACE FUNCTION public.ldv_zoo_my_rounds()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_player uuid;
 v_trip bigint;
 v_start timestamptz;
 v_cutoff timestamptz;
 v_result jsonb;
begin
 if auth.uid() is null or not public.ldv_is_participant() then
   raise exception 'Not an authorized participant' using errcode='42501';
 end if;
 v_player := public.ldv_my_person_id();
 if v_player is null then raise exception 'Participant profile missing' using errcode='42501'; end if;
 select t.id into v_trip
 from public.trips t
 join public.trip_participation tp on tp.trip_id=t.id
 where t.is_current=true and tp.person_id=v_player and tp.status='confirmed'
 limit 1;
 if v_trip is null then raise exception 'Not a confirmed trip participant' using errcode='42501'; end if;
 select max(r.unlock_at) into v_start
 from public.ldv_zoo_rounds r where r.trip_id=v_trip;
 v_cutoff:=((v_start at time zone 'Europe/Stockholm') + interval '1 day') at time zone 'Europe/Stockholm';
 select coalesce(jsonb_agg(jsonb_build_object(
   'roundIndex',r.round_index,
   'unlockAt',r.unlock_at,
   'isUnlocked',(r.unlock_at is not null and now()>=r.unlock_at),
   'questions',case when r.unlock_at is not null and now()>=r.unlock_at
     then coalesce((select jsonb_agg(jsonb_build_object(
       'questionId',q.id,
       'photoPath',z.photo_path,
       'answered',a.id is not null,
       'correct',case when a.id is not null then a.correct else null end,
       'points',case when a.id is not null then (case when a.correct then 1 else 0 end) else null end,
       'firstName',case when a.id is not null then p.first_name end,
       'answeredAt',a.submitted_at
     ) order by md5(v_player::text||':'||q.id::text))
     from public.ldv_zoo_questions q
     join public.people p on p.id=q.person_id
     join public.ldv_zoo_portraits z on z.person_id=q.person_id
     left join public.ldv_zoo_answers a on a.question_id=q.id and a.player_id=v_player
     where q.round_id=r.id),'[]'::jsonb)
     else '[]'::jsonb end
 ) order by r.round_index),'[]'::jsonb) into v_result
 from public.ldv_zoo_rounds r where r.trip_id=v_trip;
 return jsonb_build_object('tripId',v_trip,'rounds',v_result,
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
