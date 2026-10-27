-- Schéma de synchronisation Zen IPTV, reconstruit par observation.
--
-- Source : instance https://api.zeniptv.app (Supabase), app Zen IPTV 2.0.4.
-- Les colonnes marquées « observé » ont été confirmées sur l'instance réelle
-- (lecture de lignes + sondage PostgREST). Les contraintes marquées « supposé »
-- sont des hypothèses cohérentes avec le comportement de l'app.
--
-- À exécuter sur TON projet Supabase :
--   * SQL Editor (copier/coller), ou
--   * `supabase db push` via re/supabase/setup.sh (migrations)
--
-- Le script est idempotent : il peut être rejoué (drop policy if exists,
-- create or replace, create ... if not exists).

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Profils de visionnage
-- ---------------------------------------------------------------------------
create table if not exists public.watch_profiles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null,
  color      bigint              -- ARGB 32 bits (ex. 4290622207), observé
);

create index if not exists watch_profiles_user_idx on public.watch_profiles (user_id);

-- ---------------------------------------------------------------------------
-- Préférences (une ligne par utilisateur)
-- ---------------------------------------------------------------------------
create table if not exists public.user_preferences (
  user_id                    uuid primary key references auth.users (id) on delete cascade,
  show_ended_movies          boolean not null default false,
  playlist_refresh_rate_days integer not null default 1,
  ms_prot_other_apps         boolean not null default false
);

-- ---------------------------------------------------------------------------
-- Sources (Xtream / M3U) — identifiants stockés en clair, comme chez Zen
-- ---------------------------------------------------------------------------
create table if not exists public.playlist_sources (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users (id) on delete cascade,
  name                      text not null,
  "runtimeType"             text not null default 'xtream'
                              check ("runtimeType" in ('xtream', 'm3u')),
  host                      text,             -- xtream
  url                       text,             -- m3u
  username                  text,
  password                  text,
  epg_url                   text,
  color                     bigint,
  group_channels_categories boolean not null default true
);

create index if not exists playlist_sources_user_idx on public.playlist_sources (user_id);

-- ---------------------------------------------------------------------------
-- Favoris (par profil)
-- content_id = id TMDB pour vod/serie, nom de chaîne pour channel (observé)
-- ---------------------------------------------------------------------------
create table if not exists public.favorites (
  watch_profile_id uuid not null references public.watch_profiles (id) on delete cascade,
  content_id       text not null,
  content_type     text not null check (content_type in ('channel', 'vod', 'serie')),
  sort_order       integer not null default 0,
  added_at         timestamptz not null default now(),
  primary key (watch_profile_id, content_id, content_type)
);

-- ---------------------------------------------------------------------------
-- Progression (séries, et films si le client écrit runtimeType = 'vod')
-- ---------------------------------------------------------------------------
create table if not exists public.serie_progress (
  watch_profile_id     uuid not null references public.watch_profiles (id) on delete cascade,
  serie_id             text not null,      -- id TMDB (numerique) ou slug
  season_number        integer not null default 0,
  episode_number       integer not null default 0,
  watch_time           integer not null default 0,   -- secondes
  watch_progress       double precision not null default 0, -- 0..1
  last_watched         timestamptz not null default now(),
  all_episodes_watched boolean not null default false,
  "runtimeType"        text not null default 'serie',
  version_id           bigint,
  primary key (watch_profile_id, serie_id)
);

create index if not exists serie_progress_recent_idx
  on public.serie_progress (watch_profile_id, last_watched desc);

-- ---------------------------------------------------------------------------
-- Catégories masquées (par profil et par source)
-- ---------------------------------------------------------------------------
create table if not exists public.masked_categories (
  watch_profile_id uuid not null references public.watch_profiles (id) on delete cascade,
  category_id      text not null,
  category_type    text not null,
  source_id        uuid not null references public.playlist_sources (id) on delete cascade,
  primary key (watch_profile_id, category_id, category_type)
);

