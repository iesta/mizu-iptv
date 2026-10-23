# Reproduire la base Zen sur ton propre Supabase

Objectif : avoir **ta** base (schéma + données), pour que le client Linux
continue de fonctionner si le service d'origine disparaît, ou pour self-héberger.

## Ce qui est certain, ce qui est supposé

| Élément | Statut |
|---|---|
| Nom des 7 tables | **observé** (sondage PostgREST, `42P01` = inexistante) |
| Colonnes listées dans `schema.sql` | **observé** (chaque colonne validée par `select=…`) |
| Type des colonnes | **déduit** des valeurs réelles (UUID, texte, entiers, timestamptz) |
| Clé primaire `serie_progress (watch_profile_id, serie_id)` | **prouvé** : un `upsert onConflict` a réussi, or PostgREST refuse sans contrainte unique |
| Autres clés primaires | supposées (composites, dédupliquées par les colonnes observées) |
| RPC `favorites_apply_order(p_content_ids, p_content_type, p_watch_profile_id)` | **signature exacte** obtenue via l'erreur PostgREST de l'instance d'origine |
| Politiques RLS | réécrites à l'identique en intention (propriétaire), non inspectables |
| Triggers, index, buckets Storage | inconnus — non utilisés par le client Linux |

## Mise en route

1. **Créer un projet** sur <https://supabase.com> (ou self-host).
2. **SQL Editor** → coller `schema.sql` → exécuter.
3. **Authentication** : activer *Email* (et Apple/Google si tu veux, avec tes
   propres identifiants OAuth — ceux de Zen ne fonctionneront pas).
4. **Créer ton utilisateur** (via l'écran d'inscription du client Linux, ou
   *Authentication → Users*).
5. **Importer tes données** :

   ```bash
   cd re/supabase
   python3 export-data.py --out seed.sql          # mots de passe des sources vidés
   python3 export-data.py --out seed.sql --with-credentials   # tout, fichier sensible
   ```

   Puis exécuter `seed.sql` dans le SQL Editor. Les UUID de profils et de
   sources sont conservés : favoris et progression restent rattachés.

6. **Pointer le client** sur ton instance :

   ```bash
   mkdir -p ~/.config/zeniptv
   cat > ~/.config/zeniptv/config.json <<'JSON'
   {
     "backend_url": "https://TON-PROJET.supabase.co",
     "publishable_key": "sb_publishable_...",
     "tmdb_api_key": "..."
   }
   JSON
   ```

   (ou `ZEN_BACKEND_URL` / `ZEN_PUBLISHABLE_KEY` en variables d'environnement)

7. Relancer l'app, se connecter avec le compte créé à l'étape 4.

## Ce que ça ne fait pas

- **L'app Zen officielle ne peut pas être redirigée** : son URL et sa clé sont
  compilées dans le binaire. Elle continuera de parler à `api.zeniptv.app`.
  Cette reproduction sert à **notre** client (et à sauvegarder tes données).
- Pas d'Edge Functions (`qr_auth`, paywall), pas de RevenueCat : ce sont des
  briques propriétaires qui ne sont pas nécessaires au fonctionnement du client.
- Pas de Storage : le client utilise les affiches du fournisseur et de TMDB.

## Légal

C'est **ton** compte et **tes** données. L'export est en lecture seule sur
l'instance d'origine. Ne redistribue ni les données, ni le schéma comme si
c'était le leur : `schema.sql` est une reconstruction par observation, pas une
copie d'un fichier qui t'aurait été fourni.
