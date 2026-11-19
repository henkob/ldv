-- Share only the first letter, using the same access rules as the portrait.
create function public.ldv_zoo_first_letter_hint(p_question_id bigint)
returns text language sql stable security definer set search_path to ''
as $$
  select upper(substring(normalize(p.first_name, NFC) from '[[:alpha:]]'))
  from public.ldv_zoo_questions q
  join public.people p on p.id=q.person_id
  where q.id=p_question_id
    and public.ldv_zoo_can_view_question(q.id)
    and (not ldv_private.zoo_is_open() or now()<ldv_private.zoo_cutoff())
$$;

revoke all on function public.ldv_zoo_first_letter_hint(bigint) from public, anon;
grant execute on function public.ldv_zoo_first_letter_hint(bigint) to authenticated;
