-- The initial deployment covers RW 05 only. Every RT belongs to that RW.
create table public.rw (
  id uuid primary key default gen_random_uuid(),
  kode text not null unique,
  nama text not null
);

insert into public.rw(kode, nama)
values ('05', 'RW 5')
on conflict (kode) do update set nama = excluded.nama;

alter table public.rt
  add column rw_id uuid references public.rw(id) on delete restrict;

update public.rt
set rw_id = (select id from public.rw where kode = '05')
where rw_id is null;

alter table public.rt
  alter column rw_id set not null;

create index rt_rw_idx on public.rt(rw_id);

alter table public.rw enable row level security;
revoke all on public.rw from anon, public;
grant select on public.rw to authenticated;

create policy rw_read on public.rw for select to authenticated using (
  public.current_role() is not null
);
