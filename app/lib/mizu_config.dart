import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform/app_dirs.dart';

/// Configuration du backend Supabase.
///
/// **Aucune clé n'est embarquée dans le code.** L'application se configure :
///
/// 1. au premier lancement, via l'écran de configuration (URL + clé
///    publishable) ;
/// 2. ou par un fichier `.env` (à côté de l'exécutable, dans le répertoire
///    courant, ou dans `~/.config/mizu/.env`) ;
/// 3. ou par les variables d'environnement `MIZU_BACKEND_URL` /
///    `MIZU_PUBLISHABLE_KEY` ;
/// 4. ou par `~/.config/mizu/config.json` (écrit par l'écran de configuration).
///
/// Ordre de priorité : environnement > config.json > .env.
class MizuConfig {
  static String backendUrl = '';
  static String publishableKey = '';
  static String? tmdbApiKey;

  /// User-Agent par défaut des requêtes vers les panneaux IPTV.
  ///
  /// `package:http` enverrait `Dart/3.x (dart:io)`, que certains panneaux
  /// bloquent ou filtrent. Surchargeable (config.json / MIZU_USER_AGENT /
  /// Préférences) pour coller à ce qu'attend le fournisseur.
  static const String defaultUserAgent = 'MizuIPTV/1.0 (Flutter)';
  static String userAgent = defaultUserAgent;

  /// Ordre d'affichage des sections du catalogue Xtream.
  ///
  /// Clés : `live` (Live TV), `vod` (Films), `serie` (Séries). Modifiable dans
  /// Préférences par glisser-déposer. Défaut : Films, Séries, Live TV.
  static const List<String> defaultSectionOrder = ['vod', 'serie', 'live'];

  static final ValueNotifier<List<String>> _sectionOrderNotifier =
      ValueNotifier<List<String>>(List<String>.of(defaultSectionOrder));

  /// Ordre courant des sections.
  static List<String> get sectionOrder => _sectionOrderNotifier.value;

  static set sectionOrder(List<String> value) {
    final next = List<String>.unmodifiable(value);
    if (listEquals(next, _sectionOrderNotifier.value)) return;
    _sectionOrderNotifier.value = next;
  }

  /// Notifie les vues (Favoris, navigateur de source) quand l'ordre change.
  static ValueListenable<List<String>> get sectionOrderListenable =>
      _sectionOrderNotifier;

  /// Taille max des vignettes du catalogue (films/séries), en pixels.
  static const double defaultThumbSize = 150;
  static const double minThumbSize = 100;
  static const double maxThumbSize = 400;

  static final ValueNotifier<double> _thumbSizeNotifier =
      ValueNotifier<double>(defaultThumbSize);

  static double get thumbSize => _thumbSizeNotifier.value;

  static set thumbSize(double value) {
    final next = value.clamp(minThumbSize, maxThumbSize).toDouble();
    if (next == _thumbSizeNotifier.value) return;
    _thumbSizeNotifier.value = next;
  }

  static ValueListenable<double> get thumbSizeListenable => _thumbSizeNotifier;

  /// Ordre de tri du catalogue, conservé entre les sessions.
  static const String defaultCatalogSort = 'recent';
  static const List<String> catalogSortValues = [
    'recent',
    'oldest',
    'name_asc',
    'name_desc',
    'rating_desc',
    'rating_asc',
  ];

  static final ValueNotifier<String> _catalogSortNotifier =
      ValueNotifier<String>(defaultCatalogSort);

  static String get catalogSort => _catalogSortNotifier.value;

  static set catalogSort(String value) {
    if (!catalogSortValues.contains(value)) return;
    if (_catalogSortNotifier.value == value) return;
    _catalogSortNotifier.value = value;
  }

  static ValueListenable<String> get catalogSortListenable =>
      _catalogSortNotifier;

  /// D'où vient la configuration (`env`, `config`, `build`, `env-file`,
  /// vide si aucune).
  static String source = '';

  // Valeurs injectées à la compilation par
  // `flutter build … --dart-define-from-file=../.env`.
  // `String.fromEnvironment` doit être const pour être évalué au build.
  static const String _buildUrl =
      String.fromEnvironment('MIZU_BACKEND_URL', defaultValue: '');
  static const String _buildKey =
      String.fromEnvironment('MIZU_PUBLISHABLE_KEY', defaultValue: '');
  static const String _buildTmdb =
      String.fromEnvironment('MIZU_TMDB_KEY', defaultValue: '');

  /// Vrai si un backend utilisable est configuré.
  static bool get isConfigured =>
      backendUrl.isNotEmpty && publishableKey.isNotEmpty;

  static File get configFile => File('${AppDirs.configDir}/config.json');

