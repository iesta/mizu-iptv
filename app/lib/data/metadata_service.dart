import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../mizu_config.dart';
import '../platform/app_dirs.dart';

/// Métadonnées TMDB pour les contenus référencés par les favoris et la
/// progression.
///
/// Les `content_id` de Zen sont des identifiants **TMDB** (vérifié : 597 →
/// Titanic, 1368 → Rambo, 1398 → Les Soprano). TMDB exige une clé : elle est
/// lue depuis `MIZU_TMDB_KEY` ou `~/.config/mizu/config.json`
/// (`{"tmdb_api_key": "..."}`), jamais embarquée dans le binaire.
class MetadataService {
  MetadataService({String? apiKey}) : _apiKey = apiKey ?? _loadKey();

  /// Relit la clé (après modification dans les préférences).
  void reloadKey() {
    _apiKey = _loadKey();
    _memory.clear();
    _creditsMemory.clear();
    _certMemory.clear();
  }

  static const String _base = 'https://api.themoviedb.org/3';
  static const String imageBase = 'https://image.tmdb.org/t/p';

  /// Durée de conservation d'une fiche en cache.
  ///
  /// Les conditions d'utilisation de TMDB encadrent la conservation des
  /// données mises en cache ; 30 jours reste largement en dessous et évite de
  /// servir un titre obsolète.
  static const Duration cacheTtl = Duration(days: 30);

  String? _apiKey;
  final Map<String, ContentMeta?> _memory = {};
  final Map<String, Credits?> _creditsMemory = {};
  final Map<String, String?> _certMemory = {};
  final http.Client _http = http.Client();

  bool get enabled => (_apiKey ?? '').isNotEmpty;

