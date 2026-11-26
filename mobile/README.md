# Wesbar — M0, M1 Panic Button, Broadcast, dan Tiket (Flutter)

Aplikasi berfokus pada RW 5; alamat warga ditautkan ke jalan, RT, dan RW 05. PB-01 mencakup pengelolaan nama dan alamat warga oleh pengurus RT di wilayahnya atau admin; perubahan dicatat tanpa menyalin nama/alamat ke detail audit. Migrasi `0013_profile_management.sql` menambahkan izin database dan audit untuk fitur ini, sedangkan `0014_rw5_scope.sql` menautkan seluruh RT ke RW 5. M0 mencakup autentikasi email/kata sandi, pendaftaran dengan persetujuan, dan verifikasi RT. M1 mencakup countdown 3 detik, mode latihan, pembuatan insiden, antrean lokal/retry, inbox penerima, respons, status penanganan, kontak darurat, Realtime in-app, dan eskalasi best-effort setelah 60 detik. Broadcast mencakup inbox, status baca, dan penerbitan langsung untuk pengurus RT/RW/admin. PB-05 memungkinkan warga membuat tiket fasilitas, keamanan, hewan, atau listrik dan melampirkan foto opsional. Notifikasi tetap in-app; FCM push ke aplikasi tertutup dan SMS belum tersedia. Flutter 3.47.9/Dart 3.13.7 tersedia di `D:\DevTools\flutter`; cache Flutter dan Pub diarahkan ke `D:\DevTools`; Android SDK belum terpasang.

Migrasi `0012_broadcast_publish.sql` sampai `0016_ticket_escalation_reason.sql` dan Edge Function `broadcast-publish` sudah diterapkan ke proyek Supabase demo tertaut; riwayat migrasi lokal dan remote cocok sampai `0016`. Jangan menaruh service-role key di aplikasi.

## Prasyarat

- Flutter SDK berada di `D:\\DevTools\\flutter`; Pub cache dan Temp berada di `D:\\DevTools`. Folder proyek, `.dart_tool`, dan build Web juga berada di drive `D:`. Platform Android/Web sudah digenerasikan. Android SDK belum terpasang.
- Migrasi `0001` s.d. `0014` sudah diterapkan ke proyek Supabase tertaut. Seed demo membuat RT `DEMO-01` di RW 5. Edge Function `panic-create` serta `broadcast-publish` sudah dideploy. Data dummy melalui `supabase/seed.sql`: RT `DEMO-01`, jalan `Jalan Contoh`, rumah `01`–`03`. Satu akun pengurus demo sudah diprovisikan menjadi `pengurus_rt/terverifikasi`; jangan simpan email/password akun tersebut di repository.
- Untuk uji end-to-end M1, buat akun warga kedua dengan email yang bisa Anda akses, daftarkan pada rumah `02`, lalu setujui dari akun pengurus. Setelah itu gunakan dua sesi/browser berbeda: warga untuk mengirim alert dan pengurus untuk menerima/mengubah status. Titik koordinat unit dummy masih null, sehingga RPC mengirim alert ke warga terverifikasi satu RT sebagai fallback radius.
- Jika konfirmasi email aktif di Supabase Auth, warga mengonfirmasi email sebelum bisa masuk dan mengisi profil. Batas pengiriman email paket gratis perlu dicek sebelum pilot.
- Form meminta persetujuan penggunaan email sebelum membuat akun dan persetujuan data warga saat mengisi profil. **Sebelum memakai data warga sungguhan**, problem owner perlu menyetujui kebijakan privasi yang menjelaskan pengelola, tujuan, akses, retensi, dan hak warga; teks singkat pada checkbox belum menggantikan kebijakan tersebut.

## Menjalankan

**Cara paling mudah di Windows:** klik dua kali `run_demo.bat` di folder `mobile/`. Skrip memakai `D:\\DevTools\\flutter` dan mengarahkan cache/temp ke `D:`; mengambil dependency bila belum ada, lalu membuka Chrome. Hentikan app dengan `Ctrl+C` pada jendela terminal. Skrip memuat Supabase URL dan publishable key proyek demo; key tersebut public client config, bukan rahasia admin. Jangan menggantinya dengan `service_role`. Variabel user `PUB_CACHE`, `TEMP`, dan `TMP` juga diarahkan ke `D:\\DevTools`; terminal/aplikasi yang sudah terbuka perlu dibuka ulang agar mewarisi nilai tersebut.