-- ---------------------------------------------------------------------------
-- Remappage TMDB manuel (colonnes observées ; clé primaire supposée)
-- ---------------------------------------------------------------------------
create table if not exists public.tmdb_mappings (
  source_id       uuid not null references public.playlist_sources (id) on delete cascade,
  content_type    text not null,
  mapped_tmdb_id  text not null,
  primary key (source_id, content_type, mapped_tmdb_id)
);

-- ---------------------------------------------------------------------------
-- RLS : chaque utilisateur ne voit que ses données
-- ---------------------------------------------------------------------------
alter table public.watch_profiles      enable row level security;
alter table public.user_preferences    enable row level security;
alter table public.playlist_sources    enable row level security;
alter table public.favorites           enable row level security;
alter table public.serie_progress      enable row level security;
alter table public.masked_categories   enable row level security;
alter table public.tmdb_mappings       enable row level security;

-- Profils
drop policy if exists "profils: proprietaire" on public.watch_profiles;
create policy "profils: proprietaire" on public.watch_profiles
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Préférences
drop policy if exists "prefs: proprietaire" on public.user_preferences;
create policy "prefs: proprietaire" on public.user_preferences
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Sources
drop policy if exists "sources: proprietaire" on public.playlist_sources;
create policy "sources: proprietaire" on public.playlist_sources
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Favoris / progression / catégories masquées : via le profil
drop policy if exists "favoris: via profil" on public.favorites;
create policy "favoris: via profil" on public.favorites
  for all to authenticated
  using (exists (select 1 from public.watch_profiles p
                 where p.id = favorites.watch_profile_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.watch_profiles p
                 where p.id = favorites.watch_profile_id and p.user_id = auth.uid()));

drop policy if exists "progression: via profil" on public.serie_progress;
create policy "progression: via profil" on public.serie_progress
  for all to authenticated
  using (exists (select 1 from public.watch_profiles p
                 where p.id = serie_progress.watch_profile_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.watch_profiles p
                 where p.id = serie_progress.watch_profile_id and p.user_id = auth.uid()));

drop policy if exists "categories masquees: via profil" on public.masked_categories;
create policy "categories masquees: via profil" on public.masked_categories
  for all to authenticated
  using (exists (select 1 from public.watch_profiles p
                 where p.id = masked_categories.watch_profile_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.watch_profiles p
                 where p.id = masked_categories.watch_profile_id and p.user_id = auth.uid()));

-- Remappages : via la source
drop policy if exists "tmdb: via source" on public.tmdb_mappings;
create policy "tmdb: via source" on public.tmdb_mappings
  for all to authenticated
  using (exists (select 1 from public.playlist_sources s
                 where s.id = tmdb_mappings.source_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.playlist_sources s
                 where s.id = tmdb_mappings.source_id and s.user_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- RPC observée sur l'instance d'origine :
--   favorites_apply_order(p_content_ids, p_content_type, p_watch_profile_id)
-- Réordonne les favoris d'un profil selon l'ordre du tableau.
-- ---------------------------------------------------------------------------
create or replace function public.favorites_apply_order(
  p_content_ids      text[],
  p_content_type     text,
  p_watch_profile_id uuid
) returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.watch_profiles
     where id = p_watch_profile_id and user_id = auth.uid()
  ) then
    raise exception 'profil inconnu ou non autorisé';
  end if;

  update public.favorites f
     set sort_order = ord.idx - 1
    from unnest(p_content_ids) with ordinality as ord(content_id, idx)
   where f.watch_profile_id = p_watch_profile_id
     and f.content_type = p_content_type
     and f.content_id = ord.content_id;
end;
$$;

revoke all on function public.favorites_apply_order(text[], text, uuid) from public;
grant execute on function public.favorites_apply_order(text[], text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Confort : créer les préférences à l'inscription
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Realtime (optionnel) : l'instance d'origine ne publie pas ces tables.
-- À décommenter si tu veux la synchro instantanée entre appareils.
-- ---------------------------------------------------------------------------
-- alter publication supabase_realtime add table
--   public.favorites, public.serie_progress, public.watch_profiles,
--   public.playlist_sources, public.user_preferences;
