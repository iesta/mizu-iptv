import 'dart:convert';
import 'dart:io';

/// Configuration du backend.
///
/// Par défaut : l'instance utilisée par l'app Zen d'origine. Peut être
/// remplacée par ta propre instance Supabase (voir `re/supabase/`) via
/// `~/.config/mizu/config.json` :
///
/// ```json
/// {
///   "backend_url": "https://mon-projet.supabase.co",
///   "publishable_key": "sb_publishable_...",
///   "tmdb_api_key": "..."
/// }
/// ```
///
/// ou par les variables d'environnement `MIZU_BACKEND_URL` /
/// `MIZU_PUBLISHABLE_KEY`.
class MizuConfig {
  static const String defaultBackendUrl = 'https://api.zeniptv.app';
  static const String defaultPublishableKey =
      'sb_publishable_FHN4ODlO5E4bt0ezliSoqQ_3CgYEyQs';

  static String backendUrl = defaultBackendUrl;
  static String publishableKey = defaultPublishableKey;

  static String get _home => Platform.environment['HOME'] ?? '.';

  static File get configFile => File('$_home/.config/mizu/config.json');

  /// Lit la configuration (fichier puis variables d'environnement).
  /// À appeler avant `Supabase.initialize`.
  static void init() {
    try {
      if (configFile.existsSync()) {
        final data = jsonDecode(configFile.readAsStringSync());
        if (data is Map) {
          final url = data['backend_url']?.toString().trim();
          final key = data['publishable_key']?.toString().trim();
          if (url != null && url.isNotEmpty) backendUrl = url;
          if (key != null && key.isNotEmpty) publishableKey = key;
        }
      }
    } catch (_) {
      // Configuration illisible : on garde les valeurs par défaut.
    }
    final envUrl = Platform.environment['MIZU_BACKEND_URL']?.trim();
    final envKey = Platform.environment['MIZU_PUBLISHABLE_KEY']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) backendUrl = envUrl;
    if (envKey != null && envKey.isNotEmpty) publishableKey = envKey;
  }

  static const String tWatchProfiles = 'watch_profiles';
  static const String tFavorites = 'favorites';
  static const String tSerieProgress = 'serie_progress';
  static const String tPlaylistSources = 'playlist_sources';
  static const String tMaskedCategories = 'masked_categories';
  static const String tUserPreferences = 'user_preferences';
  static const String tTmdbMappings = 'tmdb_mappings';
}
