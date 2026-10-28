import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../mizu_config.dart';
import '../state/app_state.dart';
import 'home_blocks.dart';
import 'open_content.dart';
import 'tv_focus.dart';
import 'cached_image.dart';

/// Accueil : blocs de covers configurables (ordre + activation).
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.state});

  final AppState state;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const double _coverWidth = 190;

  final Map<String, ContentMeta?> _metas = {};
  final Set<String> _requested = {};
  final Map<String, List<ContentMeta>> _tmdbLists = {};
  bool _listsStarted = false;

  AppState get state => widget.state;

  static String _typeOfProgress(ProgressItem p) =>
      p.kind == 'vod' ? 'vod' : 'serie';

  @override
  void initState() {
    super.initState();
    _loadTmdbLists();
  }

  Future<void> _loadTmdbLists() async {
    if (_listsStarted) return;
    _listsStarted = true;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final queries = <String, (List<String>, String?)>{
      'latestMovies': (<String>[
        'discover/movie?language=fr-FR&region=FR&sort_by=release_date.desc&primary_release_date.lte=$today&vote_count.gte=10&page=1',
        'discover/movie?language=fr-FR&region=FR&sort_by=release_date.desc&primary_release_date.lte=$today&vote_count.gte=10&page=2',
        'discover/movie?language=fr-FR&region=FR&sort_by=release_date.desc&primary_release_date.lte=$today&vote_count.gte=10&page=3',
      ], 'vod'),
      'latestSeries': (<String>[
        'discover/tv?language=fr-FR&sort_by=first_air_date.desc&first_air_date.lte=$today&vote_count.gte=10&page=1',
        'discover/tv?language=fr-FR&sort_by=first_air_date.desc&first_air_date.lte=$today&vote_count.gte=10&page=2',
        'discover/tv?language=fr-FR&sort_by=first_air_date.desc&first_air_date.lte=$today&vote_count.gte=10&page=3',
      ], 'serie'),
      'trending': (<String>[
        'trending/all/week?language=fr-FR&page=1',
        'trending/all/week?language=fr-FR&page=2',
      ], null),
    };
    for (final entry in queries.entries) {
      final (paths, forcedType) = entry.value;
      final merged = <int, ContentMeta>{};
      for (final path in paths) {
        final list =
            await state.metadata.fetchList(path, forcedType: forcedType);
        if (!mounted) return;
        for (final meta in list) {
          merged.putIfAbsent(meta.tmdbId, () => meta);
        }
      }
      if (!mounted) return;
      setState(() => _tmdbLists[entry.key] = merged.values.toList());
    }
  }

  void _ensureMeta(String type, String id) {
    final key = '$type:$id';
    if (_requested.contains(key)) return;
    _requested.add(key);
    state.metadata.fetch(type, id).then((meta) {
      if (!mounted) return;
      setState(() => _metas[key] = meta);
    }).catchError((_) => null);
  }

  String _titleFor(String type, String id) {
    final meta = _metas['$type:$id'];
    final entry = CatalogIndex.instance.lookup(type, id);
    return meta?.title ?? entry?.name ?? id;
  }

  String? _posterFor(String type, String id) {
    final meta = _metas['$type:$id'];
    final entry = CatalogIndex.instance.lookup(type, id);
    return meta?.poster ?? entry?.poster;
  }

  @override
  Widget build(BuildContext context) {
    // Prépare les titres/affiches des favoris et reprises.
    for (final f in state.favorites) {
      if (f.contentType != 'channel') {
        _ensureMeta(f.contentType, f.contentId);
      }
    }
    for (final p in state.progress) {
      _ensureMeta(_typeOfProgress(p), p.serieId);
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        state,
        CatalogIndex.instance,
        MizuConfig.homeBlockOrderListenable,
        MizuConfig.homeBlocksDisabledListenable,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final blocks = _buildBlocks();
        if (blocks.isEmpty) return _empty(theme);

        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          itemCount: blocks.length,
          itemBuilder: (context, i) =>
              _block(theme, blocks[i].key, blocks[i].items),
        );
      },
    );
  }

  List<({String key, List<_HomeItem> items})> _buildBlocks() {
    final disabled = MizuConfig.homeBlocksDisabled.toSet();
    final out = <({String key, List<_HomeItem> items})>[];
    for (final key in MizuConfig.homeBlockOrder) {
      if (disabled.contains(key)) continue;
      final items = _itemsFor(key);
      if (items.isNotEmpty) out.add((key: key, items: items));
    }
    return out;
  }

  bool _available(String type, String id) {
    final entry = CatalogIndex.instance.lookup(type, id);
    return entry != null && entrySourceAvailable(entry, state);
  }

  List<_HomeItem> _itemsFor(String key) {
    const limit = 18;
    final items = <_HomeItem>[];

    void addContent(String type, String id,
        {double? progress, int? initialSeason}) {
      final entry = CatalogIndex.instance.lookup(type, id);
      if (entry == null || !entrySourceAvailable(entry, state)) return;
      items.add(_HomeItem(
        title: _titleFor(type, id),
        type: type,
        contentId: id,
        poster: _posterFor(type, id),
        progress: progress,
        initialSeason: initialSeason,
      ));
    }

    switch (key) {
      case 'latestMovies':
      case 'latestSeries':
      case 'trending':
        for (final meta in _tmdbLists[key] ?? const <ContentMeta>[]) {
          final type = meta.type;
          final id = '${meta.tmdbId}';
          if (!_available(type, id)) continue;
          items.add(_HomeItem(
            title: meta.title,
            type: type,
            contentId: id,
            poster: meta.poster,
          ));
          if (items.length >= limit) break;
        }
        break;
      case 'resumeMovies':
        for (final p in state.progress.where((p) => p.kind == 'vod')) {
          addContent('vod', p.serieId,
              progress: p.watchProgress, initialSeason: p.season);
          if (items.length >= limit) break;
        }
        break;
      case 'resumeSeries':
        for (final p in state.progress.where((p) => p.kind == 'serie')) {
          addContent('serie', p.serieId,
              progress: p.watchProgress, initialSeason: p.season);
          if (items.length >= limit) break;
        }
        break;
      case 'favoriteMovies':
        for (final f in state.favorites.where((f) => f.contentType == 'vod')) {
          addContent('vod', f.contentId);
          if (items.length >= limit) break;
        }
        break;
      case 'favoriteSeries':
        for (final f
            in state.favorites.where((f) => f.contentType == 'serie')) {
          addContent('serie', f.contentId);
          if (items.length >= limit) break;
        }
        break;
      case 'favoriteChannels':
        for (final f
            in state.favorites.where((f) => f.contentType == 'channel')) {
          items.add(_HomeItem(
            title: f.contentId,
            type: 'channel',
            contentId: f.contentId,
          ));
          if (items.length >= limit) break;
        }
        break;
    }
    return items;
  }

  Widget _block(ThemeData theme, String key, List<_HomeItem> items) {
    final def = homeBlockDef(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(def.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(def.label, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        SizedBox(
          height: _coverWidth * 1.5 + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _cover(
              context,
              theme,
              items[i],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cover(BuildContext context, ThemeData theme, _HomeItem item) {
    final placeholder = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        item.type == 'vod'
            ? Icons.movie_outlined
            : item.type == 'serie'
                ? Icons.video_library_outlined
                : Icons.live_tv_outlined,
        color: theme.colorScheme.primary,
      ),
    );

    return SizedBox(
      width: _coverWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvFocus(
            borderRadius: 10,
            onActivate: () => _openItem(context, item),
            child: InkWell(
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(10),
              mouseCursor: SystemMouseCursors.click,
              onTap: () => _openItem(context, item),
              child: SizedBox(
                width: _coverWidth,
                height: _coverWidth * 1.5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.poster == null || item.poster!.isEmpty)
                        placeholder
                      else
                        CachedImage(
                          item.poster!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => placeholder,
                        ),
                      if (item.progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: item.progress!.clamp(0, 1),
                            minHeight: 5,
                            backgroundColor: Colors.black38,
                          ),
                        ),
                      if (item.type == 'channel')
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'DIRECT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _openItem(BuildContext context, _HomeItem item) {
    if (item.type == 'channel') {
      openChannel(context, state, item.contentId);
      return;
    }
    final entry = CatalogIndex.instance.lookup(item.type, item.contentId);
    if (entry == null || !entrySourceAvailable(entry, state)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contenu indisponible (source manquante).')),
      );
      return;
    }
    openContent(context, state,
        kind: item.type, entry: entry, initialSeason: item.initialSeason);
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Accueil vide', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Active des blocs dans Préférences → Préférences → Accueil.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeItem {
  _HomeItem({
    required this.title,
    required this.type,
    required this.contentId,
    this.poster,
    this.progress,
    this.initialSeason,
  });

  final String title;
  final String type;
  final String contentId;
  final String? poster;
  final double? progress;
  final int? initialSeason;
}
