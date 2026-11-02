-- LDV profilbilder: kör i Supabase SQL Editor
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('ldv-avatars','ldv-avatars',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists ldv_avatar_admin_select on storage.objects;
drop policy if exists ldv_avatar_admin_insert on storage.objects;
drop policy if exists ldv_avatar_admin_update on storage.objects;
drop policy if exists ldv_avatar_admin_delete on storage.objects;
create policy ldv_avatar_admin_select on storage.objects for select to authenticated using (bucket_id='ldv-avatars' and public.ldv_is_admin());
create policy ldv_avatar_admin_insert on storage.objects for insert to authenticated with check (bucket_id='ldv-avatars' and public.ldv_is_admin());
create policy ldv_avatar_admin_update on storage.objects for update to authenticated using (bucket_id='ldv-avatars' and public.ldv_is_admin()) with check (bucket_id='ldv-avatars' and public.ldv_is_admin());
create policy ldv_avatar_admin_delete on storage.objects for delete to authenticated using (bucket_id='ldv-avatars' and public.ldv_is_admin());