  static String? _loadKey() {
    final env = Platform.environment['MIZU_TMDB_KEY'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    return MizuConfig.tmdbApiKey;
  }

  static File get _cacheFile =>
      File('${AppDirs.cacheDir}/metadata.json');

  Map<String, dynamic> _cache = {};
  bool _cacheLoaded = false;

  Future<void> _ensureCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      if (_cacheFile.existsSync()) {
        final decoded = jsonDecode(await _cacheFile.readAsString());
        if (decoded is Map<String, dynamic>) _cache = decoded;
      }
    } catch (_) {
      _cache = {};
    }
  }

  Future<void> _persist() async {
    try {
      await _cacheFile.parent.create(recursive: true);
      await _cacheFile.writeAsString(jsonEncode(_cache));
    } catch (_) {
      // Le cache est un confort, pas une dépendance.
    }
  }

  /// `type` : `vod` (film) ou `serie`.
  Future<ContentMeta?> fetch(String type, String id) async {
    final key = '$type:$id';
    if (_memory.containsKey(key)) return _memory[key];
    if (!enabled) {
      _memory[key] = null;
      return null;
    }
    await _ensureCache();
    final cached = _cache[key];
    if (cached is Map<String, dynamic>) {
      final fetchedAt = (cached['fetchedAt'] as num?)?.toInt();
      final fresh = fetchedAt != null &&
          DateTime.now().millisecondsSinceEpoch - fetchedAt <
              cacheTtl.inMilliseconds;
      if (fresh) {
        final meta = ContentMeta.fromJson(cached);
        _memory[key] = meta;
        return meta;
      }
      // Entrée expirée (ou écrite par une ancienne version, sans horodatage).
      _cache.remove(key);
    }
    try {
      final path = type == 'serie' ? 'tv' : 'movie';
      final res = await _http.get(
        Uri.parse('$_base/$path/$id?api_key=$_apiKey&language=fr-FR'),
        headers: {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) {
        _memory[key] = null;
        return null;
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final meta = ContentMeta(
        tmdbId: int.tryParse(id) ?? 0,
        type: type,
        title: (json['title'] ?? json['name'] ?? '').toString(),
        originalTitle: (json['original_title'] ?? json['original_name'])?.toString(),
        posterPath: json['poster_path']?.toString(),
        backdropPath: json['backdrop_path']?.toString(),
        overview: json['overview']?.toString(),
        year: _yearOf(json),
        vote: (json['vote_average'] as num?)?.toDouble(),
      );
      _cache[key] = {
        ...meta.toJson(),
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
      };
      _memory[key] = meta;
      await _persist();
      return meta;
    } catch (_) {
      _memory[key] = null;
      return null;
    }
  }

  /// Nombre de fiches actuellement en cache disque.
  Future<int> cacheSize() async {
    await _ensureCache();
    return _cache.length;
  }

  /// Vide le cache mémoire et disque (les fiches seront redemandées à TMDB).
  Future<void> clearCache() async {
    _memory.clear();
    _cache = {};
    _cacheLoaded = true;
    try {
      if (_cacheFile.existsSync()) await _cacheFile.delete();
    } catch (_) {
      // Rien de bloquant : le cache est recréé au besoin.
    }
  }

  static int? _yearOf(Map<String, dynamic> json) {
    final raw = (json['release_date'] ?? json['first_air_date'])?.toString();
    if (raw == null || raw.length < 4) return null;
    return int.tryParse(raw.substring(0, 4));
  }

  static String? posterUrl(String? path, {String size = 'w342'}) =>
      path == null ? null : '$imageBase/$size$path';

  static String? profileUrl(String? path, {String size = 'w185'}) =>
      path == null ? null : '$imageBase/$size$path';

  /// Distribution d'un film ou d'une série : acteurs, réalisation, musique.
  Future<Credits?> fetchCredits(String type, String id) async {
    final key = 'credits:$type:$id';
    if (_creditsMemory.containsKey(key)) return _creditsMemory[key];
    if (!enabled) {
      _creditsMemory[key] = null;
      return null;
    }
    await _ensureCache();
    final cached = _cache[key];
    if (cached is Map<String, dynamic>) {
      final credits = Credits.fromJson(cached);
      _creditsMemory[key] = credits;
      return credits;
    }
    try {
      final path = type == 'serie' ? 'tv' : 'movie';
      final res = await _http.get(
        Uri.parse('$_base/$path/$id/credits?api_key=$_apiKey&language=fr-FR'),
        headers: {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) {
        _creditsMemory[key] = null;
        return null;
      }
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final cast = ((json['cast'] as List?) ?? const [])
          .whereType<Map>()
          .take(20)
          .map((c) => CastMember(
                name: (c['name'] ?? '').toString(),
                character: c['character']?.toString(),
                profilePath: c['profile_path']?.toString(),
              ))
          .where((c) => c.name.isNotEmpty)
          .toList();
      final crew = ((json['crew'] as List?) ?? const []).whereType<Map>();
      Iterable<String> jobs(String job) => crew
          .where((c) => c['job'] == job)
          .map((c) => (c['name'] ?? '').toString())
          .where((n) => n.isNotEmpty);
      final credits = Credits(
        cast: cast,
        directors: jobs('Director').toList(),
        composers: jobs('Original Music Composer').toList(),
      );
      _cache[key] = credits.toJson();
      _creditsMemory[key] = credits;
      await _persist();
      return credits;
    } catch (_) {
      _creditsMemory[key] = null;
      return null;
    }
  }
  /// Classification d'âge : France d'abord (« 12 », « 16 »), sinon États-Unis
  /// (« R », « PG-13 », « TV-MA »).
  Future<String?> fetchCertification(String type, String id) async {
    final key = 'cert:$type:$id';
    if (_certMemory.containsKey(key)) return _certMemory[key];
    if (!enabled) {
      _certMemory[key] = null;
      return null;
    }
    await _ensureCache();
    final cached = _cache[key];
    if (cached is String) {
      _certMemory[key] = cached;
      return cached;
    }
    try {
      final path = type == 'serie'
          ? 'tv/$id/content_ratings'
          : 'movie/$id/release_dates';
      final res = await _http.get(
        Uri.parse('$_base/$path?api_key=$_apiKey'),
        headers: {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) {
        _certMemory[key] = null;
        return null;
      }
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final results = ((json['results'] as List?) ?? const []).whereType<Map>();

      String? pick(String country) {
        for (final r in results) {
          if (r['iso_3166_1'] != country) continue;
          final raw = type == 'serie'
              ? r['rating']?.toString()
              : ((r['release_dates'] as List?) ?? const [])
                  .whereType<Map>()
                  .map((d) => (d['certification'] ?? '').toString())
                  .firstWhere((c) => c.isNotEmpty, orElse: () => '');
          final text = (raw ?? '').trim();
          if (text.isNotEmpty) return text;
        }
        return null;
      }

      final cert = pick('FR') ?? pick('US');
      if (cert != null) _cache[key] = cert;
      _certMemory[key] = cert;
      await _persist();
      return cert;
    } catch (_) {
      _certMemory[key] = null;
      return null;
    }
  }
}

class CastMember {
  CastMember({required this.name, this.character, this.profilePath});

  final String name;
  final String? character;
  final String? profilePath;

  String? get photo => MetadataService.profileUrl(profilePath);

  Map<String, dynamic> toJson() =>
      {'name': name, 'character': character, 'profilePath': profilePath};

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
        name: json['name']?.toString() ?? '',
        character: json['character']?.toString(),
        profilePath: json['profilePath']?.toString(),
      );
}

class Credits {
  Credits({
    required this.cast,
    required this.directors,
    required this.composers,
  });

  final List<CastMember> cast;
  final List<String> directors;
  final List<String> composers;

  bool get isEmpty => cast.isEmpty && directors.isEmpty && composers.isEmpty;

  Map<String, dynamic> toJson() => {
        'cast': cast.map((c) => c.toJson()).toList(),
        'directors': directors,
        'composers': composers,
      };

  factory Credits.fromJson(Map<String, dynamic> json) => Credits(
        cast: ((json['cast'] as List?) ?? const [])
            .whereType<Map>()
            .map((c) => CastMember.fromJson(c.cast<String, dynamic>()))
            .toList(),
        directors: ((json['directors'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        composers: ((json['composers'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class ContentMeta {
  ContentMeta({
    required this.tmdbId,
    required this.type,
    required this.title,
    this.originalTitle,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.year,
    this.vote,
  });

  final int tmdbId;
  final String type;
  final String title;
  final String? originalTitle;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final int? year;
  final double? vote;

  String? get poster => MetadataService.posterUrl(posterPath);

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'type': type,
        'title': title,
        'originalTitle': originalTitle,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'overview': overview,
        'year': year,
        'vote': vote,
      };

  factory ContentMeta.fromJson(Map<String, dynamic> json) => ContentMeta(
        tmdbId: (json['tmdbId'] as num?)?.toInt() ?? 0,
        type: json['type']?.toString() ?? 'vod',
        title: json['title']?.toString() ?? '',
        originalTitle: json['originalTitle']?.toString(),
        posterPath: json['posterPath']?.toString(),
        backdropPath: json['backdropPath']?.toString(),
        overview: json['overview']?.toString(),
        year: (json['year'] as num?)?.toInt(),
        vote: (json['vote'] as num?)?.toDouble(),
      );
}
