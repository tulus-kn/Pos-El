#!/usr/bin/env python3
"""Pos-El v3.5 patch: privasi PIN, join grup, urutan pesan."""
import sys

def rep(text, old, new, tag):
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"[{tag}] expected 1 match, got {n}")
    return text.replace(old, new)

# ---------------- index.html ----------------
html = open("index.html", encoding="utf-8").read()

html = rep(html,
'''      const cek = await sb.from("posel_profiles").select("id").eq("pin", pin).limit(1);
      if (!cek.data || cek.data.length === 0) break;''',
'''      const { data: cek, error: errCek } = await sb.rpc("posel_cari_pin", { p_pin: pin });
      if (errCek) throw new Error("Cek PIN gagal (" + errCek.message + "). Jalankan ulang supabase/schema.sql versi v3.5.");
      if (!cek || cek.length === 0) break;''',
"cek-pin")

html = rep(html,
'''      const { data: t } = await sb.from("posel_profiles").select("id,display_name").eq("pin", pin).single();
      if (!t) { out.textContent = "PIN tidak ditemukan."; return; }''',
'''      const { data: rows, error: errPin } = await sb.rpc("posel_cari_pin", { p_pin: pin });
      if (errPin) throw new Error("Pencarian PIN gagal (" + errPin.message + "). Jalankan ulang supabase/schema.sql versi v3.5.");
      const t = rows && rows[0];
      if (!t) { out.textContent = "PIN tidak ditemukan."; return; }''',
"cari-pin")

html = rep(html,
'''    let q = sb.from("posel_messages").select("*").order("created_at", { ascending: true }).limit(100);''',
'''    let q = sb.from("posel_messages").select("*").order("created_at", { ascending: false }).limit(100);''',
"msg-order")

html = rep(html,
'''    const { data } = await q;
    return data || [];
  }
  const db = dbLokal();''',
'''    const { data } = await q;
    return (data || []).slice().reverse();
  }
  const db = dbLokal();''',
"msg-reverse")

html = rep(html,
'''Pos-El v3.4 (tabel Supabase ber-prefix posel_)''',
'''Pos-El v3.5 (tabel Supabase ber-prefix posel_)''',
"html-version")

open("index.html", "w", encoding="utf-8").write(html)
print("index.html patched")

# ---------------- schema.sql ----------------
sql = open("supabase/schema.sql", encoding="utf-8").read()

sql = rep(sql,
'''drop policy if exists "posel_profiles_select_all" on public.posel_profiles;
create policy "posel_profiles_select_all" on public.posel_profiles
  for select to authenticated using (true);''',
'''drop policy if exists "posel_profiles_select_all" on public.posel_profiles;
drop policy if exists "posel_profiles_select_self_or_contact" on public.posel_profiles;
create policy "posel_profiles_select_self_or_contact" on public.posel_profiles
  for select to authenticated using (
    id = auth.uid()
    or exists (
      select 1 from public.posel_contacts c
      where (c.requester_id = auth.uid() and c.addressee_id = posel_profiles.id)
         or (c.addressee_id = auth.uid() and c.requester_id = posel_profiles.id)
    )
  );''',
"profiles-select")

sql = rep(sql,
'''drop policy if exists "posel_group_members_insert" on public.posel_group_members;
create policy "posel_group_members_insert" on public.posel_group_members
  for insert to authenticated with check (
    user_id = auth.uid()
    or exists (select 1 from public.posel_groups g where g.id = posel_group_members.group_id and g.created_by = auth.uid())
  );''',
'''drop policy if exists "posel_group_members_insert" on public.posel_group_members;
create policy "posel_group_members_insert" on public.posel_group_members
  for insert to authenticated with check (
    exists (
      select 1 from public.posel_groups g
      where g.id = posel_group_members.group_id and g.created_by = auth.uid()
    )
    and (
      user_id = auth.uid()
      or exists (
        select 1 from public.posel_contacts c
        where c.status = 'accepted'
          and ((c.requester_id = auth.uid() and c.addressee_id = posel_group_members.user_id)
            or (c.addressee_id = auth.uid() and c.requester_id = posel_group_members.user_id))
      )
    )
  );''',
"group-insert")

