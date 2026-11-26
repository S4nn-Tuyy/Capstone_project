-- Tujuan: calon warga yang sudah login dapat mencari ID unit dari alamat tepat
-- tanpa membuka daftar semua rumah atau data KK sebelum verifikasi RT.
create function public.resolve_registration_unit(
  p_rt_code text,
  p_jalan_name text,
  p_nomor text
) returns table (rt_id uuid, unit_id uuid)
language sql stable security definer set search_path = '' as $$
  select u.rt_id, u.id
  from public.unit_rumah u
  join public.rt r on r.id = u.rt_id
  join public.jalan j on j.id = u.jalan_id
  where auth.uid() is not null
    and lower(btrim(r.kode)) = lower(btrim(p_rt_code))
    and lower(btrim(j.nama)) = lower(btrim(p_jalan_name))
    and lower(btrim(u.nomor)) = lower(btrim(p_nomor))
  limit 1
$$;
revoke all on function public.resolve_registration_unit(text, text, text) from public, anon;
grant execute on function public.resolve_registration_unit(text, text, text) to authenticated;