Alternatif manual dari `mobile/`: jalankan `D:\\DevTools\\flutter\\bin\\flutter.bat pub get`, lalu `D:\\DevTools\\flutter\\bin\\flutter.bat test`. Jalankan build Web dengan `D:\\DevTools\\flutter\\bin\\flutter.bat build web`. Untuk Android, pasang Android SDK terlebih dahulu; SDK belum tersedia pada mesin pengembangan ini.

Gunakan URL proyek dan **anon/publishable key** saja; nilai ini bukan `service_role` key. **Jangan pernah** menaruh `service_role` key di Flutter atau menyimpan kredensial pribadi dalam repository.

Alur demo: daftar akun warga kedua → konfirmasi email bila diminta → isi RT `DEMO-01`, jalan `Jalan Contoh`, rumah `02` → akun menunggu → pengurus menyetujui → warga keluar/masuk kembali. Warga lalu mencoba countdown Panic Button dalam mode latihan terlebih dahulu; matikan mode latihan untuk membuat insiden nyata pada project demo. Pengurus membuka **Insiden darurat** untuk merespons, menandai ditangani, lalu selesai. Tunggu 60 detik tanpa memilih “Saya menuju” untuk menguji penanda eskalasi.

## Tiket warga (PB-05)

Warga terverifikasi membuka **Tiket layanan** dari layar Panic Button, melihat tiket miliknya, lalu membuat tiket dengan kategori dan deskripsi. Foto bukti bersifat opsional, maksimal 5 MB, dan format JPG/PNG/WebP; foto disimpan privat dan tautan tampil hanya untuk pelapor serta pengurus RT/RW sesuai wilayah. Tenggat respons/selesai tetap kosong bila aturan SLA untuk kategori, prioritas, dan level belum diisi; angka SLA tidak ditentukan oleh aplikasi.

Migrasi `0015_ticket_submission.sql` sudah aktif pada project demo. Saat ini tabel `sla_aturan` masih kosong, sehingga tenggat tiket akan `NULL` sampai aturan SLA disepakati dan diisi. Terapkan migrasi yang sama pada environment Supabase lain sebelum menguji PB-05 di sana.

## Penanganan tiket pengurus (PB-06)

Pengurus RT membuka **Kelola tiket layanan** dari dashboard verifikasi warga. Pengurus RW dan admin membuka **Kelola tiket wilayah** dari inbox insiden. Daftar mengikuti RLS Supabase; RT hanya mengelola tiket RT sendiri, sedangkan RW/admin mengelola tiket sesuai aksesnya. Status dikelola berurutan: `baru` → `ditugaskan` → `diproses` → `selesai` → `ditutup`. Pengurus RT dapat mengeskalasi tiket level RT ke RW dengan alasan wajib; alasan dan perubahan level dicatat otomatis di `tiket_riwayat`. Setelah eskalasi, perubahan dilanjutkan pengurus RW. Foto tetap memakai akses privat. PB-06 menetapkan respons awal maksimal dua hari kerja, tetapi tenggat belum dihitung karena kalender hari kerja/libur dan aturan operasional SLA belum disepakati; aplikasi tidak mengarang tenggat.

## Broadcast

Pengurus RT dapat mengirim pengumuman langsung ke RT sendiri. Pengurus RW dan admin dapat mengirim ke semua akun terverifikasi, satu RT, atau satu peran. Penerima membuka ikon **Pengumuman**, membaca detail, dan status baca dicatat; pengirim melihat tab **Terkirim**. Pengiriman langsung dibuat bersama daftar penerimanya oleh RPC tepercaya, bukan dari klien.

Untuk backend environment lain yang sudah tertaut, dari root proyek jalankan `supabase db push --linked`, lalu `supabase functions deploy broadcast-publish --use-api`. Jalankan migrasi dan deploy function sebelum mencoba fitur pada app. Fungsi memakai secret `SUPABASE_SERVICE_ROLE_KEY` di Edge Function Supabase; jangan pernah menyalinnya ke Flutter atau repository.

Notifikasi Panic Button dan Broadcast saat ini adalah **in-app Supabase Realtime**—penerima harus membuka aplikasi dan online. Tidak ada FCM push atau SMS. Eskalasi Edge Function menggunakan background task best-effort, bukan scheduler durable; jangan dipakai sebagai satu-satunya kanal keselamatan. Kontak belum diisi sehingga tombol telepon belum dapat diuji. Rate limit Panic Button adalah maksimal tiga alert per warga dalam lima menit. Offline retry menyimpan UUID permintaan dan jenis insiden saja di storage perangkat; retry berjalan saat aplikasi kembali online/aktif.
