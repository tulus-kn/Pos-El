-- ============================================================
-- Pos-El — Skema Supabase (PostgreSQL) v3.1
-- Cara pakai: buka dashboard Supabase proyek
-- https://ubuqxmxkseoslxzruugr.supabase.co
-- lalu SQL Editor → New query → HAPUS isi query lama → tempel
-- seluruh file ini → Run.
--
-- PERBAIKAN v3.1 (2026-11-21): semua tabel Pos-El memakai prefix
-- "posel_" (posel_profiles, posel_contacts, posel_groups,
-- posel_group_members, posel_messages). Versi sebelumnya memakai
-- nama polos (profiles, contacts, ...) dan GAGAL dengan
-- "ERROR 42703: column pin does not exist" karena tabel
-- public.profiles SUDAH ADA di proyek ini dari Andi Kore dengan
-- struktur berbeda (tanpa kolom pin), sehingga
-- CREATE TABLE IF NOT EXISTS dilewati dan pembuatan index atas
-- kolom pin gagal. Dengan prefix posel_, schema ini tidak
-- menyentuh tabel Andi Kore sama sekali.
--
-- File ini aman di-run ulang: tanpa DROP TABLE, semua CREATE
-- memakai IF NOT EXISTS, semua DROP POLICY memakai IF EXISTS,
-- dan penambahan ke publikasi Realtime dibungkus agar tidak
-- gagal kalau tabel sudah terdaftar.
--
-- Setelah itu JANGAN LUPA dua langkah di bawah:
--   1. Authentication → Settings → matikan "Confirm email"
--      (akun Pos-El memakai email buatan username@pos-el.local,
--       jadi email konfirmasi tidak akan pernah sampai).
--   2. Settings → API → salin "anon public key", tempel di
--      aplikasi Pos-El → Pengaturan Supabase.
-- ============================================================

-- ---------- Tabel profil (1 baris per akun) ----------
create table if not exists public.posel_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  display_name text not null,
  pin text not null unique,
  status_text text not null default '',
  last_seen timestamptz,
  created_at timestamptz not null default now(),
  constraint posel_profiles_username_chk check (username ~ '^[a-z0-9._]{3,20}$'),
  constraint posel_profiles_pin_chk check (pin ~ '^[0-9A-F]{8}$')
);
create index if not exists posel_profiles_pin_idx on public.posel_profiles (pin);

-- ---------- Tabel kontak / undangan pertemanan ----------
create table if not exists public.posel_contacts (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.posel_profiles (id) on delete cascade,
  addressee_id uuid not null references public.posel_profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint posel_contacts_pair_uniq unique (requester_id, addressee_id),
  constraint posel_contacts_self_chk check (requester_id <> addressee_id)
);

-- ---------- Tabel grup ----------
create table if not exists public.posel_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references public.posel_profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.posel_group_members (
  group_id uuid not null references public.posel_groups (id) on delete cascade,
  user_id uuid not null references public.posel_profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- ---------- Tabel pesan (teks + ping + broadcast) ----------
create table if not exists public.posel_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.posel_profiles (id) on delete cascade,
  recipient_id uuid references public.posel_profiles (id) on delete cascade,
  group_id uuid references public.posel_groups (id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'ping')),
  body text not null default '',
  is_broadcast boolean not null default false,
  status text not null default 'sent' check (status in ('sent', 'delivered', 'read')),
  created_at timestamptz not null default now(),
  constraint posel_messages_target_chk check (
    (recipient_id is not null and group_id is null)
    or (recipient_id is null and group_id is not null)
  )
);
create index if not exists posel_messages_recipient_idx on public.posel_messages (recipient_id, created_at);
create index if not exists posel_messages_sender_idx on public.posel_messages (sender_id, created_at);
create index if not exists posel_messages_group_idx on public.posel_messages (group_id, created_at);

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.posel_profiles enable row level security;
alter table public.posel_contacts enable row level security;
alter table public.posel_groups enable row level security;
alter table public.posel_group_members enable row level security;
alter table public.posel_messages enable row level security;

