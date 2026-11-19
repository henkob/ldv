-- Each group contains equivalent spellings, normalized like player guesses.
-- Variants match exactly after normalization. The existing one-edit rule
-- applies to the registered name and nickname.
create or replace function ldv_private.zoo_guess_matches(
  p_guess text, p_first_name text, p_nickname text
)
returns boolean language sql immutable set search_path to ''
as $$
  with guess as (
    select public.ldv_zoo_normalize(p_guess) as value
  ), names(value) as (
    values (public.ldv_zoo_normalize(p_first_name)),
           (public.ldv_zoo_normalize(p_nickname))
  ), variant_groups(spellings) as (
    values
      (array['carl', 'karl']),
      (array['catarina', 'catharina', 'katarina', 'katharina']),
      (array['cathrin', 'cathrine', 'katrin', 'katrine']),
      (array['christian', 'kristian']),
      (array['christina', 'kristina']),
      (array['christoffer', 'christopher', 'kristoffer']),
      (array['eric', 'erik']),
      (array['fredric', 'fredrick', 'fredrik']),
      (array['jessica', 'jessika']),
      (array['margareta', 'margaretha']),
      (array['mikael', 'micael', 'michael']),
      (array['philip', 'phillip', 'filip']),
      (array['sofie', 'sophie']),
      (array['sofia', 'sophia']),
      (array['stefan', 'stephan']),
      (array['therese', 'terese']),
      (array['thomas', 'tomas']),
      (array['victor', 'viktor']),
      (array['victoria', 'viktoria'])
  )
  select exists (
    select 1
    from guess cross join names
    where names.value <> '' and (
      names.value = guess.value
      or (
        length(names.value) between 5 and 100
        and abs(length(names.value)-length(guess.value)) <= 1
        and extensions.levenshtein_less_equal(left(names.value,100),left(guess.value,100),1) <= 1
      )
      or exists (
        select 1 from variant_groups
        where names.value = any(spellings) and guess.value = any(spellings)
      )
    )
  )
$$;
