-- Policy tulis staf/admin dipisah per aksi supaya SELECT cukup dari satu policy (advisor multiple_permissive_policies).
drop policy "staf kelola" on public.flood_points;
create policy "staf kelola (tambah)" on public.flood_points for insert to authenticated with check ((select private.is_staff()));
create policy "staf kelola (ubah)" on public.flood_points for update to authenticated using ((select private.is_staff())) with check ((select private.is_staff()));
create policy "staf kelola (hapus)" on public.flood_points for delete to authenticated using ((select private.is_staff()));

drop policy "admin kelola" on public.shelters;
create policy "admin kelola (tambah)" on public.shelters for insert to authenticated with check ((select private.is_admin()));
create policy "admin kelola (ubah)" on public.shelters for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "admin kelola (hapus)" on public.shelters for delete to authenticated using ((select private.is_admin()));

drop policy "admin kelola" on public.emergency_contacts;
create policy "admin kelola (tambah)" on public.emergency_contacts for insert to authenticated with check ((select private.is_admin()));
create policy "admin kelola (ubah)" on public.emergency_contacts for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "admin kelola (hapus)" on public.emergency_contacts for delete to authenticated using ((select private.is_admin()));
