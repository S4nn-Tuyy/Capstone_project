-- Tujuan: undangan QR tanpa kamera dan log gerbang dengan idempotensi offline.
create type public.keputusan_akses as enum ('menunggu', 'diizinkan', 'ditolak');

create table public.undangan_tamu (
  id uuid primary key default gen_random_uuid(),
  tuan_rumah_id uuid not null references public.profiles(id) on delete restrict,
  unit_id uuid not null references public.unit_rumah(id) on delete restrict,
  nama_tamu text not null,
  token_qr uuid not null default gen_random_uuid() unique,
  berlaku_mulai_at timestamptz not null,
  berlaku_sampai_at timestamptz not null,
  dibatalkan_at timestamptz,
  created_at timestamptz not null default now(),
  constraint undangan_jendela_check check (berlaku_sampai_at > berlaku_mulai_at)
);
create index undangan_tuan_rumah_idx on public.undangan_tamu(tuan_rumah_id, berlaku_mulai_at desc);
create index undangan_unit_idx on public.undangan_tamu(unit_id);
create index undangan_jendela_idx on public.undangan_tamu(berlaku_mulai_at, berlaku_sampai_at);

create table public.log_gerbang (
  id uuid primary key default gen_random_uuid(),
  local_uuid uuid not null unique,
  undangan_id uuid unique references public.undangan_tamu(id) on delete restrict,
  unit_id uuid references public.unit_rumah(id) on delete set null,
  security_id uuid not null references public.profiles(id) on delete restrict,
  nama_tamu text,
  keputusan public.keputusan_akses not null default 'menunggu',
  masuk_at timestamptz,
  keluar_at timestamptz,
  created_at timestamptz not null default now(),
  constraint gerbang_waktu_check check (keluar_at is null or (masuk_at is not null and keluar_at >= masuk_at))
);
create index log_gerbang_unit_waktu_idx on public.log_gerbang(unit_id, created_at desc);
create index log_gerbang_security_waktu_idx on public.log_gerbang(security_id, created_at desc);
create index log_gerbang_keputusan_waktu_idx on public.log_gerbang(keputusan, created_at desc);

alter table public.undangan_tamu enable row level security;
alter table public.log_gerbang enable row level security;

create function public.guard_undangan() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() = 'service_role' or public.current_role() = 'admin' then return new; end if;
  if tg_op = 'INSERT' then
    if new.tuan_rumah_id <> auth.uid() or new.unit_id <> public.current_unit() then
      raise exception 'Undangan hanya untuk unit sendiri'; end if;
    new.created_at := now();
    new.token_qr := gen_random_uuid();
  elsif (to_jsonb(new) - 'nama_tamu' - 'berlaku_mulai_at' - 'berlaku_sampai_at' - 'dibatalkan_at') <>
        (to_jsonb(old) - 'nama_tamu' - 'berlaku_mulai_at' - 'berlaku_sampai_at' - 'dibatalkan_at') then
    raise exception 'Identitas dan token undangan tidak dapat diubah';
  end if;
  if tg_op = 'UPDATE' and new.dibatalkan_at is distinct from old.dibatalkan_at then
    if old.dibatalkan_at is not null or new.dibatalkan_at is null then
      raise exception 'Undangan yang dibatalkan tidak dapat diaktifkan kembali';
    end if;
    new.dibatalkan_at := now();
  end if;
  return new;
end $$;
create trigger undangan_guard before insert or update on public.undangan_tamu
for each row execute function public.guard_undangan();
revoke all on function public.guard_undangan() from public, anon, authenticated;

create function public.guard_log_gerbang() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_unit uuid;
begin
  if auth.role() = 'service_role' or public.current_role() = 'admin' then return new; end if;
  if tg_op = 'INSERT' then
    if public.current_role() <> 'security' or new.security_id <> auth.uid() then
      raise exception 'Hanya security dapat membuat log atas namanya sendiri';
    end if;
    new.created_at := now();
    if new.undangan_id is not null then
      select u.unit_id into v_unit from public.undangan_tamu u
      where u.id = new.undangan_id and u.dibatalkan_at is null
        and now() between u.berlaku_mulai_at and u.berlaku_sampai_at;
      if not found or new.unit_id is distinct from v_unit then
        raise exception 'QR tidak berlaku atau unit tidak sesuai'; end if;
    end if;
  elsif public.current_role() <> 'security' or
        (to_jsonb(new) - 'keputusan' - 'masuk_at' - 'keluar_at') <>
        (to_jsonb(old) - 'keputusan' - 'masuk_at' - 'keluar_at') then
    raise exception 'Log gerbang hanya boleh diubah oleh security';
  end if;
  if new.keputusan = 'diizinkan' and new.masuk_at is null then new.masuk_at := now(); end if;
  return new;
end $$;
create trigger log_gerbang_guard before insert or update on public.log_gerbang
for each row execute function public.guard_log_gerbang();
revoke all on function public.guard_log_gerbang() from public, anon, authenticated;
