-- PB-06: backfill legacy response deadlines after guard_tiket was updated.
-- The older guard preserves existing deadlines on every ticket update.
alter table public.tiket disable trigger tiket_guard;

update public.tiket
set tenggat_respons_at = created_at + interval '48 hours'
where tenggat_respons_at is null
   or tenggat_respons_at > created_at + interval '48 hours';

alter table public.tiket enable trigger tiket_guard;
