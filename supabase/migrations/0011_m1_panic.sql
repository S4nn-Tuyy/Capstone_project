-- Tujuan: idempotency offline, penerima berdasarkan radius, RPC panic aman,
-- dan status insiden real-time untuk aplikasi M1.
alter table public.insiden
  add column request_id uuid not null default gen_random_uuid();
create unique index insiden_request_id_uidx on public.insiden(request_id);

-- Warga wajib membuat insiden lewat RPC agar rate limit dan daftar penerima selalu dibuat.
drop policy insiden_warga_create on public.insiden;
revoke insert on public.insiden from authenticated;

create or replace function public.create_insiden(
  p_request_id uuid,
  p_jenis public.jenis_insiden,
  p_is_latihan boolean default false
) returns table (
  incident_id uuid,
  incident_status public.status_insiden,
  is_training boolean,
  recipient_count integer,
  event_created_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_existing public.insiden%rowtype;
  v_incident_id uuid;
  v_created_at timestamptz;
  v_radius double precision;
  v_source_lat double precision;
  v_source_lng double precision;
  v_recipients integer := 0;
  v_recent_count integer;
begin
  if v_user_id is null then
    raise exception 'Autentikasi diperlukan' using errcode = '42501';
  end if;
  if p_request_id is null or p_jenis is null then
    raise exception 'ID permintaan dan jenis insiden wajib diisi' using errcode = '22023';
  end if;

  select p.* into v_profile from public.profiles p where p.id = v_user_id;
  if not found or v_profile.verification_status <> 'terverifikasi' or v_profile.role <> 'warga' then
    raise exception 'Panic Button hanya untuk warga terverifikasi' using errcode = '42501';
  end if;

  -- Mode latihan sengaja tidak menyimpan insiden dan tidak membuat penerima.
  if coalesce(p_is_latihan, false) then
    return query select null::uuid, 'selesai'::public.status_insiden, true, 0, now();
    return;
  end if;

  select i.* into v_existing
  from public.insiden i where i.request_id = p_request_id;
  if found then
    if v_existing.pelapor_id is distinct from v_user_id then
      raise exception 'ID permintaan sudah digunakan' using errcode = '23505';
    end if;
    return query
      select v_existing.id, v_existing.status, v_existing.is_latihan,
        (select count(*)::integer from public.insiden_penerima ip where ip.insiden_id = v_existing.id),
        v_existing.created_at;
    return;
  end if;

  select count(*)::integer into v_recent_count
  from public.insiden i
  where i.pelapor_id = v_user_id and not i.is_latihan
    and i.created_at >= now() - interval '5 minutes';
  if v_recent_count >= 3 then
    raise exception 'Terlalu banyak alert dalam waktu singkat. Hubungi security langsung bila darurat.'
      using errcode = 'P0001';
  end if;

  select u.lat, u.lng into v_source_lat, v_source_lng
  from public.unit_rumah u where u.id = v_profile.unit_id;
  select coalesce((
    select s.nilai::double precision from public.pengaturan s
    where s.kunci = 'radius_tetangga_m'
  ), 150.0) into v_radius;

  insert into public.insiden (request_id, pelapor_id, unit_id, rt_id, jenis, status, is_latihan)
  values (p_request_id, v_user_id, v_profile.unit_id, v_profile.rt_id,
          p_jenis, 'aktif', false)
  returning id, created_at into v_incident_id, v_created_at;

  insert into public.insiden_penerima (insiden_id, profile_id)
  select v_incident_id, p.id
  from public.profiles p
  left join public.unit_rumah neighbor_unit on neighbor_unit.id = p.unit_id
  where p.id <> v_user_id
    and p.verification_status = 'terverifikasi'
    and (
      p.role = 'security'
      or p.role = 'pengurus_rw'
      or (p.role = 'pengurus_rt' and p.rt_id = v_profile.rt_id)
      or (
        p.role = 'warga' and p.rt_id = v_profile.rt_id
        and (
          v_source_lat is null or v_source_lng is null
          or (
            neighbor_unit.lat is not null and neighbor_unit.lng is not null
            and 2 * 6371000 * asin(sqrt(
              power(sin(radians(neighbor_unit.lat - v_source_lat) / 2), 2)
              + cos(radians(v_source_lat)) * cos(radians(neighbor_unit.lat))
                * power(sin(radians(neighbor_unit.lng - v_source_lng) / 2), 2)
            )) <= v_radius
          )
        )
      )
    )
  on conflict (insiden_id, profile_id) do nothing;
  get diagnostics v_recipients = row_count;

  return query select v_incident_id, 'aktif'::public.status_insiden, false,
    v_recipients, v_created_at;
end;
$$;
revoke all on function public.create_insiden(uuid, public.jenis_insiden, boolean) from public, anon;
grant execute on function public.create_insiden(uuid, public.jenis_insiden, boolean) to authenticated;

-- Hanya backend tepercaya yang boleh menandai eskalasi; Edge Function memanggilnya
-- 60 detik setelah alert dibuat dan hanya bila belum ada respons "menuju".
create function public.escalate_insiden_if_unanswered(p_insiden_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Hanya backend tepercaya yang dapat memicu eskalasi' using errcode = '42501';
  end if;
  update public.insiden i set eskalasi_at = now()
  where i.id = p_insiden_id and i.status = 'aktif' and i.eskalasi_at is null
    and i.created_at <= now() - interval '60 seconds'
    and not i.is_latihan
    and not exists (
      select 1 from public.insiden_penerima ip
      where ip.insiden_id = i.id and ip.respons = 'menuju'
    );
  return found;
end;
$$;
revoke all on function public.escalate_insiden_if_unanswered(uuid) from public, anon, authenticated;
grant execute on function public.escalate_insiden_if_unanswered(uuid) to service_role;

-- Realtime dipakai sebagai notifikasi in-app untuk klien yang sedang tersambung.
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Publication supabase_realtime tidak ditemukan';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'insiden'
  ) then
    alter publication supabase_realtime add table public.insiden;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'insiden_penerima'
  ) then
    alter publication supabase_realtime add table public.insiden_penerima;
  end if;
end;
$$;
