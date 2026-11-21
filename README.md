# Pos-El — Pesan Jadul ala BBM

Aplikasi chat gaya BBM: daftar pakai username + password (tanpa email, tanpa
nomor HP), tiap akun dapat **PIN 8 karakter**, tambah teman pakai PIN, chat
1-1 dengan centang terkirim → D → R, tombol **PING!** (HP penerima bergetar +
bunyi + banner merah), grup, broadcast, dan status Kabar.

Live: https://tulus-kn.github.io/Pos-El/

## Perubahan v3.3 (2026-11-21) — Tema BBM Jadul (hijau gelap)
- Tampilan dirombak jadi tema BBM Jadul kiriman user: body gelap `#222222`,
  container `#2c2c2c` (lebar maks 430px), header hijau `#009929`, avatar hijau,
  bubble pesan kirim hijau `#009929` (radius 10px 10px 2px 10px), bubble pesan
  terima abu-abu gelap `#444444`, input dan tombol hijau `#009929`, tombol
  sekunder abu-abu `#555555`, tab aktif hijau. Tombol PING! tetap merah
  mencolok. Titik online `.ping-bbm` 11px hijau beranimasi `pingGetar`
  (scale 0.75 → 1.7, 1.2 detik), titik offline `.ping-off` abu-abu `#777777`.
  Logika tidak berubah: auth, PIN, chat, Ping, grup, broadcast, Kabar,
  online indicator, dan tabel `posel_*` tetap sama seperti v3.1/v3.2.

## Perubahan v3.2 (2026-11-21) — UI ala BBM klasik + kunci bisa ditanam
- Tampilan dirombak jadi gaya BlackBerry Messenger klasik: header hitam,
  latar putih/abu-abu muda, avatar bulat, bubble pesan masuk putih/abu-abu,
  bubble pesan sendiri biru muda, tab Chat/Kontak/Kabar/Saya dengan tab aktif
  hitam, tombol PING! merah mencolok, centang ✓ → D → R tetap jelas.
  Halaman login/daftar juga dirapikan dengan gaya yang sama.
  Logika tidak berubah: auth, PIN, chat, Ping, grup, broadcast, Kabar,
  online indicator, dan tabel `posel_*` tetap sama seperti v3.1.
- **Penanaman anon key (supaya orang lain tidak perlu tempel kunci):**
  di `index.html`, cari `const DEFAULT_ANON_KEY = "";` (di dekat
  `SUPABASE_URL`, sekitar baris 204) lalu isi di antara tanda kutip dengan
  **anon public key** dari Supabase (Settings → API → Publishable key,
  diawali `sb_publishable_` atau `eyJhbGciOi...`). JANGAN isi dengan
  Secret key (`sb_secret_...`). Kunci yang ditempel pengguna di Pengaturan
  Supabase (localStorage) selalu menang atas kunci bawaan ini. Kalau
  `DEFAULT_ANON_KEY` dibiarkan `""`, aplikasi tetap minta tempel kunci
  seperti v3.1. Setelah diisi, deploy ulang `index.html` (commit + push
  ke `main`, tunggu GitHub Pages) dan rebuild APK Pos-El.

## Cara menyambungkan ke Supabase (supaya sinkron antar HP)

Backend yang dipakai: Supabase proyek
`ubuqxmxkseoslxzruugr.supabase.co` (proyek yang sama dengan Andi Kore).

Lakukan 3 langkah ini sekali saja, dari browser HP/PC (buka
https://supabase.com/dashboard lalu pilih proyek itu):

### 1. Buat tabel — jalankan `supabase/schema.sql`
- Buka **SQL Editor** → **New query**.
- **Hapus isi query lama** (yang gagal dengan error `column "pin" does not exist`),
  lalu tempel seluruh isi file `supabase/schema.sql` **versi terbaru** di repo ini → **Run**.
- File ini membuat tabel `posel_profiles`, `posel_contacts`, `posel_groups`,
  `posel_group_members`, `posel_messages`, plus RLS dan Realtime.

> **Perbaikan v3.1 (2026-11-21):** versi sebelumnya memakai nama tabel polos
> (`profiles`, `contacts`, ...) dan gagal dijalankan karena tabel
> `public.profiles` sudah ada di proyek ini dari Andi Kore dengan struktur
> berbeda (tanpa kolom `pin`). Semua tabel Pos-El sekarang ber-prefix
> `posel_` dan tidak menyentuh tabel Andi Kore sama sekali. Kalau kamu
> sudah pernah menjalankan schema lama, tabel-tabel lamanya yang sempat
> terbentuk (mis. `contacts`, `groups`, `messages`) boleh dibiarkan —
> tidak dipakai dan tidak mengganggu.

### 2. Matikan konfirmasi email
- Buka **Authentication** → **Settings** → matikan **Confirm email**.
- Wajib, karena akun Pos-El memakai email buatan `username@pos-el.local`
  yang tidak bisa menerima email konfirmasi. Kalau ini masih aktif,
  pendaftaran akan gagal dengan pesan "email belum dikonfirmasi".

### 3. Tempel anon key di aplikasi
- Buka **Settings** → **API** → salin **anon public key**.
- Buka https://tulus-kn.github.io/Pos-El/ → bagian **Pengaturan Supabase**
  di layar masuk → tempel kunci → **Simpan Kunci**.
- Kunci ini tersimpan hanya di HP itu (localStorage). Kunci ini memang
  kunci publik; yang melindungi data adalah RLS di database, bukan kunci.

Kalau proyek Supabase sedang **paused** (free tier lama tidak dipakai),
dashboard akan menawarkannya untuk **Restore / Unpause** dulu. Itu juga
penyebab aplikasi menampilkan "Supabase tidak bisa dijangkau".

## Cara uji sinkron antar 2 HP
1. HP A dan HP B sama-sama buka Pos-El, daftar dengan username berbeda.
2. HP A buka **Profil (tab Saya)** → **Salin PIN**.
3. HP B buka **Kontak** → tempel PIN A → **Tambah** → HP A buka **Kontak**
   → **Terima** undangan.
4. Chat dari HP A → HP B langsung menerima (Realtime), centang berubah
   ✓ → D saat diterima → R saat chat dibuka.
5. Tekan **PING!** → HP B bergetar + bunyi + banner merah.

## Mode Lokal (kalau Supabase belum disiapkan)
Kalau anon key belum diisi, aplikasi menawarkan **Mode Lokal (demo)**:
akun, kontak, dan pesan hanya tersimpan di HP itu dan TIDAK sinkron.
Layar selalu menampilkan label "MODE LOKAL" supaya tidak tertukar
dengan mode cloud. Teman A/B/C di mode ini adalah akun demo untuk
mencoba chat dan Ping.

## Batas yang diketahui
- Pesan grup tidak punya centang D/R per anggota (status grup hanya
  "terkirim").
- Kehadiran online dihitung dari `last_seen` yang diperbarui tiap
  aplikasi dibuka / tiap 5 detik saat dipakai; kalau aplikasi ditutup,
  status jadi Offline setelah ~2 menit.
- Tanpa email, akun yang lupa password tidak bisa reset sendiri —
  reset harus lewat dashboard Supabase (Authentication → Users).
