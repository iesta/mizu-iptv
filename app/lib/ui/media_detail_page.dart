import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/metadata_service.dart';
import '../data/models.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';
import 'player_page.dart';
import 'cached_image.dart';

enum MediaKind { vod, serie }

/// Une version d'une série (qualité/langue) : un `series_id` distinct pour un
/// même contenu TMDB (ex. « X (FR) FHD » et « X (MULTI) FHD »).
class SeriesVersion {
  const SeriesVersion({required this.id, required this.name, this.poster});

  final int id;
  final String name;
  final String? poster;
}

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
    this.versions = const [],
  });

  final AppState state;
  final XtreamClient client;
  final MediaKind kind;
  final int id;
  final String fallbackName;
  final String? fallbackPoster;

  /// Saison à présélectionner (reprise de lecture).
  final int? initialSeason;

  /// Versions connues de la série (même TMDB, `series_id` différents).
  final List<SeriesVersion> versions;

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
  int _seriesId = 0;
  List<SeriesVersion> _versions = const [];
  String? _error;
  bool _loading = true;
  bool _autoPlayed = false;
  bool _showAllCast = false;
  Credits? _credits;
  List<VideoTrailer> _trailers = const [];
  String? _backdrop;
  double? _vote;
  String? _cert;
  late XtreamClient _client = widget.client;
  late final List<XtreamClient> _fallbacks = List.of(widget.fallbackClients);
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _seriesId = widget.id;
    _versions = List<SeriesVersion>.of(widget.versions);
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
        final json = await _client.seriesInfo(_seriesId);
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
    if (widget.kind == MediaKind.serie && _versions.isEmpty) {
      _loadVersions();
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
    final videos = await widget.state.metadata.fetchVideos(type, tmdb);
    if (!mounted) return;
    setState(() {
      _backdrop = MetadataService.posterUrl(meta?.backdropPath, size: 'w1280');
      _vote = meta?.vote;
      _cert = cert;
      if (credits != null && !credits.isEmpty) _credits = credits;
      if (videos.isNotEmpty) _trailers = videos;
    });
  }

  /// Découvre les autres versions (même TMDB, `series_id` différents) quand
  /// elles n'ont pas été fournies par le catalogue.
  Future<void> _loadVersions() async {
    final tmdb = _tmdbId;
    final nameKey = _normalizeName(_title);
    try {
      final list = await _client.series();
      final out = <SeriesVersion>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final id = int.tryParse((item['series_id'] ?? '').toString());
        if (id == null) continue;
        final itemTmdb = (item['tmdb'] ?? item['tmdb_id'])?.toString();
        final matches = (tmdb != null && itemTmdb == tmdb) ||
            _normalizeName((item['name'] ?? '').toString()) == nameKey;
        if (!matches) continue;
        if (out.any((v) => v.id == id)) continue;
        out.add(SeriesVersion(
          id: id,
          name: (item['name'] ?? '').toString(),
          poster: (item['cover'] ?? item['stream_icon'])?.toString(),
        ));
      }
      if (!mounted || out.isEmpty) return;
      setState(() => _versions = out);
    } catch (_) {
      // Pas de sélecteur de version si la liste est indisponible.
    }
  }

  /// Nom comparé sans qualité/version : « X (FR) FHD » → « x ».
  static String _normalizeName(String raw) {
    var name = raw.toLowerCase();
    name = name.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    name = name.replaceAll(
        RegExp(r'\b(fhd|uhd|4k|hd|sd|multi|vf|vostfr|fr|truefrench)\b'), ' ');
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Change de version (autre `series_id`) et recharge la fiche.
  void _selectVersion(SeriesVersion version) {
    if (version.id == _seriesId) return;
    setState(() {
      _seriesId = version.id;
      _info = null;
      _data = null;
      _episodes = {};
      _season = 1;
      _credits = null;
      _trailers = const [];
      _backdrop = null;
      _vote = null;
      _cert = null;
      _error = null;
      _autoPlayed = true;
    });
    _load();
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

  /// Ouvre la fiche TMDB du film ou de la série dans le navigateur.
  Future<void> _openTmdb() async {
    final tmdb = _tmdbId;
    if (tmdb == null) return;
    final kind = widget.kind == MediaKind.vod ? 'movie' : 'tv';
    final uri = Uri.parse('https://www.themoviedb.org/$kind/$tmdb');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Aucun navigateur disponible : on ignore.
    }
  }

  /// Trailers TMDB, ou repli sur `youtube_trailer` fourni par le panneau.
  List<VideoTrailer> get _availableTrailers {
    if (_trailers.isNotEmpty) return _trailers;
    final raw = _info?['youtube_trailer']?.toString().trim();
    if (raw == null || raw.isEmpty) return const [];
    final key = _youtubeKeyOf(raw);
    if (key == null) return const [];
    return [
      VideoTrailer(key: key, site: 'YouTube', type: 'Trailer', name: _title),
    ];
  }

  /// Extrait l'id YouTube d'une URL (`?v=`, `youtu.be/…`) ou d'un id brut.
  String? _youtubeKeyOf(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      if (uri.host.toLowerCase().contains('youtu.be')) {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        if (id != null && id.isNotEmpty) return id;
      }
      return null;
    }
    return raw.length >= 8 && !raw.contains('/') ? raw : null;
  }

  /// Ouvre une bande-annonce (choix si plusieurs) dans le navigateur.
  Future<void> _openTrailer() async {
    final trailers = _availableTrailers;
    if (trailers.isEmpty) return;
    VideoTrailer chosen = trailers.first;
    if (trailers.length > 1) {
      final selected = await showModalBottomSheet<VideoTrailer>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                dense: true,
                title: Text('Bande-annonces'),
                titleTextStyle: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final t in trailers)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(
                    (t.name?.isNotEmpty ?? false) ? t.name! : 'Bande-annonce',
                  ),
                  subtitle: Text(
                    [
                      if (t.type.isNotEmpty) t.type,
                      if (t.language != null && t.language!.isNotEmpty)
                        t.language!.toUpperCase(),
                    ].join(' · '),
                  ),
                  onTap: () => Navigator.of(context).pop(t),
                ),
            ],
          ),
        ),
      );
      if (selected == null) return;
      chosen = selected;
    }
    try {
      await launchUrl(
        Uri.parse(chosen.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Aucun navigateur disponible : on ignore.
    }
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

  void _playMovie({bool fromStart = false}) {
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
        initialPosition: (!fromStart && resume != null && resume.watchTime > 5)
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

  void _playTarget({bool fromStart = false}) {
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
      position: (!fromStart && t.position > 5)
          ? Duration(seconds: t.position.round())
          : null,
    );
  }

  /// Premier épisode disponible (plus petite saison), sans reprise.
  void _playFirstEpisode() {
    final seasons =
        _episodes.keys.map(int.tryParse).whereType<int>().toList()..sort();
    for (final season in seasons) {
      final list = _episodes['$season'] ?? const [];
      if (list.isNotEmpty) {
        _playEpisode(list.first);
        return;
      }
    }
  }

  /// Espace : lecture / reprise ; Ctrl+Espace : depuis le début.
  void _playOrResume({required bool fromStart}) {
    if (_loading || _error != null) return;
    if (widget.kind == MediaKind.vod) {
      _playMovie(fromStart: fromStart);
      return;
    }
    if (_target != null) {
      _playTarget(fromStart: fromStart);
    } else {
      _playFirstEpisode();
    }
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

  /// Échap / Retour : revient à la liste. Espace : lecture/reprise.
  /// Ctrl+Espace : lecture depuis le début.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      final fromStart = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      _playOrResume(fromStart: fromStart);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _target;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
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
                      textScaler: const TextScaler.linear(1.5),
                    ),
                    child: Stack(
                      children: [
                        // Image du film en fond de toute la page (y compris
                        // derrière la distribution).
                        Positioned.fill(child: _pageBackground(theme)),
                        ListView(
                        children: [
                          _header(theme, target),
                          if (widget.kind == MediaKind.serie)
                            _versionsSection(theme),
                          if (widget.kind == MediaKind.serie)
                            _episodesSection(theme),
                          _castSection(theme),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ],
                  ),
                ),
      ),
    );
  }

  /// Marge horizontale unique de la fiche (toutes les sections l'utilisent).
  static const double _pad = 20;

  /// En-tête : barre retour, titre + méta, puis affiche avec, à sa droite, les
  /// étiquettes de genre et le descriptif.
  Widget _header(ThemeData theme, _Target? target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Décalage de -14 pour que le glyphe du bouton retombe pile sur la
        // marge _pad du titre (le bouton a 14 px de padding interne).
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad - 14, 8, _pad, 0),
          child: _topBar(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 8, _pad, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleRow(theme, target),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _posterBox(theme),
                  const SizedBox(width: 20),
                  Expanded(child: _detailsColumn(theme, target)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Retour + favori en haut de la fiche. Pas de barre d'application : le
  /// cadre est géré par le gestionnaire de fenêtres.
  Widget _topBar() {
    final theme = Theme.of(context);
    return Row(
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            iconSize: 30,
            textStyle: theme.textTheme.titleLarge?.copyWith(
              fontSize: (theme.textTheme.titleLarge?.fontSize ?? 22) - 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minimumSize: const Size(0, 52),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('retour'),
        ),
        const Spacer(),
        if (_tmdbId != null)
          ListenableBuilder(
            listenable: widget.state,
            builder: (context, _) {
              final type = widget.kind == MediaKind.vod ? 'vod' : 'serie';
              final fav = widget.state.isFavorite(_tmdbId!, type);
              return IconButton(
                tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                iconSize: 32,
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(
                  minWidth: 56,
                  minHeight: 56,
                ),
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
                onPressed: () => widget.state.toggleFavorite(_tmdbId!, type),
              );
            },
          ),
      ],
    );
  }

  /// Genre(s) sous forme d'étiquettes arrondies, puis l'icône d'infos du flux.
  Widget _genreTags(ThemeData theme, List<String> genres) {
    final color = theme.colorScheme.onSurface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final genre in genres)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              genre,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  /// Styles du film, découpés en étiquettes.
  List<String> get _genres {
    final raw = _info?['genre']?.toString().trim() ?? '';
    if (raw.isEmpty) return const [];
    final seen = <String>{};
    return raw
        .split(RegExp(r'[,/|]| & '))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && seen.add(s))
        .toList();
  }

  /// Image du film en fond de toute la page, avec un dégradé marqué et haut
  /// pour rendre le titre et la méta lisibles.
  Widget _pageBackground(ThemeData theme) {
    final backdrop = _backdropUrl;
    final colors = theme.colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop != null)
          CachedImage(
            backdrop,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.99),
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.95),
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.72),
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.45),
                colors.surface.withValues(alpha: backdrop == null ? 1 : 0.78),
                colors.surface,
              ],
              stops: const [0.0, 0.2, 0.45, 0.65, 0.85, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  /// Titre (étoiles juste après) puis année (en gras) · durée.
  Widget _titleRow(ThemeData theme, _Target? target) {
    final colors = theme.colorScheme;
    final rating = _rating;

    final play = widget.kind == MediaKind.vod
        ? FilledButton.icon(
            style: _playButtonStyle(theme),
            onPressed: () => _playMovie(),
            icon: const Icon(Icons.play_arrow),
            label: Text(_resume == null ? 'Lecture' : 'Reprendre'),
          )
        : target != null
            ? FilledButton.icon(
                style: _playButtonStyle(theme),
                onPressed: () => _playTarget(),
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
              Text.rich(
                TextSpan(
                  style: theme.textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  children: [
                    TextSpan(text: _title),
                    // Étoiles juste après le titre, suivies de la note.
                    // Cliquables : ouvre la fiche TMDB.
                    if (rating != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: MouseRegion(
                          cursor: _tmdbId == null
                              ? MouseCursor.defer
                              : SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _tmdbId == null ? null : _openTmdb,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: 14, top: 2, bottom: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _stars(rating),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${rating.toStringAsFixed(1)}/10',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: colors.onSurface
                                          .withValues(alpha: 0.88),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_year != null || _duration != null || _cert != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_year != null || _duration != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            if (_year != null)
                              TextSpan(
                                text: _year,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            if (_year != null && _duration != null)
                              const TextSpan(text: ' · '),
                            if (_duration != null) TextSpan(text: _duration),
                          ],
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    if (_cert != null) _certBadge(theme),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (play != null) _HoverLift(child: play),
              if (play != null) const SizedBox(width: 10),
              _moreMenuButton(theme),
            ],
          ),
        ),
      ],
    );
  }

  /// Bouton rond « … » : actions secondaires de la fiche.
  Widget _moreMenuButton(ThemeData theme) {
    final tmdb = _tmdbId;
    final type = widget.kind == MediaKind.vod ? 'vod' : 'serie';
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final hasResume = _hasResume;
        final favorite = tmdb != null && widget.state.isFavorite(tmdb, type);
        final resumeSeconds = widget.kind == MediaKind.vod
            ? (_resume?.watchTime ?? 0)
            : (_target?.position ?? 0);
        return MenuAnchor(
          alignmentOffset: const Offset(0, 8),
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.replay),
              onPressed: () => _playOrResume(fromStart: true),
              child: const Text('Jouer du début'),
            ),
            if (hasResume)
              MenuItemButton(
                leadingIcon: const Icon(Icons.play_arrow),
                onPressed: () => _playOrResume(fromStart: false),
                child: Text(
                  resumeSeconds > 0
                      ? 'Reprendre · ${_fmtResume(resumeSeconds)}'
                      : 'Reprendre',
                ),
              ),
            if (hasResume)
              MenuItemButton(
                leadingIcon: const Icon(Icons.remove_circle_outline),
                onPressed: _clearProgress,
                child: const Text('Annuler le suivi'),
              ),
            if (tmdb != null)
              MenuItemButton(
                leadingIcon:
                    Icon(favorite ? Icons.favorite_border : Icons.favorite),
                onPressed: () => widget.state.toggleFavorite(tmdb, type),
                child: Text(
                    favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'),
              ),
          ],
          builder: (context, controller, child) => IconButton.filled(
            iconSize: 28,
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minWidth: 60, minHeight: 60),
            tooltip: 'Plus d\'actions',
            icon: const Icon(Icons.more_horiz),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        );
      },
    );
  }

  bool get _hasResume =>
      widget.kind == MediaKind.vod ? _resume != null : _target != null;

  Future<void> _clearProgress() async {
    final tmdb = _tmdbId;
    if (tmdb == null) return;
    await widget.state.deleteProgress(tmdb);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Suivi annulé.')),
    );
  }

  /// Affiche verticale (300×450) avec repli si absente.
  Widget _posterBox(ThemeData theme) {
    final fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.movie_outlined, size: 32),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 300,
        height: 450,
        child: _poster == null
            ? fallback
            : CachedImage(
                _poster!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  /// Étiquettes de genre, descriptif et infos de reprise, à droite de l'affiche.
  Widget _detailsColumn(ThemeData theme, _Target? target) {
    final light = theme.colorScheme.onSurface.withValues(alpha: 0.9);
    final genres = _genres;
    final plot = _plot;
    final trailers = _availableTrailers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toujours affiché : l'icône « i » (infos flux) vit à côté des tags.
        _genreTags(theme, genres),
        const SizedBox(height: 12),
        if (plot != null) ...[
          Text(
            plot,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (trailers.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 34),
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) + 1,
                ),
              ),
              onPressed: _openTrailer,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.movie_filter_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Text('Bande-annonce'),
                  if (trailers.length > 1) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.kind == MediaKind.serie && target != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              target.isNext
                  ? 'épisode suivant'
                  : target.position > 5
                      ? 'à ${_mmss(target.position)}'
                      : 'depuis le début',
              style: theme.textTheme.bodyMedium?.copyWith(color: light),
            ),
          ),
        if (_tmdbId == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Pas d\'identifiant TMDB : favoris et reprise '
              'ne seront pas synchronisés.',
              style: theme.textTheme.bodyMedium?.copyWith(color: light),
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

  /// Cinq étoiles remplies selon la note sur 10 (chaque étoile = 2 points).
  Widget _stars(double rating10) {
    final stars = rating10 / 2;
    const amber = Color(0xFFFFC107);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              children: [
                Icon(Icons.star_rounded,
                    size: 24, color: amber.withValues(alpha: 0.22)),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: (stars - i).clamp(0.0, 1.0),
                    child: const Icon(Icons.star_rounded,
                        size: 24, color: amber),
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

  /// Note sur 10 : `rating_5based`/`rating` Xtream, sinon vote TMDB (/10).
  double? get _rating {
    final five = double.tryParse(_info?['rating_5based']?.toString() ?? '');
    double? raw;
    if (five != null && five > 0) {
      raw = five * 2;
    } else {
      final xtream = double.tryParse(_info?['rating']?.toString() ?? '');
      if (xtream != null && xtream > 0) {
        raw = xtream > 5 ? xtream : xtream * 2;
      } else {
        raw = _vote; // TMDB, déjà sur 10
      }
    }
    if (raw == null || raw <= 0) return null;
    return raw.clamp(0.0, 10.0);
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

  /// Nombre d'acteurs affichés avant « Voir plus ».
  static const int _castPreview = 10;

  Widget _castSection(ThemeData theme) {
    final directors = _directors;
    final composers = _composers;
    final cast = _cast;
    if (directors.isEmpty && composers.isEmpty && cast.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasMore = cast.length > _castPreview;
    final visible = _showAllCast || !hasMore
        ? cast
        : cast.take(_castPreview).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, 8, _pad, 8),
          child: Text('Distribution', style: theme.textTheme.titleMedium),
        ),
        if (directors.isNotEmpty) _crewLine(theme, 'Réalisation', directors),
        if (composers.isNotEmpty) _crewLine(theme, 'Musique', composers),
        if (visible.isNotEmpty)
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 8),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _personTile(theme, visible[i]),
            ),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.fromLTRB(_pad, 0, _pad, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showAllCast = !_showAllCast),
                icon: Icon(_showAllCast ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _showAllCast
                      ? 'Voir moins'
                      : 'Voir plus (${cast.length - _castPreview})',
                ),
              ),
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
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
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
                  : CachedImage(
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
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

  /// Temps de reprise lisible : `1:23` ou `1:02:03`.
  static String _fmtResume(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  /// Sélecteur de version (qualité/langue) quand plusieurs `series_id`
  /// partagent le même contenu TMDB.
  Widget _versionsSection(ThemeData theme) {
    if (widget.kind != MediaKind.serie || _versions.length < 2) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pad, 4, _pad, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final version in _versions)
                ChoiceChip(
                  label: Text(version.name),
                  selected: version.id == _seriesId,
                  onSelected: (_) => _selectVersion(version),
                ),
            ],
          ),
        ],
      ),
    );
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

/// Léger effet de survol (échelle + halo) pour le bouton de lecture.
class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child});

  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.04 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

