-- Tujuan: identitas minimal pengguna, token push, dan helper otorisasi tanpa rekursi RLS.
create type public.peran_pengguna as enum ('warga', 'security', 'pengurus_rt', 'pengurus_rw', 'admin');
create type public.status_verifikasi as enum ('menunggu', 'terverifikasi', 'ditolak');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.peran_pengguna not null default 'warga',
  rt_id uuid references public.rt(id) on delete restrict,
  unit_id uuid references public.unit_rumah(id) on delete restrict,
  verification_status public.status_verifikasi not null default 'menunggu',
  consented_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint profiles_warga_unit_check check (role <> 'warga' or (rt_id is not null and unit_id is not null)),
  constraint profiles_pengurus_rt_check check (role <> 'pengurus_rt' or rt_id is not null)
);
create index profiles_rt_idx on public.profiles(rt_id);
create index profiles_unit_idx on public.profiles(unit_id);
create index profiles_role_idx on public.profiles(role);

create table public.fcm_token (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index fcm_token_profile_idx on public.fcm_token(profile_id);

alter table public.profiles enable row level security;
alter table public.fcm_token enable row level security;

-- SECURITY DEFINER membaca hanya identitas pemanggil; tidak menerima ID/peran dari klien.
create function public.current_role() returns public.peran_pengguna
language sql stable security definer set search_path = ''
as $$ select p.role from public.profiles p
  where p.id = (select auth.uid()) and p.verification_status = 'terverifikasi'
    and p.consented_at is not null $$;

create function public.current_rt() returns uuid
language sql stable security definer set search_path = ''
as $$ select p.rt_id from public.profiles p
  where p.id = (select auth.uid()) and p.verification_status = 'terverifikasi'
    and p.consented_at is not null $$;

create function public.current_unit() returns uuid
language sql stable security definer set search_path = ''
as $$ select p.unit_id from public.profiles p
  where p.id = (select auth.uid()) and p.verification_status = 'terverifikasi'
    and p.consented_at is not null $$;

revoke all on function public.current_role() from public;
revoke all on function public.current_rt() from public;
revoke all on function public.current_unit() from public;
grant execute on function public.current_role(), public.current_rt(), public.current_unit() to authenticated;

-- RLS membatasi baris, trigger menjaga kolom role/RT/unit dari perubahan oleh warga.
create function public.guard_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_role public.peran_pengguna := public.current_role();
begin
  if new.unit_id is not null and not exists (
    select 1 from public.unit_rumah u where u.id = new.unit_id and u.rt_id = new.rt_id
  ) then raise exception 'Unit dan RT tidak sesuai'; end if;
  if tg_op = 'INSERT' then
    if auth.role() <> 'service_role' and v_role is distinct from 'admin' then
      if new.id is distinct from auth.uid() or new.role <> 'warga'
         or new.verification_status <> 'menunggu' then
        raise exception 'Pendaftaran hanya untuk profil warga sendiri';
      end if;
      new.created_at := now();
      new.consented_at := now();
    end if;
  elsif auth.role() <> 'service_role' and v_role is distinct from 'admin' then
    if v_role = 'pengurus_rt' and old.id <> auth.uid()
       and old.role = 'warga' and old.verification_status = 'menunggu'
       and new.verification_status in ('terverifikasi', 'ditolak')
       and old.rt_id = public.current_rt() and new.rt_id is not distinct from old.rt_id
       and (to_jsonb(new) - 'verification_status') = (to_jsonb(old) - 'verification_status') then
      return new;
    end if;
    if old.id = auth.uid() and
       (to_jsonb(new) - 'full_name' - 'phone' - 'consented_at') =
       (to_jsonb(old) - 'full_name' - 'phone' - 'consented_at')
       and new.consented_at >= old.consented_at then
      if new.consented_at is distinct from old.consented_at then
        new.consented_at := now();
      end if;
      return new;
    end if;
    raise exception 'Perubahan profil tidak diizinkan';
  end if;
  return new;
end $$;
create trigger profiles_guard before insert or update on public.profiles
for each row execute function public.guard_profile();
revoke all on function public.guard_profile() from public, anon, authenticated;
