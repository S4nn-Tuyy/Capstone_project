-- Tujuan: kejadian darurat, penerima yang dituju, dan kontak darurat.
create type public.jenis_insiden as enum ('keamanan', 'kebakaran', 'medis', 'lainnya');
create type public.status_insiden as enum ('aktif', 'ditangani', 'selesai', 'alarm_palsu');
create type public.respons_insiden as enum ('menunggu', 'menuju', 'tidak_bisa');

create table public.insiden (
  id uuid primary key default gen_random_uuid(),
  pelapor_id uuid references public.profiles(id) on delete set null,
  unit_id uuid references public.unit_rumah(id) on delete set null,
  rt_id uuid not null references public.rt(id) on delete restrict,
  jenis public.jenis_insiden not null,
  status public.status_insiden not null default 'aktif',
  is_latihan boolean not null default false,
  lokasi text not null,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now(),
  ditangani_at timestamptz,
  selesai_at timestamptz,
  eskalasi_at timestamptz,
  constraint insiden_koordinat_check check (
    (lat is null and lng is null) or
    (lat between -90 and 90 and lng between -180 and 180)
  )
);
create index insiden_rt_status_waktu_idx on public.insiden(rt_id, status, created_at desc);
create index insiden_pelapor_idx on public.insiden(pelapor_id, created_at desc);
create index insiden_unit_idx on public.insiden(unit_id);

create table public.insiden_penerima (
  id uuid primary key default gen_random_uuid(),
  insiden_id uuid not null references public.insiden(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  respons public.respons_insiden not null default 'menunggu',
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  constraint insiden_penerima_unique unique (insiden_id, profile_id)
);
create index insiden_penerima_profile_idx on public.insiden_penerima(profile_id, created_at desc);
create index insiden_penerima_insiden_respons_idx on public.insiden_penerima(insiden_id, respons);

create table public.kontak_darurat (
  id uuid primary key default gen_random_uuid(),
  rt_id uuid references public.rt(id) on delete cascade,
  nama text not null,
  nomor_telepon text not null,
  jenis public.jenis_insiden,
  aktif boolean not null default true
);
create index kontak_darurat_rt_idx on public.kontak_darurat(rt_id);

alter table public.insiden enable row level security;
alter table public.insiden_penerima enable row level security;
alter table public.kontak_darurat enable row level security;

-- Membuka detail hanya bagi penerima yang ditugaskan selama insiden belum ditutup.
create function public.is_penerima_insiden(p_insiden uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.insiden_penerima ip
    join public.insiden i on i.id = ip.insiden_id
    where ip.insiden_id = p_insiden and ip.profile_id = (select auth.uid())
      and i.status in ('aktif', 'ditangani')
  )
$$;
revoke all on function public.is_penerima_insiden(uuid) from public;
grant execute on function public.is_penerima_insiden(uuid) to authenticated;

create function public.guard_insiden_update() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'service_role' or public.current_role() = 'admin' then return new; end if;
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.ditangani_at := null;
    new.selesai_at := null;
    new.eskalasi_at := null;
    select r.kode || ' / ' || j.nama || ' No. ' || u.nomor into new.lokasi
    from public.unit_rumah u join public.rt r on r.id = u.rt_id
    join public.jalan j on j.id = u.jalan_id where u.id = new.unit_id;
    if not found then raise exception 'Unit insiden tidak ditemukan'; end if;
    return new;
  end if;
  if public.current_role() not in ('security', 'pengurus_rt', 'pengurus_rw')
     or (to_jsonb(new) - 'status' - 'ditangani_at' - 'selesai_at' - 'eskalasi_at') <>
        (to_jsonb(old) - 'status' - 'ditangani_at' - 'selesai_at' - 'eskalasi_at') then
    raise exception 'Hanya status insiden yang dapat diubah';
  end if;
  if old.status in ('selesai', 'alarm_palsu') or
     (new.status = 'aktif' and old.status <> 'aktif') then
    raise exception 'Insiden yang ditutup tidak dapat dibuka kembali';
  end if;
  new.ditangani_at := old.ditangani_at;
  new.selesai_at := old.selesai_at;
  if new.status = 'ditangani' and old.status <> 'ditangani' then new.ditangani_at := now(); end if;
  if new.status in ('selesai', 'alarm_palsu') and old.status <> new.status then new.selesai_at := now(); end if;
  if new.eskalasi_at is distinct from old.eskalasi_at then
    if old.eskalasi_at is not null or new.eskalasi_at is null then
      raise exception 'Eskalasi sudah dicatat';
    end if;
    new.eskalasi_at := now();
  end if;
  return new;
end $$;
create trigger insiden_update_guard before insert or update on public.insiden
for each row execute function public.guard_insiden_update();
revoke all on function public.guard_insiden_update() from public, anon, authenticated;

create function public.guard_respons_insiden() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'service_role' or public.current_role() = 'admin' then return new; end if;
  if old.profile_id <> auth.uid() or
     (to_jsonb(new) - 'respons' - 'responded_at') <>
     (to_jsonb(old) - 'respons' - 'responded_at') then
    raise exception 'Hanya respons sendiri yang dapat diubah';
  end if;
  if old.respons <> 'menunggu' then raise exception 'Respons sudah dicatat'; end if;
  if new.respons <> 'menunggu' then new.responded_at := now(); end if;
  return new;
end $$;
create trigger insiden_penerima_update_guard before update on public.insiden_penerima
for each row execute function public.guard_respons_insiden();
revoke all on function public.guard_respons_insiden() from public, anon, authenticated;
