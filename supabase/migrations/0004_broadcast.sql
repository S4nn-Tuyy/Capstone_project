-- Tujuan: pengumuman terjadwal dan catatan penerimaan/baca per akun.
create type public.jenis_pengumuman as enum ('umum', 'penting', 'darurat');
create type public.audiens_pengumuman as enum ('semua', 'rt', 'peran');

create table public.pengumuman (
  id uuid primary key default gen_random_uuid(),
  penulis_id uuid references public.profiles(id) on delete set null,
  jenis public.jenis_pengumuman not null default 'umum',
  audiens public.audiens_pengumuman not null,
  target_rt_id uuid references public.rt(id) on delete restrict,
  target_peran public.peran_pengguna,
  judul text not null,
  isi text not null,
  jadwal_at timestamptz,
  terkirim_at timestamptz,
  created_at timestamptz not null default now(),
  constraint pengumuman_audiens_check check (
    (audiens = 'semua' and target_rt_id is null and target_peran is null) or
    (audiens = 'rt' and target_rt_id is not null and target_peran is null) or
    (audiens = 'peran' and target_rt_id is null and target_peran is not null)
  )
);
create index pengumuman_jadwal_idx on public.pengumuman(jadwal_at);
create index pengumuman_target_rt_idx on public.pengumuman(target_rt_id, created_at desc);
create index pengumuman_terkirim_idx on public.pengumuman(terkirim_at);

create table public.pengumuman_penerima (
  id uuid primary key default gen_random_uuid(),
  pengumuman_id uuid not null references public.pengumuman(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  dibaca_at timestamptz,
  created_at timestamptz not null default now(),
  constraint pengumuman_penerima_unique unique (pengumuman_id, profile_id)
);
create index pengumuman_penerima_profile_idx on public.pengumuman_penerima(profile_id, dibaca_at);
create index pengumuman_penerima_pengumuman_idx on public.pengumuman_penerima(pengumuman_id, dibaca_at);

alter table public.pengumuman enable row level security;
alter table public.pengumuman_penerima enable row level security;

create function public.is_penerima_pengumuman(p_pengumuman uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pengumuman_penerima pp
    join public.pengumuman p on p.id = pp.pengumuman_id
    where pp.pengumuman_id = p_pengumuman and pp.profile_id = (select auth.uid())
      and p.terkirim_at is not null
  )
$$;
revoke all on function public.is_penerima_pengumuman(uuid) from public;
grant execute on function public.is_penerima_pengumuman(uuid) to authenticated;

-- Waktu terkirim hanya dapat ditetapkan backend tepercaya/admin setelah pengiriman nyata.
create function public.guard_pengumuman() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'service_role' or public.current_role() = 'admin' then return new; end if;
  if tg_op = 'INSERT' then
    if new.terkirim_at is not null then raise exception 'Pengiriman belum dikonfirmasi'; end if;
    new.created_at := now();
  elsif new.terkirim_at is distinct from old.terkirim_at or old.terkirim_at is not null
     or new.id is distinct from old.id or new.created_at is distinct from old.created_at then
    raise exception 'Pengumuman terkirim tidak dapat diubah oleh penulis';
  end if;
  return new;
end $$;
create trigger pengumuman_guard before insert or update on public.pengumuman
for each row execute function public.guard_pengumuman();
revoke all on function public.guard_pengumuman() from public, anon, authenticated;

create function public.guard_baca_pengumuman() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'service_role' or public.current_role() = 'admin' then return new; end if;
  if old.profile_id <> auth.uid() or
     (to_jsonb(new) - 'dibaca_at') <> (to_jsonb(old) - 'dibaca_at') or
     old.dibaca_at is not null then
    raise exception 'Hanya waktu baca milik sendiri yang dapat diisi sekali';
  end if;
  new.dibaca_at := now();
  return new;
end $$;
create trigger pengumuman_penerima_update_guard before update on public.pengumuman_penerima
for each row execute function public.guard_baca_pengumuman();
revoke all on function public.guard_baca_pengumuman() from public, anon, authenticated;
