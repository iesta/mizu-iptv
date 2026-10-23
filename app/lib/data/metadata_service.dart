import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Métadonnées TMDB pour les contenus référencés par les favoris et la
/// progression.
///
/// Les `content_id` de Zen sont des identifiants **TMDB** (vérifié : 597 →
/// Titanic, 1368 → Rambo, 1398 → Les Soprano). TMDB exige une clé : elle est
/// lue depuis `MIZU_TMDB_KEY` ou `~/.config/mizu/config.json`
/// (`{"tmdb_api_key": "..."}`), jamais embarquée dans le binaire.
class MetadataService {
  MetadataService({String? apiKey}) : _apiKey = apiKey ?? _loadKey();

  static const String _base = 'https://api.themoviedb.org/3';
  static const String imageBase = 'https://image.tmdb.org/t/p';

  final String? _apiKey;
  final Map<String, ContentMeta?> _memory = {};
  final http.Client _http = http.Client();

  bool get enabled => (_apiKey ?? '').isNotEmpty;

  static String? _loadKey() {
    final env = Platform.environment['MIZU_TMDB_KEY'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    try {
      final file = File('${_home()}/.config/mizu/config.json');
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync());
      if (data is Map && data['tmdb_api_key'] is String) {
        return (data['tmdb_api_key'] as String).trim();
      }
    } catch (_) {
      // Configuration illisible : on reste en mode dégradé.
    }
    return null;
  }

  static String _home() => Platform.environment['HOME'] ?? '.';

  static File get _cacheFile =>
      File('${_home()}/.cache/mizu/metadata.json');

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
      final meta = ContentMeta.fromJson(cached);
      _memory[key] = meta;
      return meta;
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
      _cache[key] = meta.toJson();
      _memory[key] = meta;
      await _persist();
      return meta;
    } catch (_) {
      _memory[key] = null;
      return null;
    }
  }

  static int? _yearOf(Map<String, dynamic> json) {
    final raw = (json['release_date'] ?? json['first_air_date'])?.toString();
    if (raw == null || raw.length < 4) return null;
    return int.tryParse(raw.substring(0, 4));
  }

  static String? posterUrl(String? path, {String size = 'w342'}) =>
      path == null ? null : '$imageBase/$size$path';
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
