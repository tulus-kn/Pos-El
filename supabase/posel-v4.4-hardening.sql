-- ============================================================
-- Pos-El v4.4 — HARDENING keamanan database (aman dijalankan ulang)
-- Jalankan di Supabase -> SQL Editor -> New query -> Run.
-- Urutan: jalankan SQL ini, lalu unggah index.html yang sudah dipatch.
--
-- Isi:
--  1. Kontak: undangan hanya bisa DITERIMA oleh penerima (sebelumnya
--     pengirim bisa membuat baris status 'accepted' sendiri).
--  2. Pesan: DM hanya ke kontak yang sudah diterima; hanya kolom
--     "status" yang boleh diubah; batas panjang isi; batas ping.
--  3. Story/profil: validasi warna, URL media/avatar, masa berlaku.
--  4. Storage: tiap pengguna hanya boleh menulis/membaca daftar
--     file di folder miliknya sendiri.
-- Semua CHECK dibuat NOT VALID: data lama tidak ditolak, hanya
-- baris baru/yang diubah yang divalidasi.
-- ============================================================

-- ---------- 1. KONTAK ----------
drop policy if exists "posel_contacts_party" on public.posel_contacts;
drop policy if exists "posel_contacts_select" on public.posel_contacts;
drop policy if exists "posel_contacts_insert" on public.posel_contacts;
drop policy if exists "posel_contacts_update_addressee" on public.posel_contacts;
drop policy if exists "posel_contacts_delete_party" on public.posel_contacts;

create policy "posel_contacts_select" on public.posel_contacts
  for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- Pengirim hanya boleh membuat undangan berstatus 'pending'.
create policy "posel_contacts_insert" on public.posel_contacts
  for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending');

-- Hanya PENERIMA yang boleh menerima undangan.
create policy "posel_contacts_update_addressee" on public.posel_contacts
  for update to authenticated
  using (addressee_id = auth.uid())
  with check (addressee_id = auth.uid() and status = 'accepted');

-- Kedua pihak boleh menolak / menghapus pertemanan.
create policy "posel_contacts_delete_party" on public.posel_contacts
  for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- Pasangan requester/addressee tidak boleh diubah setelah dibuat.
create or replace function public.posel_contacts_guard()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
begin
  if new.requester_id <> old.requester_id or new.addressee_id <> old.addressee_id then
    raise exception 'Pasangan kontak tidak boleh diubah';
  end if;
  return new;
end;
$fn$;
drop trigger if exists posel_contacts_guard_trg on public.posel_contacts;
create trigger posel_contacts_guard_trg
  before update on public.posel_contacts
  for each row execute function public.posel_contacts_guard();

-- ---------- 2. PESAN ----------
-- DM hanya boleh dikirim ke kontak yang sudah diterima.
drop policy if exists "posel_messages_insert_own" on public.posel_messages;
create policy "posel_messages_insert_own" on public.posel_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      (group_id is null and exists (
        select 1 from public.posel_contacts c
        where c.status = 'accepted'
          and ((c.requester_id = auth.uid() and c.addressee_id = posel_messages.recipient_id)
            or (c.addressee_id = auth.uid() and c.requester_id = posel_messages.recipient_id))
      ))
      or (group_id is not null and public.posel_is_group_member(group_id))
    )
  );

-- Policy UPDATE tidak bisa membatasi kolom. Tanpa ini, penerima (atau anggota
-- grup mana pun) bisa menulis ulang isi pesan dan pengirimnya. Aplikasi hanya
-- mengubah "status" (delivered/read), jadi cabut hak UPDATE lalu beri hanya
-- pada kolom itu.
revoke update on public.posel_messages from anon, authenticated;
grant update (status) on public.posel_messages to authenticated;

-- Batas panjang isi (foto dikirim sebagai data URI, jadi cukup longgar;
-- turunkan jika foto Anda kecil).
alter table public.posel_messages drop constraint if exists posel_messages_body_len_chk;
alter table public.posel_messages
  add constraint posel_messages_body_len_chk check (char_length(body) <= 3000000) not valid;

-- Batas ping: maks 20 per menit per pengirim (cegah spam notifikasi).
create or replace function public.posel_batasi_ping()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if new.kind = 'ping' and (
    select count(*) from public.posel_messages m
    where m.sender_id = new.sender_id and m.kind = 'ping'
      and m.created_at > now() - interval '1 minute'
  ) >= 20 then
    raise exception 'Terlalu banyak ping. Tunggu sebentar.';
  end if;
  return new;
end;
$fn$;
drop trigger if exists posel_batasi_ping_trg on public.posel_messages;
create trigger posel_batasi_ping_trg
  before insert on public.posel_messages
  for each row execute function public.posel_batasi_ping();

