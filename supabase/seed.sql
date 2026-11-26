-- Tujuan: data wilayah dummy untuk demo M0; tidak berisi identitas warga nyata.
-- Aman dijalankan ulang: ID dan kunci unik tetap sama.
insert into public.rw (kode, nama)
values ('05', 'RW 5')
on conflict (kode) do update set nama = excluded.nama;

insert into public.rt (id, kode, nama, rw_id)
values (
  '10000000-0000-4000-8000-000000000001',
  'DEMO-01',
  'RT Demo 01',
  (select id from public.rw where kode = '05')
)
on conflict (id) do update set
  kode = excluded.kode,
  nama = excluded.nama,
  rw_id = excluded.rw_id;

insert into public.jalan (id, nama)
values ('20000000-0000-4000-8000-000000000001', 'Jalan Contoh')
on conflict (id) do update set nama = excluded.nama;

insert into public.kk (id) values
  ('30000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002'),
  ('30000000-0000-4000-8000-000000000003')
on conflict (id) do nothing;

insert into public.unit_rumah (id, jalan_id, nomor, rt_id, kk_id, lat, lng)
values
  ('40000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '01', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', null, null),
  ('40000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', '02', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', null, null),
  ('40000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', '03', '10000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000003', null, null)
on conflict (jalan_id, nomor) do update
set rt_id = excluded.rt_id,
    kk_id = excluded.kk_id,
    lat = excluded.lat,
    lng = excluded.lng;
