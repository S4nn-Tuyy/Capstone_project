-- Tujuan: catatan audit, metrik kesehatan, dan pengaturan yang dikelola admin.
create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  aksi text not null,
  entitas text not null,
  entitas_id uuid,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_waktu_idx on public.audit_log(created_at desc);
create index audit_log_entitas_idx on public.audit_log(entitas, entitas_id);
create index audit_log_actor_idx on public.audit_log(actor_id, created_at desc);

create table public.health_checks (
  id uuid primary key default gen_random_uuid(),
  komponen text not null,
  metrik text not null,
  nilai numeric not null,
  diperiksa_at timestamptz not null default now()
);
create index health_checks_komponen_waktu_idx on public.health_checks(komponen, diperiksa_at desc);

create table public.pengaturan (
  id uuid primary key default gen_random_uuid(),
  kunci text not null unique check (kunci in ('radius_tetangga_m', 'batas_eskalasi_detik', 'retensi_hari')),
  nilai integer not null check (nilai > 0),
  updated_at timestamptz not null default now()
);

alter table public.audit_log enable row level security;
alter table public.health_checks enable row level security;
alter table public.pengaturan enable row level security;
-- TODO: pg_cron untuk eskalasi, retensi, dan health check diputuskan di tahap berikutnya.
