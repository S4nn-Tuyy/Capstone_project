-- Hanya Edge Function tepercaya yang boleh menerbitkan pengumuman dan
-- membuat snapshot penerima. Seluruh langkah berada dalam satu transaksi.
create function public.publish_pengumuman(
  p_author_id uuid,
  p_jenis public.jenis_pengumuman,
  p_audiens public.audiens_pengumuman,
  p_target_rt_id uuid,
  p_target_peran public.peran_pengguna,
  p_judul text,
  p_isi text
) returns table (
  announcement_id uuid,
  recipient_count integer,
  sent_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
declare
  v_author_role public.peran_pengguna;
  v_author_rt uuid;
  v_announcement_id uuid;
  v_sent_at timestamptz := now();
  v_recipient_count integer := 0;
begin
  select p.role, p.rt_id into v_author_role, v_author_rt
  from public.profiles p
  where p.id = p_author_id
    and p.verification_status = 'terverifikasi'
    and p.consented_at is not null;
  if not found then
    raise exception 'Akun pengirim belum terverifikasi' using errcode = '42501';
  end if;
  if v_author_role not in ('pengurus_rt', 'pengurus_rw', 'admin') then
    raise exception 'Peran ini tidak dapat mengirim pengumuman' using errcode = '42501';
  end if;
  if p_judul is null or length(btrim(p_judul)) not between 1 and 120 then
    raise exception 'Judul wajib diisi (maksimal 120 karakter)' using errcode = '22023';
  end if;
  if p_isi is null or length(btrim(p_isi)) not between 1 and 5000 then
    raise exception 'Isi wajib diisi (maksimal 5000 karakter)' using errcode = '22023';
  end if;
  if (p_audiens = 'semua' and (p_target_rt_id is not null or p_target_peran is not null))
     or (p_audiens = 'rt' and (p_target_rt_id is null or p_target_peran is not null))
     or (p_audiens = 'peran' and (p_target_rt_id is not null or p_target_peran is null)) then
    raise exception 'Target tidak sesuai dengan audiens' using errcode = '22023';
  end if;
  if v_author_role = 'pengurus_rt'
     and (p_audiens <> 'rt' or p_target_rt_id is distinct from v_author_rt) then
    raise exception 'Pengurus RT hanya dapat mengirim ke RT sendiri' using errcode = '42501';
  end if;

  insert into public.pengumuman (
    penulis_id, jenis, audiens, target_rt_id, target_peran, judul, isi
  ) values (
    p_author_id, p_jenis, p_audiens, p_target_rt_id, p_target_peran,
    btrim(p_judul), btrim(p_isi)
  ) returning id into v_announcement_id;

  insert into public.pengumuman_penerima (pengumuman_id, profile_id)
  select v_announcement_id, p.id
  from public.profiles p
  where p.verification_status = 'terverifikasi'
    and p.consented_at is not null
    and (
      p_audiens = 'semua'
      or (p_audiens = 'rt' and p.rt_id = p_target_rt_id)
      or (p_audiens = 'peran' and p.role = p_target_peran)
    );
  get diagnostics v_recipient_count = row_count;
  if v_recipient_count = 0 then
    raise exception 'Tidak ada akun terverifikasi pada target tersebut' using errcode = 'P0001';
  end if;

  update public.pengumuman p
  set terkirim_at = v_sent_at
  where p.id = v_announcement_id;

  return query select v_announcement_id, v_recipient_count, v_sent_at;
end;
$$;
revoke all on function public.publish_pengumuman(
  uuid, public.jenis_pengumuman, public.audiens_pengumuman,
  uuid, public.peran_pengguna, text, text
) from public, anon, authenticated;
grant execute on function public.publish_pengumuman(
  uuid, public.jenis_pengumuman, public.audiens_pengumuman,
  uuid, public.peran_pengguna, text, text
) to service_role;

-- Realtime in-app untuk inbox penerima dan pembaruan status sudah dibaca.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pengumuman'
  ) then
    alter publication supabase_realtime add table public.pengumuman;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pengumuman_penerima'
  ) then
    alter publication supabase_realtime add table public.pengumuman_penerima;
  end if;
end;
$$;
