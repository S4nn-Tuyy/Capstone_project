-- Tujuan: ringkasan analytics yang tetap memakai RLS pemanggil (PostgreSQL 15+).
-- Hanya pengurus/admin dapat membaca view; agregasi tidak mengungkap identitas warga.
create view public.v_heatmap_jalan_jam with (security_invoker = true) as
select sumber.rt_id, u.jalan_id,
       extract(hour from sumber.waktu at time zone 'Asia/Jakarta')::integer as jam,
       count(*) filter (where sumber.jenis = 'insiden')::bigint as jumlah_insiden,
       count(*) filter (where sumber.jenis = 'pengaduan')::bigint as jumlah_pengaduan
from (
  select i.rt_id, i.unit_id, i.created_at as waktu, 'insiden'::text as jenis
  from public.insiden i where not i.is_latihan and i.status <> 'alarm_palsu'
  union all
  select t.rt_id, t.unit_id, t.created_at as waktu, 'pengaduan'::text as jenis
  from public.tiket t where t.kategori = 'keamanan'
) sumber
join public.unit_rumah u on u.id = sumber.unit_id
where public.current_role() in ('pengurus_rt', 'pengurus_rw', 'admin')
group by sumber.rt_id, u.jalan_id, extract(hour from sumber.waktu at time zone 'Asia/Jakarta');

create view public.v_kepatuhan_sla with (security_invoker = true) as
select t.rt_id, t.kategori, t.prioritas,
       count(*)::bigint as jumlah_tiket,
       count(*) filter (where t.direspons_at is not null and
         t.direspons_at <= t.tenggat_respons_at)::bigint as respons_tepat_waktu,
       count(*) filter (where t.status in ('selesai', 'ditutup'))::bigint as tiket_selesai,
       count(*) filter (where t.status in ('selesai', 'ditutup') and
         t.selesai_at <= t.tenggat_selesai_at)::bigint as selesai_tepat_waktu
from public.tiket t
where public.current_role() in ('pengurus_rt', 'pengurus_rw', 'admin')
group by t.rt_id, t.kategori, t.prioritas;

create view public.v_keterbacaan with (security_invoker = true) as
select p.id as pengumuman_id, p.target_rt_id, p.jenis,
       count(pp.id)::bigint as jumlah_penerima,
       count(pp.dibaca_at)::bigint as jumlah_dibaca,
       round(100.0 * count(pp.dibaca_at) / nullif(count(pp.id), 0), 2) as persen_dibaca
from public.pengumuman p
left join public.pengumuman_penerima pp on pp.pengumuman_id = p.id
where public.current_role() in ('pengurus_rt', 'pengurus_rw', 'admin')
  and p.terkirim_at is not null
group by p.id, p.target_rt_id, p.jenis;

create view public.v_waktu_respons with (security_invoker = true) as
select i.rt_id, i.jenis,
       count(*)::bigint as jumlah_insiden,
       count(pertama.responded_at)::bigint as jumlah_direspons,
       round(avg(extract(epoch from (pertama.responded_at - i.created_at)))::numeric, 2)
         as rata_respons_detik
from public.insiden i
left join lateral (
  select min(ip.responded_at) as responded_at
  from public.insiden_penerima ip
  where ip.insiden_id = i.id and ip.respons = 'menuju'
) pertama on true
where public.current_role() in ('pengurus_rt', 'pengurus_rw', 'admin')
  and not i.is_latihan and i.status <> 'alarm_palsu'
group by i.rt_id, i.jenis;

revoke all on public.v_heatmap_jalan_jam, public.v_kepatuhan_sla,
  public.v_keterbacaan, public.v_waktu_respons from public, anon;
grant select on public.v_heatmap_jalan_jam, public.v_kepatuhan_sla,
  public.v_keterbacaan, public.v_waktu_respons to authenticated;