  /// Fichiers `.env` consultés, dans l'ordre.
  static List<File> get envFiles {
    final files = <File>[
      File('${Directory.current.path}/.env'),
      File('${AppDirs.configDir}/.env'),
    ];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      files.add(File('$exeDir/.env'));
    } catch (_) {
      // resolvedExecutable indisponible : on ignore.
    }
    return files;
  }

  /// Lit la configuration.
  ///
  /// Ordre de priorité : variables d'environnement (dev/CI) > config.json
  /// (choix explicite de l'utilisateur) > valeurs compilées depuis `.env`
  /// (`--dart-define-from-file`) > fichier `.env` à l'exécution.
  /// À appeler avant `Supabase.initialize`.
  static void init() {
    _readEnvFile();
    _readConfigFile();
    _readBuildDefines();
    _readEnvironment();

    if (backendUrl.isNotEmpty) {
      while (backendUrl.endsWith('/')) {
        backendUrl = backendUrl.substring(0, backendUrl.length - 1);
      }
    }
  }

  static void _readConfigFile() {
    try {
      if (!configFile.existsSync()) return;
      final data = jsonDecode(configFile.readAsStringSync());
      if (data is! Map) return;
      final url = data['backend_url']?.toString().trim();
      final key = data['publishable_key']?.toString().trim();
      final tmdb = data['tmdb_api_key']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        backendUrl = url;
        source = 'config';
      }
      if (key != null && key.isNotEmpty) {
        publishableKey = key;
        source = 'config';
      }
      if (tmdb != null && tmdb.isNotEmpty) tmdbApiKey = tmdb;
      final order = data['section_order'];
      if (_isValidSectionOrder(order)) {
        sectionOrder = (order as List).map((e) => e.toString()).toList();
      }
      final thumb = data['thumb_size'];
      if (thumb is num) thumbSize = thumb.toDouble();
      final sort = data['catalog_sort']?.toString();
      if (sort != null) catalogSort = sort;
    } catch (_) {
      // Fichier illisible : on continue avec les autres sources.
    }
  }

  /// Un ordre valide contient exactement les trois sections, sans doublon.
  static bool _isValidSectionOrder(dynamic raw) {
    if (raw is! List) return false;
    final list = raw.map((e) => e.toString()).toList();
    return list.length == defaultSectionOrder.length &&
        list.toSet().length == defaultSectionOrder.length &&
        list.every(defaultSectionOrder.contains);
  }

  static void _readEnvFile() {
    for (final file in envFiles) {
      try {
        if (!file.existsSync()) continue;
        final values = _parseDotEnv(file.readAsStringSync());
        final url = values['MIZU_BACKEND_URL'] ?? values['SUPABASE_URL'];
        final key = values['MIZU_PUBLISHABLE_KEY'] ??
            values['SUPABASE_KEY'] ??
            values['SUPABASE_ANON_KEY'];
        if (url != null && url.isNotEmpty) {
          backendUrl = url;
          source = 'env-file';
        }
        if (key != null && key.isNotEmpty) {
          publishableKey = key;
          source = 'env-file';
        }
        final tmdb = values['MIZU_TMDB_KEY'] ?? values['TMDB_API_KEY'];
        if (tmdb != null && tmdb.isNotEmpty) tmdbApiKey = tmdb;
        final ua = values['MIZU_USER_AGENT'];
        if (ua != null && ua.isNotEmpty) userAgent = ua;
        if (backendUrl.isNotEmpty || publishableKey.isNotEmpty) return;
      } catch (_) {
        // .env illisible : on tente le suivant.
      }
    }
  }

  static void _readBuildDefines() {
    if (_buildUrl.trim().isNotEmpty) {
      backendUrl = _buildUrl.trim();
      source = 'build';
    }
    if (_buildKey.trim().isNotEmpty) {
      publishableKey = _buildKey.trim();
      source = 'build';
    }
    if (_buildTmdb.trim().isNotEmpty) tmdbApiKey = _buildTmdb.trim();
  }

  static void _readEnvironment() {
    final env = Platform.environment;
    final url = (env['MIZU_BACKEND_URL'] ?? env['SUPABASE_URL'])?.trim();
    final key = (env['MIZU_PUBLISHABLE_KEY'] ??
            env['SUPABASE_KEY'] ??
            env['SUPABASE_ANON_KEY'])
        ?.trim();
    final tmdb = (env['MIZU_TMDB_KEY'] ?? env['TMDB_API_KEY'])?.trim();
    final ua = env['MIZU_USER_AGENT']?.trim();
    if (ua != null && ua.isNotEmpty) userAgent = ua;
    if (url != null && url.isNotEmpty) {
      backendUrl = url;
      source = 'env';
    }
    if (key != null && key.isNotEmpty) {
      publishableKey = key;
      source = 'env';
    }
    if (tmdb != null && tmdb.isNotEmpty) tmdbApiKey = tmdb;
  }

  /// Parseur minimal de `.env` : `CLE=valeur`, `#` en commentaire,
  /// guillemets optionnels, `export` toléré.
  static Map<String, String> _parseDotEnv(String content) {
    final out = <String, String>{};
    for (final rawLine in const LineSplitter().convert(content)) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trim();
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = value;
    }
    return out;
  }

  /// Écrit la configuration. Les champs `null` conservent la valeur existante.
  /// Renvoie `true` si l'URL ou la clé du backend a changé (redémarrage requis).
  static Future<bool> save({
    String? backendUrl,
    String? publishableKey,
    String? tmdbApiKey,
    String? userAgent,
    List<String>? sectionOrder,
    double? thumbSize,
    String? catalogSort,
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
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      data['user_agent'] = userAgent.trim();
      MizuConfig.userAgent = userAgent.trim();
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
    if (sectionOrder != null && _isValidSectionOrder(sectionOrder)) {
      final list = sectionOrder.map((e) => e.toString()).toList();
      data['section_order'] = list;
      MizuConfig.sectionOrder = list;
    }
    if (thumbSize != null) {
      MizuConfig.thumbSize = thumbSize;
      data['thumb_size'] = MizuConfig.thumbSize;
    }
    if (catalogSort != null && catalogSortValues.contains(catalogSort)) {
      MizuConfig.catalogSort = catalogSort;
      data['catalog_sort'] = MizuConfig.catalogSort;
    }

    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    if (!Platform.isWindows) {
      // La clé n'est pas un secret critique, mais on limite la lecture.
      await Process.run('chmod', ['600', configFile.path]);
    }
    source = 'config';

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
