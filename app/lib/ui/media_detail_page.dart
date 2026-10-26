import 'dart:io';

import 'package:flutter/material.dart';

import '../data/metadata_service.dart';
import '../data/models.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';
import 'player_page.dart';

enum MediaKind { vod, serie }

/// Épisode cible d'une reprise : celui en cours, ou le suivant s'il est fini.
class _Target {
  const _Target(this.season, this.episode, this.position, {this.isNext = false});
  final int season;
  final int episode;

  /// Position de reprise en secondes (0 si l'épisode n'a pas commencé).
  final double position;

  /// L'épisode en cours est terminé : la cible est l'épisode suivant.
  final bool isNext;
}

/// Fiche film ou série d'une source Xtream, avec lecture et reprise.
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.state,
    required this.client,
    required this.kind,
    required this.id,
    required this.fallbackName,
    this.fallbackPoster,
    this.initialSeason,
    this.fallbackClients = const [],
  });

  final AppState state;
  final XtreamClient client;
  final MediaKind kind;
  final int id;
  final String fallbackName;
  final String? fallbackPoster;

  /// Saison à présélectionner (reprise de lecture).
  final int? initialSeason;

  /// Clients de secours : si la source principale ne répond pas (HTTP 461,
  /// compte expiré…), on réessaie sur la suivante avec le même contenu.
  final List<XtreamClient> fallbackClients;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _data;
  Map<String, List<Map<String, dynamic>>> _episodes = {};
  int _season = 1;
  String? _error;
  bool _loading = true;
  bool _autoPlayed = false;
  Credits? _credits;
  String? _backdrop;
  double? _vote;
  String? _cert;
  late XtreamClient _client = widget.client;
  late final List<XtreamClient> _fallbacks = List.of(widget.fallbackClients);
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.kind == MediaKind.vod) {
        final json = await _client.vodInfo(widget.id);
        _info = (json['info'] as Map?)?.cast<String, dynamic>();
        _data = (json['movie_data'] as Map?)?.cast<String, dynamic>();
      } else {
        final json = await _client.seriesInfo(widget.id);
        _info = (json['info'] as Map?)?.cast<String, dynamic>();
        _data = json;
        final rawEpisodes = json['episodes'];
        if (rawEpisodes is Map) {
          _episodes = rawEpisodes.map((k, v) => MapEntry(
                k.toString(),
                (v as List)
                    .map((e) => (e as Map).cast<String, dynamic>())
                    .toList(),
              ));
        }
        _selectInitialSeason();
      }
    } catch (e) {
      if (_fallbacks.isNotEmpty) {
        // Bascule sur la source suivante qui propose le même contenu.
        _client.close();
        _client = _fallbacks.removeAt(0);
        _attempt++;
        if (_attempt < 4) return _load();
      }
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _loadCredits();
    _maybeAutoPlay();
  }

  /// Backdrop et distribution via TMDB ; silencieux si pas de clé TMDB.
  Future<void> _loadCredits() async {
    final tmdb = _tmdbId;
    if (tmdb == null) return;
    final type = widget.kind == MediaKind.vod ? 'vod' : 'serie';
    final meta = await widget.state.metadata.fetch(type, tmdb);
    final credits = await widget.state.metadata.fetchCredits(type, tmdb);
    final cert = await widget.state.metadata.fetchCertification(type, tmdb);
    if (!mounted) return;
    setState(() {
      _backdrop = MetadataService.posterUrl(meta?.backdropPath, size: 'w1280');
      _vote = meta?.vote;
      _cert = cert;
      if (credits != null && !credits.isEmpty) _credits = credits;
    });
  }

  /// Saison ouverte par défaut : celle de l'épisode à reprendre, sinon celle
  /// demandée par l'appelant, sinon la première.
  void _selectInitialSeason() {
    final numbers = _episodes.keys
        .map(int.tryParse)
        .whereType<int>()
        .toList()
      ..sort();
    if (numbers.isEmpty) return;
    final target = _target;
    if (target != null && numbers.contains(target.season)) {
      _season = target.season;
      return;
    }
    final wanted = widget.initialSeason;
    if (wanted != null && numbers.contains(wanted)) {
      _season = wanted;
      return;
    }
    _season = numbers.first;
  }

  /// Titre affiché, sans le millésime final (« Film (2026) » → « Film ») :
  /// l'année figure déjà dans les métadonnées.
  String get _title {
    final raw =
        (_info?['name'] ?? _data?['name'] ?? widget.fallbackName).toString();
    return raw.replaceFirst(RegExp(r'\s*\((?:19|20)\d{2}\)\s*$'), '');
  }

  String? get _plot {
    final raw = (_info?['plot'] ?? _info?['description'] ?? _info?['overview'])
        ?.toString();
    return (raw == null || raw.trim().isEmpty) ? null : raw.trim();
  }

  String? get _poster {
    final raw = (_info?['movie_image'] ??
            _info?['cover_big'] ??
            _info?['cover'] ??
            widget.fallbackPoster)
        ?.toString();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  String? get _tmdbId {
    final raw = (_info?['tmdb_id'] ?? _info?['tmdb'] ?? _info?['tmdbId'])
        ?.toString();
    if (raw == null || raw.isEmpty || raw == '0') return null;
    return raw;
  }

  String? get _containerExt {
    final raw = _data?['container_extension']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    final infoExt = _info?['container_extension']?.toString();
    return (infoExt != null && infoExt.isNotEmpty) ? infoExt : null;
  }

  ProgressItem? get _resume {
    final tmdb = _tmdbId;
    if (tmdb == null) return null;
    for (final p in widget.state.progress) {
      if (p.serieId == tmdb) return p;
    }
    return null;
  }

  /// Épisode à reprendre : celui en cours, ou le suivant si l'épisode est fini.
  _Target? get _target {
    if (widget.kind != MediaKind.serie) return null;
    final r = _resume;
    if (r == null) return null;

    final finished = r.allEpisodesWatched || r.watchProgress >= 0.95;
    if (!finished) {
      return _Target(r.season, r.episode, r.watchTime);
    }

    final list = _episodes['${r.season}'] ?? const [];
    if (list.isEmpty) return _Target(r.season, r.episode, 0);

    final index = list.indexWhere(
        (e) => (e['episode_num'] as num?)?.toInt() == r.episode);
    if (index >= 0 && index + 1 < list.length) {
      final next = (list[index + 1]['episode_num'] as num?)?.toInt();
      return _Target(r.season, next ?? r.episode + 1, 0, isNext: true);
    }

    // Fin de saison : premier épisode de la saison suivante s'il existe.
    final seasons = _episodes.keys.map(int.tryParse).whereType<int>().toList()
      ..sort();
    int? nextSeason;
    for (final s in seasons) {
      if (s > r.season) {
        nextSeason = s;
        break;
      }
    }
    if (nextSeason != null) {
      final first = _episodes['$nextSeason']!.first;
      return _Target(nextSeason, (first['episode_num'] as num?)?.toInt() ?? 1, 0,
          isNext: true);
    }
    return _Target(r.season, r.episode, 0);
  }

  void _playMovie() {
    final ext = _containerExt ?? 'mp4';
    final url = _client.vodUrl(widget.id, ext: ext);
    final resume = _resume;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        state: widget.state,
        url: url,
        title: _title,
        subtitle: 'Film',
        contentId: _tmdbId,
        contentType: _tmdbId == null ? null : 'vod',
        initialPosition: (resume != null && resume.watchTime > 5)
            ? Duration(seconds: resume.watchTime.round())
            : null,
      ),
    ));
  }

  void _playEpisode(Map<String, dynamic> episode, {Duration? position}) {
    final episodeId = int.tryParse(episode['id']?.toString() ?? '');
    if (episodeId == null) return;
    final ext = episode['container_extension']?.toString() ?? 'mp4';
    final season = (episode['season'] as num?)?.toInt() ??
        (episode['season_number'] as num?)?.toInt() ??
        _season;
    final number = (episode['episode_num'] as num?)?.toInt() ?? 0;
    final tmdb = _tmdbId;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        state: widget.state,
        url: _client.seriesUrl(episodeId, ext: ext),
        title: _title,
        subtitle: 'S$season E$number',
        contentId: tmdb,
        contentType: tmdb == null ? null : 'serie',
        season: tmdb == null ? null : season,
        episode: tmdb == null ? null : number,
        initialPosition: position,
      ),
    ));
  }

  void _playTarget() {
    final t = _target;
    if (t == null) return;
    final list = _episodes['${t.season}'] ?? const [];
    if (list.isEmpty) return;
    var episode = list.first;
    for (final e in list) {
      if ((e['episode_num'] as num?)?.toInt() == t.episode) {
        episode = e;
        break;
      }
    }
    _playEpisode(
      episode,
      position: t.position > 5 ? Duration(seconds: t.position.round()) : null,
    );
  }

  void _maybeAutoPlay() {
    if (Platform.environment['MIZU_AUTOPLAY'] != '1' || _autoPlayed) return;
    _autoPlayed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.kind == MediaKind.vod) {
        _playMovie();
        return;
      }
      final target = _target;
      if (target != null) {
        _playTarget();
        return;
      }
      for (final list in _episodes.values) {
        if (list.isNotEmpty) {
          _playEpisode(list.first);
          return;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _target;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_tmdbId != null)
            ListenableBuilder(
              listenable: widget.state,
              builder: (context, _) {
                final type = widget.kind == MediaKind.vod ? 'vod' : 'serie';
                final fav = widget.state.isFavorite(_tmdbId!, type);
                return IconButton(
                  tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
                  onPressed: () => widget.state.toggleFavorite(_tmdbId!, type),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Erreur: $_error'),
                  ),
                )
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.3),
                  ),
                  child: ListView(
                  children: [
                    _header(theme, target),
                    if (widget.kind == MediaKind.serie) _episodesSection(theme),
                    _castSection(theme),
                    const SizedBox(height: 24),
                  ],
                ),
                ),
    );
  }

  /// Marge horizontale unique de la fiche (toutes les sections l'utilisent).
  static const double _pad = 20;

  /// En-tête : backdrop, titre + bouton, puis affiche qui chevauche le
  /// backdrop juste sous la ligne d'année.
  Widget _header(ThemeData theme, _Target? target) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 280,
          child: _backdropLayer(theme),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(_pad, 12, _pad, 0),
              child: _titleRow(theme, target),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _posterBox(theme),
                  const SizedBox(width: 20),
                  Expanded(child: _detailsColumn(theme, target)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _backdropLayer(ThemeData theme) {
    final backdrop = _backdropUrl;
    final colors = theme.colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop != null)
          Image.network(
            backdrop,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.8),
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.35),
                colors.surface,
              ],
              stops: const [0, 0.6, 1],
            ),
          ),
        ),
      ],
    );
  }

  /// Titre, note, classification, méta à gauche ; bouton de lecture à droite.
  Widget _titleRow(ThemeData theme, _Target? target) {
    final colors = theme.colorScheme;
    final rating = _rating;
    final meta = [
      _year,
      _duration,
      _info?['genre']?.toString(),
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

    final play = widget.kind == MediaKind.vod
        ? FilledButton.icon(
            style: _playButtonStyle(theme),
            onPressed: _playMovie,
            icon: const Icon(Icons.play_arrow),
            label: Text(_resume == null ? 'Lecture' : 'Reprendre'),
          )
        : target != null
            ? FilledButton.icon(
                style: _playButtonStyle(theme),
                onPressed: _playTarget,
                icon: const Icon(Icons.play_arrow),
                label: Text('S${target.season} E${target.episode}'),
              )
            : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title,
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (rating != null || _cert != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (rating != null) ...[
                      _stars(rating),
                      const SizedBox(width: 10),
                      Text(
                        '${rating.toStringAsFixed(1)} / 5',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                    if (rating != null && _cert != null)
                      const SizedBox(width: 14),
                    if (_cert != null) _certBadge(theme),
                  ],
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta.join(' · '),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (play != null)
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 4),
            child: play,
          ),
      ],
    );
  }

  /// Affiche verticale (200×300) avec repli si absente.
  Widget _posterBox(ThemeData theme) {
    final fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.movie_outlined, size: 32),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 200,
        height: 300,
        child: _poster == null
            ? fallback
            : Image.network(
                _poster!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  /// Description et infos de reprise, à droite de l'affiche.
  Widget _detailsColumn(ThemeData theme, _Target? target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_plot != null)
          Text(_plot!, style: theme.textTheme.bodyMedium),
        if (widget.kind == MediaKind.serie && target != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              target.isNext
                  ? 'épisode suivant'
                  : target.position > 5
                      ? 'à ${_mmss(target.position)}'
                      : 'depuis le début',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        if (_tmdbId == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Pas d\'identifiant TMDB : favoris et reprise '
              'ne seront pas synchronisés.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
      ],
    );
  }

  /// Classification d'âge TMDB : « 12 », « 16 », « R », « PG-13 »…
  Widget _certBadge(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(_cert!, style: theme.textTheme.labelMedium),
      );

  /// Cinq étoiles jaunes remplies à la fraction de la note (0..5).
  Widget _stars(double rating) {
    const amber = Color(0xFFFFC107);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              children: [
                Icon(Icons.star_rounded,
                    size: 28, color: amber.withValues(alpha: 0.22)),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: (rating - i).clamp(0.0, 1.0),
                    child: const Icon(Icons.star_rounded,
                        size: 28, color: amber),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Backdrop TMDB si chargé, sinon celui de la source Xtream (URL ou chemin).
  String? get _backdropUrl {
    if (_backdrop != null) return _backdrop;
    final raw = _info?['backdrop_path']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('http')
        ? raw
        : MetadataService.posterUrl(raw, size: 'w1280');
  }

  /// Note sur 5 : `rating` Xtream (souvent /10) sinon vote TMDB.
  double? get _rating {
    var raw = double.tryParse(_info?['rating']?.toString() ?? '');
    raw ??= _vote;
    if (raw == null || raw <= 0) return null;
    return (raw > 5 ? raw / 2 : raw).clamp(0.0, 5.0);
  }

  String? get _year {
    final raw = (_info?['releasedate'] ??
            _info?['releaseDate'] ??
            _info?['release_date'])
        ?.toString();
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})').firstMatch(raw);
    return match?.group(1);
  }

  /// Durée lisible : « 01:37:31 » (Xtream) → « 1h37 ».
  String? get _duration {
    final raw = _info?['duration']?.toString().trim();
    if (raw != null && raw.isNotEmpty && raw != '00:00:00') {
      final hms = RegExp(r'^(\d+):(\d{2}):(\d{2})$').firstMatch(raw);
      if (hms == null) return raw;
      final h = int.parse(hms.group(1)!);
      final m = int.parse(hms.group(2)!);
      return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
    }
    final secs = int.tryParse(_info?['duration_secs']?.toString() ?? '');
    if (secs == null || secs <= 0) return null;
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
  }

  /// Bouton de lecture un peu plus gros que le défaut (TV / usage à distance).
  ButtonStyle _playButtonStyle(ThemeData theme) => FilledButton.styleFrom(
        minimumSize: const Size(0, 60),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        iconSize: 34,
        textStyle: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      );

  /// Noms séparés par virgule, point-virgule, « & » ou « et » (champ texte
  /// Xtream), ou déjà sous forme de liste.
  List<String> _splitNames(dynamic raw) {
    if (raw == null) return const [];
    final text = raw is List ? raw.join(', ') : raw.toString();
    return text
        .split(RegExp(r'[,;/]| & | et '))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<String> get _directors {
    final fromTmdb = _credits?.directors ?? const <String>[];
    return fromTmdb.isNotEmpty ? fromTmdb : _splitNames(_info?['director']);
  }

  List<String> get _composers => _credits?.composers ?? const [];

  List<CastMember> get _cast {
    final fromTmdb = _credits?.cast ?? const <CastMember>[];
    if (fromTmdb.isNotEmpty) return fromTmdb;
    // Repli sans clé TMDB : le champ `cast` de la source, sans photos.
    return _splitNames(_info?['cast'])
        .map((name) => CastMember(name: name))
        .toList();
  }

  Widget _castSection(ThemeData theme) {
    final directors = _directors;
    final composers = _composers;
    final cast = _cast;
    if (directors.isEmpty && composers.isEmpty && cast.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 8, _pad, 8),
          child: Text('Distribution', style: theme.textTheme.titleMedium),
        ),
        if (directors.isNotEmpty) _crewLine(theme, 'Réalisation', directors),
        if (composers.isNotEmpty) _crewLine(theme, 'Musique', composers),
        if (cast.isNotEmpty)
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 8),
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _personTile(theme, cast[i]),
            ),
          ),
      ],
    );
  }

  Widget _crewLine(ThemeData theme, String label, List<String> names) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, 0, _pad, 4),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$label : ',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
          TextSpan(text: names.join(', ')),
        ]),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  Widget _personTile(ThemeData theme, CastMember person) {
    final photo = person.photo;
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 92,
              height: 112,
              child: photo == null
                  ? _personPlaceholder(theme, person.name)
                  : Image.network(
                      photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _personPlaceholder(theme, person.name),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if ((person.character ?? '').isNotEmpty)
            Text(
              person.character!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  Widget _personPlaceholder(ThemeData theme, String name) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(initials, style: theme.textTheme.titleMedium),
    );
  }

  static String _mmss(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _episodesSection(ThemeData theme) {
    final seasonNumbers = _episodes.keys.map(int.tryParse).whereType<int>().toList()
      ..sort();
    if (seasonNumbers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(_pad),
        child: Text('Aucun épisode retourné par la source.'),
      );
    }
    final current = seasonNumbers.contains(_season) ? _season : seasonNumbers.first;
    final list = _episodes['$current'] ?? const [];
    final target = _target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 0, _pad, 8),
          child: Text('Épisodes', style: theme.textTheme.titleMedium),
        ),
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _pad),
            children: [
              for (final s in seasonNumbers)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('Saison $s'),
                    selected: s == current,
                    onSelected: (_) => setState(() => _season = s),
                  ),
                ),
            ],
          ),
        ),
        for (final ep in list)
          _episodeTile(
            theme,
            ep,
            (ep['episode_num'] as num?)?.toInt(),
            isTarget: target != null &&
                target.season == current &&
                target.episode == (ep['episode_num'] as num?)?.toInt(),
          ),
      ],
    );
  }

  Widget _episodeTile(
    ThemeData theme,
    Map<String, dynamic> ep,
    int? number, {
    required bool isTarget,
  }) {
    final resume = _resume;
    String? subtitle;
    if (isTarget && resume != null) {
      if (resume.allEpisodesWatched || resume.watchProgress >= 0.95) {
        subtitle = 'Vu · reprendre au suivant';
      } else if (resume.watchTime > 5) {
        subtitle = 'Reprendre à ${(resume.watchProgress * 100).round()} %';
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: _pad),
      mouseCursor: SystemMouseCursors.click,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isTarget ? theme.colorScheme.primary : null,
        child: Text(
          '${number ?? '?'}',
          style: TextStyle(
            fontSize: 12,
            color: isTarget ? theme.colorScheme.onPrimary : null,
          ),
        ),
      ),
      title: Text(
        (ep['title'] ?? 'Épisode $number').toString(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary)),
      trailing: const Icon(Icons.play_circle_outline),
      onTap: () => _playEpisode(
        ep,
        position: isTarget &&
                resume != null &&
                resume.watchProgress < 0.95 &&
                resume.watchTime > 5
            ? Duration(seconds: resume.watchTime.round())
            : null,
      ),
    );
  }
}