-- ---------- 3. PROFIL, GRUP, STORY ----------
alter table public.posel_profiles drop constraint if exists posel_profiles_nama_len_chk;
alter table public.posel_profiles
  add constraint posel_profiles_nama_len_chk check (char_length(display_name) between 1 and 60) not valid;

alter table public.posel_groups drop constraint if exists posel_groups_nama_len_chk;
alter table public.posel_groups
  add constraint posel_groups_nama_len_chk check (char_length(name) between 1 and 60) not valid;

do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'posel_profiles' and column_name = 'avatar_url') then
    alter table public.posel_profiles drop constraint if exists posel_profiles_avatar_chk;
    alter table public.posel_profiles
      add constraint posel_profiles_avatar_chk check (
        avatar_url is null or avatar_url = ''
        or avatar_url like 'https://ubuqxmxkseoslxzruugr.supabase.co/storage/v1/object/public/posel-media/%'
      ) not valid;
  end if;

  if to_regclass('public.posel_stories') is not null then
    alter table public.posel_stories drop constraint if exists posel_stories_warna_chk;
    alter table public.posel_stories
      add constraint posel_stories_warna_chk check (warna ~ '^#[0-9a-fA-F]{6}$') not valid;

    alter table public.posel_stories drop constraint if exists posel_stories_media_chk;
    alter table public.posel_stories
      add constraint posel_stories_media_chk check (
        media_url = ''
        or media_url like 'https://ubuqxmxkseoslxzruugr.supabase.co/storage/v1/object/public/posel-media/%'
      ) not valid;

    alter table public.posel_stories drop constraint if exists posel_stories_exp_chk;
    alter table public.posel_stories
      add constraint posel_stories_exp_chk check (expires_at <= created_at + interval '24 hours') not valid;

    -- Story kedaluwarsa tidak bisa dibaca lagi lewat API.
    drop policy if exists "posel_stories_select_kontak" on public.posel_stories;
    create policy "posel_stories_select_kontak" on public.posel_stories
      for select to authenticated
      using (
        expires_at > now()
        and (
          user_id = auth.uid()
          or exists (
            select 1 from public.posel_contacts c
            where c.status = 'accepted'
              and ((c.requester_id = auth.uid() and c.addressee_id = posel_stories.user_id)
                or (c.addressee_id = auth.uid() and c.requester_id = posel_stories.user_id))
          )
        )
      );
  end if;
end
$$;

-- ---------- 4. STORAGE (bucket posel-media) ----------
-- Pola path yang dipakai aplikasi:
--   <uid>/<nama-file>          (media chat)
--   stories/<uid>/<nama-file>  (story)
--   avatar/<uid>.jpg           (foto profil)
-- Sebelumnya SEMUA pengguna login boleh menulis/menimpa/MENDAFTAR semua file
-- di bucket (termasuk menimpa avatar orang lain).
create or replace function public.posel_media_milik(p_name text)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $fn$
  select
    split_part(p_name, '/', 1) = auth.uid()::text
    or (split_part(p_name, '/', 1) = 'stories' and split_part(p_name, '/', 2) = auth.uid()::text)
    or (split_part(p_name, '/', 1) = 'avatar' and split_part(p_name, '/', 2) like auth.uid()::text || '.%');
$fn$;
revoke all on function public.posel_media_milik(text) from public;
grant execute on function public.posel_media_milik(text) to authenticated;

drop policy if exists "posel_media_insert" on storage.objects;
drop policy if exists "posel_media_update" on storage.objects;
drop policy if exists "posel_media_select" on storage.objects;
drop policy if exists "posel_media_delete" on storage.objects;

create policy "posel_media_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'posel-media' and public.posel_media_milik(name));

create policy "posel_media_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'posel-media' and public.posel_media_milik(name))
  with check (bucket_id = 'posel-media' and public.posel_media_milik(name));

-- SELECT dipertahankan (upload dengan upsert:true membutuhkannya) tapi hanya
-- untuk file milik sendiri. Membuka URL publik file tetap berfungsi.
create policy "posel_media_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'posel-media' and public.posel_media_milik(name));

create policy "posel_media_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'posel-media' and public.posel_media_milik(name));

-- OPSIONAL (hapus tanda -- jika sesuai): batas ukuran / jenis file.
-- Hati-hati: unggahan dengan content-type kosong dikirim sebagai
-- application/octet-stream dan akan ditolak jika allowed_mime_types diisi.
-- update storage.buckets
--   set file_size_limit = 52428800  -- 50 MB
-- where id = 'posel-media';
