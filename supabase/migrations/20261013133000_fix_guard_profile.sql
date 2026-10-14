-- Admin pertama diangkat lewat SQL editor / secret key (tanpa JWT pengguna), jadi yang dijaga
-- hanya permintaan dari pengguna aplikasi. Klaim role di JWT tidak bisa dipalsukan klien.
create or replace function private.guard_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (new.role, new.is_blocked) is distinct from (old.role, old.is_blocked)
     and coalesce(auth.jwt() ->> 'role', '') in ('authenticated', 'anon')
     and not private.is_admin() then
    raise exception 'Hanya admin yang bisa mengubah peran atau status blokir' using errcode = '42501';
  end if;
  return new;
end $$;
