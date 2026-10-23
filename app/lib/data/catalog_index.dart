import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/app_dirs.dart';
import 'models.dart';
import 'xtream_client.dart';

/// Index local « id TMDB → contenu du fournisseur ».
///
/// Les favoris et la progression de Zen ne stockent qu'un **id TMDB**. Pour
/// afficher un nom (et pouvoir relancer la lecture) sans dépendre de l'API
/// TMDB, on indexe le catalogue des sources Xtream : chaque série/film dont le
/// panneau expose `tmdb_id` fournit son nom, son affiche et son id fournisseur.
class CatalogIndex extends ChangeNotifier {
  CatalogIndex._();

  static final CatalogIndex instance = CatalogIndex._();

  final Map<String, IndexEntry> _entries = {};
  bool _loading = false;
  Future<void>? _cacheFuture;
  String? _lastError;

  bool get loading => _loading;
  String? get lastError => _lastError;
  int get size => _entries.length;

  static String _key(String kind, String tmdbId) => '$kind:$tmdbId';

  IndexEntry? lookup(String kind, String tmdbId) =>
      _entries[_key(kind == 'vod' ? 'vod' : 'serie', tmdbId)];

  static File get _cacheFile =>
      File('${AppDirs.cacheDir}/catalog_index_v2.json');

  /// Charge le cache disque sans toucher au réseau (noms disponibles tout de suite).
  /// Les appels concurrents partagent la même future (pas de lecture partielle).
  Future<void> ensureLoaded() => _cacheFuture ??= _doLoadCache();

  Future<void> _doLoadCache() async {
    debugPrint('index: chargement ${_cacheFile.path} exists=${await _cacheFile.exists()}');
    try {
      if (await _cacheFile.exists()) {
        final data = jsonDecode(await _cacheFile.readAsString());
        if (data is Map<String, dynamic>) {
          for (final e in data.entries) {
            final v = e.value;
            if (v is Map<String, dynamic>) {
              _entries[e.key] = IndexEntry.fromJson(v);
            }
          }
        }
      }
    } catch (_) {
      // Cache illisible : on repartira du réseau.
    }
    debugPrint('index: ${_entries.length} entrées en cache');
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _cacheFile.parent.create(recursive: true);
      await _cacheFile.writeAsString(jsonEncode(
        _entries.map((k, v) => MapEntry(k, v.toJson())),
      ));
    } catch (_) {
      // best effort
    }
  }

  String? _tmdbOf(Map<String, dynamic> item) {
    final raw = (item['tmdb_id'] ?? item['tmdb'] ?? item['tmdbId'])?.toString();
    if (raw == null || raw.isEmpty || raw == '0' || raw == 'null') return null;
    return raw;
  }

  /// Construit/actualise l'index pour les sources Xtream fournies.
  ///
  /// Volontairement séquentiel et espacé : les panneaux Xtream coupent (HTTP
  /// 461) quand on enchaîne les requêtes.
  Future<void> build(List<PlaylistSource> sources, {bool force = false}) async {
    if (_loading) return;
    await ensureLoaded();
    final xtream = sources.where((s) => s.isXtream).toList();
    if (xtream.isEmpty) return;
    if (!force && _entries.isNotEmpty) return;

    _loading = true;
    _lastError = null;
    notifyListeners();

    var added = 0;
    for (final source in xtream) {
      if (_entries.values.any(
          (e) => e.candidates.any((c) => c.sourceId == source.id))) {
        continue;
      }
      final client = XtreamClient(
        baseUrl: source.endpoint,
        username: source.username ?? '',
        password: source.password ?? '',
        userAgent: source.raw['user_agent']?.toString(),
      );
      try {
        final series = await client.series();
        await Future<void>.delayed(const Duration(seconds: 3));
        final movies = await client.vodStreams();
        added += _ingest(source, series, 'serie');
        added += _ingest(source, movies, 'vod');
      } catch (e) {
        _lastError = e.toString();
        debugPrint('index: source ${source.name} ignorée ($e)');
      } finally {
        client.close();
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }

    _loading = false;
    if (added > 0) await _persist();
    debugPrint('index: $added entrées ajoutées, total ${_entries.length}');
    notifyListeners();
  }

  int _ingest(PlaylistSource source, List<dynamic> items, String kind) {
    var added = 0;
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      final tmdb = _tmdbOf(item);
      if (tmdb == null) continue;
      final providerId =
          (item['series_id'] ?? item['stream_id'] ?? item['id'])?.toString();
      if (providerId == null) continue;
      final name = (item['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final key = _key(kind, tmdb);
      final candidate = IndexCandidate(
        providerId: providerId,
        sourceId: source.id,
        sourceName: source.name,
      );
      final existing = _entries[key];
      if (existing == null) {
        _entries[key] = IndexEntry(
          kind: kind,
          tmdbId: tmdb,
          name: name,
          poster: (item['cover'] ?? item['stream_icon'] ?? item['cover_big'])
              ?.toString(),
          candidates: [candidate],
        );
        added++;
      } else if (!existing.candidates
          .any((c) => c.sourceId == candidate.sourceId)) {
        // Le même contenu existe sur plusieurs sources : on garde toutes les
        // pistes pour pouvoir basculer si l'une ne répond pas.
        existing.candidates.add(candidate);
      }
    }
    return added;
  }
}

/// Une source où le contenu est disponible.
class IndexCandidate {
  IndexCandidate({
    required this.providerId,
    required this.sourceId,
    required this.sourceName,
  });

  final String providerId;
  final String sourceId;
  final String sourceName;

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'sourceId': sourceId,
        'sourceName': sourceName,
      };

  factory IndexCandidate.fromJson(Map<String, dynamic> json) => IndexCandidate(
        providerId: json['providerId']?.toString() ?? '',
        sourceId: json['sourceId']?.toString() ?? '',
        sourceName: json['sourceName']?.toString() ?? '',
      );
}

class IndexEntry {
  IndexEntry({
    required this.kind,
    required this.tmdbId,
    required this.name,
    required this.candidates,
    this.poster,
  });

  final String kind;
  final String tmdbId;
  final String name;
  final String? poster;
  final List<IndexCandidate> candidates;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'tmdbId': tmdbId,
        'name': name,
        'poster': poster,
        'candidates': candidates.map((c) => c.toJson()).toList(),
      };

  factory IndexEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['candidates'];
    var candidates = <IndexCandidate>[];
    if (raw is List) {
      candidates = raw
          .whereType<Map>()
          .map((e) => IndexCandidate.fromJson(e.cast<String, dynamic>()))
          .toList();
    } else if (json['providerId'] != null) {
      // Ancien format (une seule source).
      candidates = [
        IndexCandidate(
          providerId: json['providerId'].toString(),
          sourceId: json['sourceId']?.toString() ?? '',
          sourceName: json['sourceName']?.toString() ?? '',
        ),
      ];
    }
    return IndexEntry(
      kind: json['kind']?.toString() ?? 'serie',
      tmdbId: json['tmdbId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      poster: json['poster']?.toString(),
      candidates: candidates,
    );
  }
}
