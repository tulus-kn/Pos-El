-- ============================================================
-- Pos-El v4.3.1 — STORY (teks / foto / video / voice note / MP3)
-- Jalankan sekali di Supabase -> SQL Editor.
-- ============================================================

alter table public.posel_profiles
  add column if not exists avatar_url text;

create table if not exists public.posel_stories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.posel_profiles (id) on delete cascade,
  kind        text not null check (kind in ('teks','foto','video','suara','musik')),
  teks        text not null default '',
  media_url   text not null default '',
  warna       text not null default '#0f86c9',
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default (now() + interval '24 hours')
);

create index if not exists posel_stories_exp_idx on public.posel_stories (expires_at desc);
create index if not exists posel_stories_user_idx on public.posel_stories (user_id, created_at);

alter table public.posel_stories enable row level security;

drop policy if exists "posel_stories_insert_own" on public.posel_stories;
create policy "posel_stories_insert_own" on public.posel_stories
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "posel_stories_delete_own" on public.posel_stories;
create policy "posel_stories_delete_own" on public.posel_stories
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists "posel_stories_select_kontak" on public.posel_stories;
create policy "posel_stories_select_kontak" on public.posel_stories
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.posel_contacts c
      where c.status = 'accepted'
        and ((c.requester_id = auth.uid() and c.addressee_id = user_id)
          or (c.addressee_id = auth.uid() and c.requester_id = user_id))
    )
  );

grant select, insert, delete on public.posel_stories to authenticated;

insert into storage.buckets (id, name, public)
values ('posel-media', 'posel-media', true)
on conflict (id) do update set public = true;

drop policy if exists "posel_media_insert" on storage.objects;
drop policy if exists "posel_media_update" on storage.objects;
drop policy if exists "posel_media_select" on storage.objects;

create policy "posel_media_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'posel-media');
create policy "posel_media_update" on storage.objects
  for update to authenticated using (bucket_id = 'posel-media') with check (bucket_id = 'posel-media');
create policy "posel_media_select" on storage.objects
  for select to authenticated using (bucket_id = 'posel-media');
