-- PB-01: allow RT staff to correct resident names and house assignments
-- inside their RT. Admins retain their existing full management access.
create or replace function public.guard_profile() returns trigger
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
       and old.role = 'warga'
       and old.rt_id = public.current_rt()
       and new.rt_id is not distinct from old.rt_id
       and btrim(new.full_name) <> ''
       and (to_jsonb(new) - 'full_name' - 'unit_id') =
           (to_jsonb(old) - 'full_name' - 'unit_id') then
      return new;
    end if;

    if v_role = 'pengurus_rt' and old.id <> auth.uid()
       and old.role = 'warga' and old.verification_status = 'menunggu'
       and new.verification_status in ('terverifikasi', 'ditolak')
       and old.rt_id = public.current_rt()
       and new.rt_id is not distinct from old.rt_id
       and (to_jsonb(new) - 'verification_status') =
           (to_jsonb(old) - 'verification_status') then
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

create or replace function public.audit_profile_resident_update() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.full_name is distinct from old.full_name
     or new.unit_id is distinct from old.unit_id
     or new.rt_id is distinct from old.rt_id then
    insert into public.audit_log(actor_id, aksi, entitas, entitas_id, detail)
    values (
      auth.uid(),
      'perbarui_data_warga',
      'profiles',
      new.id,
      jsonb_build_object(
        'nama_diubah', new.full_name is distinct from old.full_name,
        'rumah_diubah', new.unit_id is distinct from old.unit_id,
        'rt_diubah', new.rt_id is distinct from old.rt_id
      )
    );
  end if;
  return new;
end $$;

revoke all on function public.audit_profile_resident_update() from public, anon, authenticated;
create trigger profiles_audit_resident_update
  after update on public.profiles
  for each row execute function public.audit_profile_resident_update();
