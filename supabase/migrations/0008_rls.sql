-- Tujuan: membuka akses minimum kepada authenticated; anon tetap tanpa hak.
-- Service_role (backend tepercaya saja) melewati RLS; jangan kirim kuncinya ke klien.
revoke all on public.rt, public.jalan, public.kk, public.unit_rumah,
  public.profiles, public.fcm_token, public.insiden, public.insiden_penerima,
  public.kontak_darurat, public.pengumuman, public.pengumuman_penerima,
  public.sla_aturan, public.tiket, public.tiket_riwayat,
  public.undangan_tamu, public.log_gerbang, public.audit_log,
  public.health_checks, public.pengaturan from anon, public;
grant select, insert, update, delete on public.rt, public.jalan, public.kk,
  public.unit_rumah, public.profiles, public.fcm_token, public.insiden,
  public.insiden_penerima, public.kontak_darurat, public.pengumuman,
  public.pengumuman_penerima, public.sla_aturan, public.tiket,
  public.tiket_riwayat, public.undangan_tamu, public.log_gerbang,
  public.audit_log, public.health_checks, public.pengaturan to authenticated;

-- Untuk semua tabel selain riwayat/audit: admin tidak dibatasi RLS.
do $policies$
declare t text;
begin
  foreach t in array array[
    'rt', 'jalan', 'kk', 'unit_rumah', 'profiles', 'fcm_token',
    'insiden', 'insiden_penerima', 'kontak_darurat',
    'pengumuman', 'pengumuman_penerima', 'sla_aturan', 'tiket',
    'undangan_tamu', 'log_gerbang', 'health_checks', 'pengaturan'
  ] loop
    execute format(
      'create policy admin_all on public.%I for all to authenticated using (public.current_role() = ''admin'') with check (public.current_role() = ''admin'')', t
    );
  end loop;
end $policies$;

-- Wilayah: warga melihat unit sendiri; pengurus RT wilayahnya; RW seluruh wilayah.
create policy rt_read on public.rt for select to authenticated using (
  id = public.current_rt() or public.current_role() in ('pengurus_rw', 'admin'));
create policy jalan_read on public.jalan for select to authenticated using (
  public.current_role() in ('pengurus_rw', 'admin') or exists (
    select 1 from public.unit_rumah u where u.jalan_id = jalan.id and
      (u.id = public.current_unit() or
       (public.current_role() = 'pengurus_rt' and u.rt_id = public.current_rt()))
  ));
create policy kk_read on public.kk for select to authenticated using (
  public.current_role() in ('pengurus_rw', 'admin') or exists (
    select 1 from public.unit_rumah u where u.kk_id = kk.id and
      (u.id = public.current_unit() or
       (public.current_role() = 'pengurus_rt' and u.rt_id = public.current_rt()))
  ));
create policy unit_read on public.unit_rumah for select to authenticated using (
  id = public.current_unit() or public.current_role() in ('pengurus_rw', 'admin') or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()));

-- Profil: calon warga melihat profil sendiri; RT hanya memverifikasi RT-nya.
create policy profile_read on public.profiles for select to authenticated using (
  id = (select auth.uid()) or public.current_role() in ('pengurus_rw', 'admin') or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()));
create policy profile_register on public.profiles for insert to authenticated with check (
  id = (select auth.uid()) and role = 'warga' and verification_status = 'menunggu');
create policy profile_change on public.profiles for update to authenticated using (
  id = (select auth.uid()) or public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()))
with check (
  id = (select auth.uid()) or public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()));
-- RW hanya baca profil; guard_profile menolak perubahan selain pemilik/RT/admin.
create policy fcm_own on public.fcm_token for all to authenticated using (
  profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

-- Panic Button: penerima tetangga melihat insiden sendiri hanya saat aktif/ditangani.
create policy insiden_read on public.insiden for select to authenticated using (
  pelapor_id = (select auth.uid()) or public.is_penerima_insiden(id) or
  public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()) or
  (public.current_role() = 'security' and status in ('aktif', 'ditangani')));
create policy insiden_warga_create on public.insiden for insert to authenticated with check (
  public.current_role() = 'warga' and pelapor_id = (select auth.uid()) and
  rt_id = public.current_rt() and unit_id = public.current_unit() and status = 'aktif');
create policy insiden_petugas_update on public.insiden for update to authenticated using (
  public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()) or
  (public.current_role() = 'security' and status in ('aktif', 'ditangani')))
with check (
  public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()) or
  public.current_role() = 'security');
create policy penerima_read on public.insiden_penerima for select to authenticated using (
  (profile_id = (select auth.uid()) and public.is_penerima_insiden(insiden_id)) or exists (
    select 1 from public.insiden i where i.id = insiden_id and (
      i.pelapor_id = (select auth.uid()) or public.current_role() = 'pengurus_rw' or
      (public.current_role() = 'pengurus_rt' and i.rt_id = public.current_rt())
    )
  ));
create policy penerima_respond on public.insiden_penerima for update to authenticated using (
  profile_id = (select auth.uid()) and public.is_penerima_insiden(insiden_id))
with check (profile_id = (select auth.uid()) and public.is_penerima_insiden(insiden_id));
-- Penugasan penerima hanya oleh admin atau backend service_role.
create policy kontak_read on public.kontak_darurat for select to authenticated using (
  public.current_role() = 'pengurus_rw' or
  (public.current_role() in ('warga', 'pengurus_rt') and
    (rt_id is null or rt_id = public.current_rt())));
create policy kontak_rt_manage on public.kontak_darurat for all to authenticated using (
  public.current_role() = 'pengurus_rt' and rt_id = public.current_rt())
with check (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt());

