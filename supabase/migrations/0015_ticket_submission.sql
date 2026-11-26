-- PB-05: optional private photo evidence and ticket creation without
-- inventing SLA deadlines before the RW 05 operating rules are agreed.
alter table public.tiket
  add column foto_path text,
  alter column tenggat_respons_at drop not null,
  alter column tenggat_selesai_at drop not null;

alter table public.tiket
  add constraint tiket_foto_path_owner_check check (
    foto_path is null or (
      pelapor_id is not null
      and split_part(foto_path, '/', 1) = pelapor_id::text
      and split_part(foto_path, '/', 2) = id::text
      and split_part(foto_path, '/', 3) <> ''
      and split_part(foto_path, '/', 4) = ''
    )
  );

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
    if new.level is distinct from old.level and
       (old.level <> 'rt' or new.level <> 'rw') then
      raise exception 'Eskalasi hanya dari RT ke RW';
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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ticket-photos',
  'ticket-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy ticket_photo_upload_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'ticket-photos' and
    (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text and
    array_length(storage.foldername(storage.objects.name), 1) = 2 and
    split_part(storage.objects.name, '/', 3) in ('foto.jpg', 'foto.png', 'foto.webp')
  );

create policy ticket_photo_read_authorized on storage.objects
  for select to authenticated
  using (
    bucket_id = 'ticket-photos' and exists (
      select 1 from public.tiket t
      where t.foto_path = storage.objects.name and (
        t.pelapor_id = (select auth.uid()) or
        public.current_role() in ('pengurus_rw', 'admin') or
        (public.current_role() = 'pengurus_rt' and t.rt_id = public.current_rt())
      )
    )
  );

create policy ticket_photo_delete_unattached_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'ticket-photos' and
    (storage.foldername(storage.objects.name))[1] = (select auth.uid())::text and
    not exists (
      select 1 from public.tiket t where t.foto_path = storage.objects.name
    )
  );