sql = rep(sql,
'''-- Profil: semua user login boleh membaca profil (perlu untuk cari PIN);
-- hanya boleh tulis barisnya sendiri.''',
'''-- Profil: hanya baris sendiri + profil kontak (v3.5). Pencarian PIN
-- lewat fungsi posel_cari_pin. Hanya boleh tulis barisnya sendiri.''',
"profiles-comment")

sql = rep(sql,
'''create index if not exists posel_profiles_pin_idx on public.posel_profiles (pin);''',
'''create index if not exists posel_profiles_pin_idx on public.posel_profiles (pin);

-- ---------- RPC cari akun lewat PIN (v3.5) ----------
-- Sejak v3.5, tabel posel_profiles TIDAK lagi bisa dibaca semua user:
-- hanya baris sendiri + kontak. Pencarian PIN (daftar & tambah teman)
-- lewat fungsi ini yang hanya mengembalikan id + display_name (tanpa PIN).
create or replace function public.posel_cari_pin(p_pin text)
returns table (id uuid, display_name text)
language sql
security definer
set search_path = public, pg_temp
as $fn$
  select p.id, p.display_name
  from public.posel_profiles p
  where p.pin = upper(btrim(p_pin))
  limit 1;
$fn$;
revoke all on function public.posel_cari_pin(text) from public;
grant execute on function public.posel_cari_pin(text) to authenticated;''',
"rpc")

sql = rep(sql,
'''-- Pos-El — Skema Supabase (PostgreSQL) v3.1''',
'''-- Pos-El — Skema Supabase (PostgreSQL) v3.5''',
"sql-title")

sql = rep(sql,
'''-- ============================================================

-- ---------- Tabel profil (1 baris per akun) ----------''',
'''--
-- PERBAIKAN v3.5 (2026-11-21):
--   * posel_profiles hanya bisa dibaca baris sendiri + kontak
--     (sebelumnya semua user bisa membaca PIN semua orang).
--     Pencarian PIN dialihkan ke fungsi posel_cari_pin(p_pin).
--   * posel_group_members hanya bisa ditambah oleh pembuat grup,
--     dan hanya untuk dirinya sendiri atau kontaknya (sebelumnya
--     siapa pun bisa self-join grup mana saja).
-- ============================================================

-- ---------- Tabel profil (1 baris per akun) ----------''',
"sql-note")

open("supabase/schema.sql", "w", encoding="utf-8").write(sql)
print("schema.sql patched")

# ---------------- README.md ----------------
rd = open("README.md", encoding="utf-8").read()

rd = rep(rd,
'''## Perubahan v3.4 (2026-11-21) — Desain BBM gradient + ikon baru''',
'''## Perubahan v3.5 (2026-11-21) — Privasi PIN, join grup, urutan pesan
- **PIN tidak lagi terbaca semua orang.** Policy `posel_profiles` diganti:
  tiap user hanya bisa membaca baris profilnya sendiri dan profil kontaknya.
  Pencarian akun lewat PIN kini memakai fungsi `posel_cari_pin(p_pin)`
  (SECURITY DEFINER) yang hanya mengembalikan `id` + `display_name`, tanpa
  membocorkan PIN siapa pun.
- **Tidak bisa lagi self-join grup.** `posel_group_members` hanya bisa
  ditambah oleh pembuat grup, dan hanya untuk dirinya atau kontak yang
  sudah `accepted`. Sebelumnya siapa pun yang tahu `group_id` bisa ikut
  grup mana saja lalu membaca pesan grupnya.
- **Pesan terbaru tidak lagi hilang.** `ambilPesan()` sekarang mengambil
  100 pesan **terbaru** (`order created_at desc limit 100`, lalu di-reverse
  untuk tampilan) — versi lama mengambil 100 pesan tertua sehingga chat
  baru tidak pernah muncul setelah lewat 100 pesan.
- **Wajib migrasi:** jalankan ulang `supabase/schema.sql` versi v3.5 di
  SQL Editor (aman diulang, tanpa DROP TABLE), lalu deploy ulang
  `index.html`. Tanpa migrasi, daftar & tambah teman akan menampilkan
  "Pencarian PIN gagal … jalankan ulang schema.sql versi v3.5".

## Perubahan v3.4 (2026-11-21) — Desain BBM gradient + ikon baru''',
"readme")

open("README.md", "w", encoding="utf-8").write(rd)
print("README.md patched")
