import 'dart:convert';
import 'dart:io';

import 'platform/app_dirs.dart';

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
  static String? tmdbApiKey;

  /// Vrai si l'utilisateur a explicitement configuré un backend.
  static bool get isCustomBackend =>
      backendUrl != defaultBackendUrl || publishableKey != defaultPublishableKey;

  static File get configFile => File('${AppDirs.configDir}/config.json');

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
          final tmdb = data['tmdb_api_key']?.toString().trim();
          if (tmdb != null && tmdb.isNotEmpty) tmdbApiKey = tmdb;
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

  /// Écrit la configuration. Les champs `null` conservent la valeur existante.
  /// Renvoie `true` si l'URL ou la clé du backend a changé (redémarrage requis).
  static Future<bool> save({
    String? backendUrl,
    String? publishableKey,
    String? tmdbApiKey,
  }) async {
    final before = (MizuConfig.backendUrl, MizuConfig.publishableKey);

    var data = <String, dynamic>{};
    try {
      if (configFile.existsSync()) {
        final decoded = jsonDecode(configFile.readAsStringSync());
        if (decoded is Map<String, dynamic>) data = decoded;
      }
    } catch (_) {
      data = {};
    }

    if (backendUrl != null && backendUrl.trim().isNotEmpty) {
      data['backend_url'] = backendUrl.trim();
      MizuConfig.backendUrl = backendUrl.trim();
    }
    if (publishableKey != null && publishableKey.trim().isNotEmpty) {
      data['publishable_key'] = publishableKey.trim();
      MizuConfig.publishableKey = publishableKey.trim();
    }
    if (tmdbApiKey != null) {
      if (tmdbApiKey.trim().isEmpty) {
        data.remove('tmdb_api_key');
        MizuConfig.tmdbApiKey = null;
      } else {
        data['tmdb_api_key'] = tmdbApiKey.trim();
        MizuConfig.tmdbApiKey = tmdbApiKey.trim();
      }
    }

    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    if (!Platform.isWindows) {
      // La clé n'est pas un secret critique, mais on limite la lecture.
      await Process.run('chmod', ['600', configFile.path]);
    }

    return before != (MizuConfig.backendUrl, MizuConfig.publishableKey);
  }

  static const String tWatchProfiles = 'watch_profiles';
  static const String tFavorites = 'favorites';
  static const String tSerieProgress = 'serie_progress';
  static const String tPlaylistSources = 'playlist_sources';
  static const String tMaskedCategories = 'masked_categories';
  static const String tUserPreferences = 'user_preferences';
  static const String tTmdbMappings = 'tmdb_mappings';
}
