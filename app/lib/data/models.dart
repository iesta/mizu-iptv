// Modèles du schéma de synchronisation Zen (validés sur un compte réel).
//
// Le champ `raw` conserve la ligne complète : le serveur peut ajouter des
// colonnes sans casser le client.

String? _str(dynamic v) => v?.toString();

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class WatchProfile {
  WatchProfile(this.raw)
      : id = _str(raw['id']) ?? '',
        name = _str(raw['name']) ?? 'Profil',
        color = (raw['color'] as num?)?.toInt();

  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final int? color;
}

class PlaylistSource {
  PlaylistSource(this.raw)
      : id = _str(raw['id']) ?? '',
        name = _str(raw['name']) ?? 'Source',
        kind = _str(raw['runtimeType']) ?? 'xtream',
        host = _str(raw['host']),
        url = _str(raw['url']),
        username = _str(raw['username']),
        password = _str(raw['password']),
        epgUrl = _str(raw['epg_url']),
        color = (raw['color'] as num?)?.toInt();

  final Map<String, dynamic> raw;
  final String id;
  final String name;

  /// `xtream` ou `m3u` (colonne serveur `runtimeType`).
  final String kind;
  final String? host;
  final String? url;
  final String? username;
  final String? password;
  final String? epgUrl;
  final int? color;

  bool get isXtream => kind == 'xtream';
  bool get isM3u => kind == 'm3u';

  /// Adresse utile selon le type : `host` pour Xtream, `url` pour M3U.
  String get endpoint => (isXtream ? host : url) ?? '';
}

class FavoriteItem {
  FavoriteItem(this.raw)
      : contentId = _str(raw['content_id']) ?? '',
        contentType = _str(raw['content_type']) ?? '',
        sortOrder = (raw['sort_order'] as num?)?.toInt(),
        addedAt = _date(raw['added_at']);

  final Map<String, dynamic> raw;

  /// Identifiant du média : id numérique du fournisseur pour `vod`/`serie`,
  /// nom de la chaîne pour `channel` (les ids diffèrent d'une source à l'autre).
  final String contentId;

  /// `channel`, `vod` ou `serie`.
  final String contentType;
  final int? sortOrder;
  final DateTime? addedAt;
}

class ProgressItem {
  ProgressItem(this.raw)
      : serieId = _str(raw['serie_id']) ?? '',
        season = (raw['season_number'] as num?)?.toInt() ?? 0,
        episode = (raw['episode_number'] as num?)?.toInt() ?? 0,
        watchTime = (raw['watch_time'] as num?)?.toDouble() ?? 0,
        watchProgress = (raw['watch_progress'] as num?)?.toDouble() ?? 0,
        versionId = (raw['version_id'] as num?)?.toInt(),
        kind = _str(raw['runtimeType']) ?? 'serie',
        lastWatched = _date(raw['last_watched']),
        allEpisodesWatched = raw['all_episodes_watched'] == true;

  final Map<String, dynamic> raw;
  final String serieId;
  final int season;
  final int episode;

  /// Position de lecture en secondes.
  final double watchTime;

  /// Fraction 0..1 de l'épisode vue.
  final double watchProgress;
  final int? versionId;
  final String kind;
  final DateTime? lastWatched;
  final bool allEpisodesWatched;
}
