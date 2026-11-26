-- Tujuan: menyimpan struktur RT, jalan, rumah, dan KK sebagai ID internal saja.
create extension if not exists pgcrypto;

create table public.rt (
  id uuid primary key default gen_random_uuid(),
  kode text not null unique,
  nama text not null
);

create table public.jalan (
  id uuid primary key default gen_random_uuid(),
  nama text not null unique
);

create table public.kk (
  id uuid primary key default gen_random_uuid()
);

create table public.unit_rumah (
  id uuid primary key default gen_random_uuid(),
  jalan_id uuid not null references public.jalan(id) on delete restrict,
  nomor text not null,
  rt_id uuid not null references public.rt(id) on delete restrict,
  kk_id uuid references public.kk(id) on delete set null,
  lat double precision,
  lng double precision,
  constraint unit_rumah_nomor_unique unique (jalan_id, nomor),
  constraint unit_rumah_koordinat_check check (
    (lat is null and lng is null) or
    (lat between -90 and 90 and lng between -180 and 180)
  )
);
create index unit_rumah_rt_idx on public.unit_rumah(rt_id);
create index unit_rumah_kk_idx on public.unit_rumah(kk_id);
create index unit_rumah_jalan_idx on public.unit_rumah(jalan_id);

alter table public.rt enable row level security;
alter table public.jalan enable row level security;
alter table public.kk enable row level security;
alter table public.unit_rumah enable row level security;
