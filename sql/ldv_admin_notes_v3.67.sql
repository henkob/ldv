-- LDV v3.67: interna adminnoteringar per person
-- Kör i Supabase SQL Editor innan funktionen används i administrationen.
CREATE TABLE IF NOT EXISTS public.ldv_admin_notes (
  person_id uuid PRIMARY KEY REFERENCES public.people(id) ON DELETE CASCADE,
  note text NOT NULL DEFAULT '' CHECK (char_length(note) <= 200),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ldv_admin_notes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ldv_admin_notes FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ldv_admin_notes TO authenticated;
DROP POLICY IF EXISTS ldv_admin_notes_admin_select ON public.ldv_admin_notes;
DROP POLICY IF EXISTS ldv_admin_notes_admin_insert ON public.ldv_admin_notes;
DROP POLICY IF EXISTS ldv_admin_notes_admin_update ON public.ldv_admin_notes;
DROP POLICY IF EXISTS ldv_admin_notes_admin_delete ON public.ldv_admin_notes;
CREATE POLICY ldv_admin_notes_admin_select ON public.ldv_admin_notes FOR SELECT TO authenticated USING ((SELECT public.ldv_is_admin()));
CREATE POLICY ldv_admin_notes_admin_insert ON public.ldv_admin_notes FOR INSERT TO authenticated WITH CHECK ((SELECT public.ldv_is_admin()));
CREATE POLICY ldv_admin_notes_admin_update ON public.ldv_admin_notes FOR UPDATE TO authenticated USING ((SELECT public.ldv_is_admin())) WITH CHECK ((SELECT public.ldv_is_admin()));
CREATE POLICY ldv_admin_notes_admin_delete ON public.ldv_admin_notes FOR DELETE TO authenticated USING ((SELECT public.ldv_is_admin()));
