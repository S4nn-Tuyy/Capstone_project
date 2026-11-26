-- PB-06: keep the RT escalation reason in the ticket history.
alter table public.tiket
  add column alasan_eskalasi text,
  add constraint tiket_alasan_eskalasi_check check (
    alasan_eskalasi is null or
    length(btrim(alasan_eskalasi)) between 1 and 1000
  );

alter table public.tiket_riwayat
  add column catatan text;

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
      new.tenggat_respons_at := new.created_at + make_interval(mins => v_respons);
      new.tenggat_selesai_at := new.created_at + make_interval(mins => v_selesai);
    else
      new.tenggat_respons_at := null;
      new.tenggat_selesai_at := null;
    end if;
  end if;

  return new;
end $$;

create or replace function public.catat_tiket_riwayat() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.tiket_riwayat(
      tiket_id, actor_id, aksi, level_sesudah, status_sesudah
    ) values (new.id, auth.uid(), 'dibuat', new.level, new.status);
  else
    if new.level is distinct from old.level then
      insert into public.tiket_riwayat(
        tiket_id, actor_id, aksi, level_sebelum, level_sesudah, catatan
      ) values (
        new.id, auth.uid(), 'eskalasi', old.level, new.level, new.alasan_eskalasi
      );
    end if;
    if new.status is distinct from old.status then
      insert into public.tiket_riwayat(
        tiket_id, actor_id, aksi, status_sebelum, status_sesudah
      ) values (new.id, auth.uid(), 'status', old.status, new.status);
    end if;
  end if;
  return null;
end $$;
