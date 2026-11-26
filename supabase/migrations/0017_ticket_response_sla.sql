-- PB-06: use calendar-hour response deadlines and durable auto escalation.
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Keep stricter existing response targets, but cap the maximum at 48 hours.
update public.tiket
set tenggat_respons_at = created_at + interval '48 hours'
where tenggat_respons_at is null
   or tenggat_respons_at > created_at + interval '48 hours';

create index if not exists tiket_rt_unresponded_created_idx
  on public.tiket(created_at)
  where level = 'rt' and status = 'baru' and direspons_at is null;

create or replace function public.guard_tiket() returns trigger
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
       (new.id is distinct from old.id or
        new.pelapor_id is distinct from old.pelapor_id or
        new.rt_id is distinct from old.rt_id or
        new.unit_id is distinct from old.unit_id or
        new.created_at is distinct from old.created_at or
        new.foto_path is distinct from old.foto_path) then
      raise exception 'Identitas, wilayah, dan foto tiket tidak dapat diubah';
    end if;

    if new.level is distinct from old.level then
      if old.level <> 'rt' or new.level <> 'rw' then
        raise exception 'Eskalasi hanya dari RT ke RW';
      end if;
      if new.alasan_eskalasi is null or
         length(btrim(new.alasan_eskalasi)) not between 1 and 1000 then
        raise exception 'Alasan eskalasi wajib diisi (maksimal 1000 karakter)';
      end if;
    elsif new.alasan_eskalasi is distinct from old.alasan_eskalasi then
      raise exception 'Alasan hanya dapat dicatat saat eskalasi';
    end if;

    if new.kategori is not distinct from old.kategori and
       new.prioritas is not distinct from old.prioritas then
      new.tenggat_respons_at := old.tenggat_respons_at;
      new.tenggat_selesai_at := old.tenggat_selesai_at;
    end if;
    if new.status <> 'baru' and old.status = 'baru' then
      new.direspons_at := now();
    else
      new.direspons_at := old.direspons_at;
    end if;
    if new.status in ('selesai', 'ditutup') and old.status not in ('selesai', 'ditutup') then
      new.selesai_at := now();
    else
      new.selesai_at := old.selesai_at;
    end if;
  end if;

  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and
     (new.kategori is distinct from old.kategori or
      new.prioritas is distinct from old.prioritas)) then
    select s.target_respons_menit, s.target_selesai_menit
      into v_respons, v_selesai
      from public.sla_aturan s
      where s.kategori = new.kategori
        and s.prioritas = new.prioritas
        and s.level = new.level;
    if found then
      new.tenggat_respons_at := new.created_at +
        make_interval(mins => least(v_respons, 2880));
      new.tenggat_selesai_at := new.created_at + make_interval(mins => v_selesai);
    else
      new.tenggat_respons_at := new.created_at + interval '48 hours';
      new.tenggat_selesai_at := null;
    end if;
  end if;

  return new;
end $$;

create or replace function public.escalate_unresponded_tickets()
returns bigint
language plpgsql
security definer
set search_path = '' as $$
declare v_escalated bigint;
begin
  update public.tiket
  set level = 'rw',
      alasan_eskalasi = 'Eskalasi otomatis setelah 96 jam tanpa respons RT.'
  where level = 'rt'
    and status = 'baru'
    and direspons_at is null
    and created_at <= now() - interval '96 hours';

  get diagnostics v_escalated = row_count;
  return v_escalated;
end $$;
revoke all on function public.escalate_unresponded_tickets()
  from public, anon, authenticated;

do $$
declare v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job
    where jobname = 'wesbar-ticket-auto-escalation'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'wesbar-ticket-auto-escalation',
    '*/5 * * * *',
    'select public.escalate_unresponded_tickets();'
  );
end $$;
