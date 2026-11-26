-- Tujuan: tiket ber-SLA dengan jejak otomatis setiap perubahan level/eskalasi.
create type public.kategori_tiket as enum ('fasilitas', 'keamanan', 'hewan', 'listrik');
create type public.prioritas_tiket as enum ('rendah', 'sedang', 'tinggi', 'mendesak');
create type public.level_tiket as enum ('rt', 'rw');
create type public.status_tiket as enum ('baru', 'ditugaskan', 'diproses', 'selesai', 'ditutup');

create table public.sla_aturan (
  id uuid primary key default gen_random_uuid(),
  kategori public.kategori_tiket not null,
  prioritas public.prioritas_tiket not null,
  level public.level_tiket not null,
  target_respons_menit integer not null check (target_respons_menit > 0),
  target_selesai_menit integer not null check (target_selesai_menit > 0),
  constraint sla_aturan_unique unique (kategori, prioritas, level)
);

create table public.tiket (
  id uuid primary key default gen_random_uuid(),
  pelapor_id uuid references public.profiles(id) on delete set null,
  rt_id uuid not null references public.rt(id) on delete restrict,
  unit_id uuid references public.unit_rumah(id) on delete set null,
  kategori public.kategori_tiket not null,
  prioritas public.prioritas_tiket not null default 'sedang',
  level public.level_tiket not null default 'rt',
  status public.status_tiket not null default 'baru',
  deskripsi text not null,
  tenggat_respons_at timestamptz not null,
  tenggat_selesai_at timestamptz not null,
  direspons_at timestamptz,
  selesai_at timestamptz,
  created_at timestamptz not null default now()
);
create index tiket_rt_level_status_idx on public.tiket(rt_id, level, status);
create index tiket_pelapor_waktu_idx on public.tiket(pelapor_id, created_at desc);
create index tiket_tenggat_respons_idx on public.tiket(tenggat_respons_at);
create index tiket_tenggat_selesai_idx on public.tiket(tenggat_selesai_at);

create table public.tiket_riwayat (
  id uuid primary key default gen_random_uuid(),
  tiket_id uuid not null references public.tiket(id) on delete restrict,
  actor_id uuid references public.profiles(id) on delete set null,
  aksi text not null check (aksi in ('dibuat', 'status', 'eskalasi')),
  level_sebelum public.level_tiket,
  level_sesudah public.level_tiket,
  status_sebelum public.status_tiket,
  status_sesudah public.status_tiket,
  created_at timestamptz not null default now()
);
create index tiket_riwayat_tiket_waktu_idx on public.tiket_riwayat(tiket_id, created_at desc);

alter table public.sla_aturan enable row level security;
alter table public.tiket enable row level security;
alter table public.tiket_riwayat enable row level security;

create function public.guard_tiket() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_respons integer; v_selesai integer;
begin
  if tg_op = 'INSERT' and auth.role() <> 'service_role'
     and public.current_role() is distinct from 'admin' then
    new.created_at := now();
    new.direspons_at := null;
    new.selesai_at := null;
  end if;
  if tg_op = 'UPDATE' then
    if auth.role() <> 'service_role' and public.current_role() <> 'admin' and
       (new.id is distinct from old.id or new.pelapor_id is distinct from old.pelapor_id or
        new.rt_id is distinct from old.rt_id or new.unit_id is distinct from old.unit_id or
        new.created_at is distinct from old.created_at) then
      raise exception 'Identitas dan wilayah tiket tidak dapat diubah';
    end if;
    if new.level is distinct from old.level and
       (old.level <> 'rt' or new.level <> 'rw') then
      raise exception 'Eskalasi hanya dari RT ke RW';
    end if;
    if new.kategori is not distinct from old.kategori and
       new.prioritas is not distinct from old.prioritas then
      new.tenggat_respons_at := old.tenggat_respons_at;
      new.tenggat_selesai_at := old.tenggat_selesai_at;
    end if;
    if new.status <> 'baru' and old.status = 'baru' then new.direspons_at := now();
    else new.direspons_at := old.direspons_at; end if;
    if new.status in ('selesai', 'ditutup') and old.status not in ('selesai', 'ditutup')
      then new.selesai_at := now();
    else new.selesai_at := old.selesai_at; end if;
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and
     (new.kategori is distinct from old.kategori or new.prioritas is distinct from old.prioritas)) then
    select s.target_respons_menit, s.target_selesai_menit into v_respons, v_selesai
    from public.sla_aturan s where s.kategori = new.kategori
      and s.prioritas = new.prioritas and s.level = new.level;
    if not found then raise exception 'Aturan SLA belum tersedia'; end if;
    new.tenggat_respons_at := new.created_at + make_interval(mins => v_respons);
    new.tenggat_selesai_at := new.created_at + make_interval(mins => v_selesai);
  end if;
  return new;
end $$;
create trigger tiket_guard before insert or update on public.tiket
for each row execute function public.guard_tiket();
revoke all on function public.guard_tiket() from public, anon, authenticated;

-- Trigger berjalan untuk perubahan manual maupun perubahan oleh job tepercaya di masa depan.
create function public.catat_tiket_riwayat() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.tiket_riwayat(tiket_id, actor_id, aksi, level_sesudah, status_sesudah)
    values (new.id, auth.uid(), 'dibuat', new.level, new.status);
  else
    if new.level is distinct from old.level then
      insert into public.tiket_riwayat(tiket_id, actor_id, aksi, level_sebelum, level_sesudah)
      values (new.id, auth.uid(), 'eskalasi', old.level, new.level);
    end if;
    if new.status is distinct from old.status then
      insert into public.tiket_riwayat(tiket_id, actor_id, aksi, status_sebelum, status_sesudah)
      values (new.id, auth.uid(), 'status', old.status, new.status);
    end if;
  end if;
  return null;
end $$;
create trigger tiket_history after insert or update on public.tiket
for each row execute function public.catat_tiket_riwayat();
revoke all on function public.catat_tiket_riwayat() from public, anon, authenticated;
-- TODO: penjadwalan eskalasi otomatis (pg_cron) ditentukan pada tahap berikutnya; tidak dibuat di sini.