-- Broadcast: isi hanya kepada penerima yang tercatat dan sudah dikirim.
create policy pengumuman_read on public.pengumuman for select to authenticated using (
  public.is_penerima_pengumuman(id) or
  (public.current_role() in ('pengurus_rt', 'pengurus_rw') and penulis_id = (select auth.uid())) or
  public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and audiens = 'rt' and target_rt_id = public.current_rt()));
create policy pengumuman_rt_create on public.pengumuman for insert to authenticated with check (
  public.current_role() = 'pengurus_rt' and penulis_id = (select auth.uid()) and
  audiens = 'rt' and target_rt_id = public.current_rt());
create policy pengumuman_rt_edit on public.pengumuman for update to authenticated using (
  public.current_role() = 'pengurus_rt' and penulis_id = (select auth.uid()) and
  audiens = 'rt' and target_rt_id = public.current_rt())
with check (
  public.current_role() = 'pengurus_rt' and penulis_id = (select auth.uid()) and
  audiens = 'rt' and target_rt_id = public.current_rt());
create policy pengumuman_rw_create on public.pengumuman for insert to authenticated with check (
  public.current_role() = 'pengurus_rw' and penulis_id = (select auth.uid()));
create policy pengumuman_rw_edit on public.pengumuman for update to authenticated using (
  public.current_role() = 'pengurus_rw' and penulis_id = (select auth.uid()))
with check (public.current_role() = 'pengurus_rw' and penulis_id = (select auth.uid()));
create policy pengumuman_penerima_read on public.pengumuman_penerima for select to authenticated using (
  (profile_id = (select auth.uid()) and public.is_penerima_pengumuman(pengumuman_id)) or
  public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and exists (
    select 1 from public.profiles p where p.id = profile_id and p.rt_id = public.current_rt()
  )));
create policy pengumuman_penerima_baca on public.pengumuman_penerima for update to authenticated using (
  profile_id = (select auth.uid()) and public.is_penerima_pengumuman(pengumuman_id))
with check (profile_id = (select auth.uid()) and public.is_penerima_pengumuman(pengumuman_id));
-- Daftar penerima hanya dibuat admin/service_role; penerima sendiri hanya mengisi dibaca_at.

-- Pengaduan: tenggat dihitung dari aturan yang hanya dapat diatur admin.
create policy sla_read on public.sla_aturan for select to authenticated using (
  public.current_role() in ('warga', 'pengurus_rt', 'pengurus_rw'));
create policy tiket_read on public.tiket for select to authenticated using (
  pelapor_id = (select auth.uid()) or public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt()));
create policy tiket_warga_create on public.tiket for insert to authenticated with check (
  public.current_role() = 'warga' and pelapor_id = (select auth.uid()) and
  rt_id = public.current_rt() and unit_id = public.current_unit() and
  level = 'rt' and status = 'baru');
create policy tiket_rt_update on public.tiket for update to authenticated using (
  public.current_role() = 'pengurus_rt' and rt_id = public.current_rt() and level = 'rt')
with check (public.current_role() = 'pengurus_rt' and rt_id = public.current_rt());
create policy tiket_rw_update on public.tiket for update to authenticated using (
  public.current_role() = 'pengurus_rw') with check (public.current_role() = 'pengurus_rw');
create policy riwayat_read on public.tiket_riwayat for select to authenticated using (
  exists (select 1 from public.tiket t where t.id = tiket_id and (
    t.pelapor_id = (select auth.uid()) or public.current_role() = 'pengurus_rw' or
    (public.current_role() = 'pengurus_rt' and t.rt_id = public.current_rt())
  )) or public.current_role() = 'admin');
-- Riwayat append-only: hanya trigger SECURITY DEFINER yang menulis, termasuk saat eskalasi otomatis kelak.

-- Gerbang: security dapat melihat undangan yang masih valid dan seluruh log, tanpa batas shift.
create policy undangan_read on public.undangan_tamu for select to authenticated using (
  tuan_rumah_id = (select auth.uid()) or public.current_role() = 'pengurus_rw' or
  (public.current_role() = 'pengurus_rt' and exists (
    select 1 from public.unit_rumah u where u.id = unit_id and u.rt_id = public.current_rt()
  )) or
  (public.current_role() = 'security' and dibatalkan_at is null and
   now() between berlaku_mulai_at and berlaku_sampai_at));
create policy undangan_own_create on public.undangan_tamu for insert to authenticated with check (
  public.current_role() = 'warga' and tuan_rumah_id = (select auth.uid()) and
  unit_id = public.current_unit());
create policy undangan_own_update on public.undangan_tamu for update to authenticated using (
  public.current_role() = 'warga' and tuan_rumah_id = (select auth.uid()))
with check (public.current_role() = 'warga' and tuan_rumah_id = (select auth.uid()) and
            unit_id = public.current_unit());
create policy gerbang_read on public.log_gerbang for select to authenticated using (
  public.current_role() in ('security', 'pengurus_rw') or
  unit_id = public.current_unit() or
  (public.current_role() = 'pengurus_rt' and exists (
    select 1 from public.unit_rumah u where u.id = unit_id and u.rt_id = public.current_rt()
  )));
create policy gerbang_security_insert on public.log_gerbang for insert to authenticated with check (
  public.current_role() = 'security' and security_id = (select auth.uid()));
create policy gerbang_security_update on public.log_gerbang for update to authenticated using (
  public.current_role() = 'security') with check (public.current_role() = 'security');

-- Data sistem: audit hanya boleh ditambahkan; administrator boleh membaca seluruhnya.
create policy audit_admin_read on public.audit_log for select to authenticated using (
  public.current_role() = 'admin');
create policy audit_admin_insert on public.audit_log for insert to authenticated with check (
  public.current_role() = 'admin' and actor_id = (select auth.uid()));