-- Profil: semua user login boleh membaca profil (perlu untuk cari PIN);
-- hanya boleh tulis barisnya sendiri.
drop policy if exists "posel_profiles_select_all" on public.posel_profiles;
create policy "posel_profiles_select_all" on public.posel_profiles
  for select to authenticated using (true);
drop policy if exists "posel_profiles_insert_own" on public.posel_profiles;
create policy "posel_profiles_insert_own" on public.posel_profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "posel_profiles_update_own" on public.posel_profiles;
create policy "posel_profiles_update_own" on public.posel_profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Kontak: hanya kedua belah pihak yang boleh melihat/mengubah.
drop policy if exists "posel_contacts_party" on public.posel_contacts;
create policy "posel_contacts_party" on public.posel_contacts
  for all to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid())
  with check (requester_id = auth.uid() or addressee_id = auth.uid());

-- Grup: pembuat boleh membuat; anggota boleh membaca.
drop policy if exists "posel_groups_insert_creator" on public.posel_groups;
create policy "posel_groups_insert_creator" on public.posel_groups
  for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "posel_groups_select_member" on public.posel_groups;
create policy "posel_groups_select_member" on public.posel_groups
  for select to authenticated using (
    created_by = auth.uid()
    or exists (select 1 from public.posel_group_members m where m.group_id = posel_groups.id and m.user_id = auth.uid())
  );

-- Anggota grup: anggota/pembuat boleh membaca; pembuat boleh menambah.
drop policy if exists "posel_group_members_select" on public.posel_group_members;
create policy "posel_group_members_select" on public.posel_group_members
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.posel_groups g where g.id = posel_group_members.group_id and g.created_by = auth.uid())
  );
drop policy if exists "posel_group_members_insert" on public.posel_group_members;
create policy "posel_group_members_insert" on public.posel_group_members
  for insert to authenticated with check (
    user_id = auth.uid()
    or exists (select 1 from public.posel_groups g where g.id = posel_group_members.group_id and g.created_by = auth.uid())
  );

-- Pesan: pengirim & penerima (atau anggota grup) boleh membaca.
-- Kirim: hanya sebagai diri sendiri. Ubah status: hanya penerima
-- (atau anggota grup untuk pesan grup).
drop policy if exists "posel_messages_select_party" on public.posel_messages;
create policy "posel_messages_select_party" on public.posel_messages
  for select to authenticated using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.posel_group_members m where m.group_id = posel_messages.group_id and m.user_id = auth.uid()))
  );
drop policy if exists "posel_messages_insert_own" on public.posel_messages;
create policy "posel_messages_insert_own" on public.posel_messages
  for insert to authenticated with check (sender_id = auth.uid());
drop policy if exists "posel_messages_update_recipient" on public.posel_messages;
create policy "posel_messages_update_recipient" on public.posel_messages
  for update to authenticated using (
    recipient_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.posel_group_members m where m.group_id = posel_messages.group_id and m.user_id = auth.uid()))
  ) with check (
    recipient_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.posel_group_members m where m.group_id = posel_messages.group_id and m.user_id = auth.uid()))
  );

-- ============================================================
-- Realtime: izinkan Postgres mengirim perubahan tabel ini
-- ke client yang berlangganan (pesan & undangan langsung masuk).
-- Dibungkus DO block supaya run ulang tidak gagal kalau tabel
-- sudah terdaftar di publikasi (duplicate_object).
-- ============================================================
do $$
begin
  alter publication supabase_realtime add table public.posel_messages;
exception when duplicate_object then
  null;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.posel_contacts;
exception when duplicate_object then
  null;
end
$$;
do $$
begin
  alter publication supabase_realtime add table public.posel_profiles;
exception when duplicate_object then
  null;
end
$$;
