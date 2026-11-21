-- ============================================================
-- Pos-El — Skema Supabase (PostgreSQL)
-- Cara pakai: buka dashboard Supabase proyek
-- https://ubuqxmxkseoslxzruugr.supabase.co
-- lalu SQL Editor → New query → tempel seluruh file ini → Run.
-- Setelah itu JANGAN LUPA dua langkah di bawah:
--   1. Authentication → Settings → matikan "Confirm email"
--      (akun Pos-El memakai email buatan username@pos-el.local,
--       jadi email konfirmasi tidak akan pernah sampai).
--   2. Settings → API → salin "anon public key", tempel di
--      aplikasi Pos-El → Pengaturan Supabase.
-- ============================================================

-- ---------- Tabel profil (1 baris per akun) ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  display_name text not null,
  pin text not null unique,
  status_text text not null default '',
  last_seen timestamptz,
  created_at timestamptz not null default now(),
  constraint profiles_username_chk check (username ~ '^[a-z0-9._]{3,20}$'),
  constraint profiles_pin_chk check (pin ~ '^[0-9A-F]{8}$')
);
create index if not exists profiles_pin_idx on public.profiles (pin);

-- ---------- Tabel kontak / undangan pertemanan ----------
create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint contacts_pair_uniq unique (requester_id, addressee_id),
  constraint contacts_self_chk check (requester_id <> addressee_id)
);

-- ---------- Tabel grup ----------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- ---------- Tabel pesan (teks + ping + broadcast) ----------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid references public.profiles (id) on delete cascade,
  group_id uuid references public.groups (id) on delete cascade,
  kind text not null default 'text' check (kind in ('text', 'ping')),
  body text not null default '',
  is_broadcast boolean not null default false,
  status text not null default 'sent' check (status in ('sent', 'delivered', 'read')),
  created_at timestamptz not null default now(),
  constraint messages_target_chk check (
    (recipient_id is not null and group_id is null)
    or (recipient_id is null and group_id is not null)
  )
);
create index if not exists messages_recipient_idx on public.messages (recipient_id, created_at);
create index if not exists messages_sender_idx on public.messages (sender_id, created_at);
create index if not exists messages_group_idx on public.messages (group_id, created_at);

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.profiles enable row level security;
alter table public.contacts enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.messages enable row level security;

-- Profil: semua user login boleh membaca profil (perlu untuk cari PIN);
-- hanya boleh tulis barisnya sendiri.
drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all" on public.profiles
  for select to authenticated using (true);
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Kontak: hanya kedua belah pihak yang boleh melihat/mengubah.
drop policy if exists "contacts_party" on public.contacts;
create policy "contacts_party" on public.contacts
  for all to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid())
  with check (requester_id = auth.uid() or addressee_id = auth.uid());

-- Grup: pembuat boleh membuat; anggota boleh membaca.
drop policy if exists "groups_insert_creator" on public.groups;
create policy "groups_insert_creator" on public.groups
  for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "groups_select_member" on public.groups;
create policy "groups_select_member" on public.groups
  for select to authenticated using (
    created_by = auth.uid()
    or exists (select 1 from public.group_members m where m.group_id = groups.id and m.user_id = auth.uid())
  );

-- Anggota grup: anggota/pembuat boleh membaca; pembuat boleh menambah.
drop policy if exists "group_members_select" on public.group_members;
create policy "group_members_select" on public.group_members
  for select to authenticated using (
    user_id = auth.uid()
    or exists (select 1 from public.groups g where g.id = group_members.group_id and g.created_by = auth.uid())
  );
drop policy if exists "group_members_insert" on public.group_members;
create policy "group_members_insert" on public.group_members
  for insert to authenticated with check (
    user_id = auth.uid()
    or exists (select 1 from public.groups g where g.id = group_members.group_id and g.created_by = auth.uid())
  );

-- Pesan: pengirim & penerima (atau anggota grup) boleh membaca.
-- Kirim: hanya sebagai diri sendiri. Ubah status: hanya penerima
-- (atau anggota grup untuk pesan grup).
drop policy if exists "messages_select_party" on public.messages;
create policy "messages_select_party" on public.messages
  for select to authenticated using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.group_members m where m.group_id = messages.group_id and m.user_id = auth.uid()))
  );
drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_own" on public.messages
  for insert to authenticated with check (sender_id = auth.uid());
drop policy if exists "messages_update_recipient" on public.messages;
create policy "messages_update_recipient" on public.messages
  for update to authenticated using (
    recipient_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.group_members m where m.group_id = messages.group_id and m.user_id = auth.uid()))
  ) with check (
    recipient_id = auth.uid()
    or (group_id is not null and exists (
      select 1 from public.group_members m where m.group_id = messages.group_id and m.user_id = auth.uid()))
  );

-- ============================================================
-- Realtime: izinkan Postgres mengirim perubahan tabel ini
-- ke client yang berlangganan (pesan & undangan langsung masuk).
-- ============================================================
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.contacts;
alter publication supabase_realtime add table public.profiles;
