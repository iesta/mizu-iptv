import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../mizu_config.dart';
import '../state/app_state.dart';
import 'catalog_options.dart';
import 'open_content.dart';
import 'tv_focus.dart';
import 'cached_image.dart';

/// Reprise de lecture : liste (défaut) ou grille avec covers, recherche, tri et
/// taille de vignettes réglables.
class ContinueTab extends StatefulWidget {
  const ContinueTab({super.key, required this.state});

  final AppState state;

  @override
  State<ContinueTab> createState() => _ContinueTabState();
}

class _ContinueTabState extends State<ContinueTab> {
  final TextEditingController _search = TextEditingController();
  final Map<String, ContentMeta?> _metas = {};
  final Set<String> _requested = {};
  String _filter = '';

  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _typeOf(ProgressItem p) => p.kind == 'vod' ? 'vod' : 'serie';
  static String _keyOf(ProgressItem p) => '${_typeOf(p)}:${p.serieId}';

  /// Charge les métadonnées (titre/affiche/note) une fois par contenu.
  void _ensureMetas() {
    for (final p in state.progress) {
      final key = _keyOf(p);
      if (_requested.contains(key)) continue;
      _requested.add(key);
      state.metadata.fetch(_typeOf(p), p.serieId).then((meta) {
        if (!mounted) return;
        setState(() => _metas[key] = meta);
      }).catchError((_) => null);
    }
  }

  String _titleOf(ProgressItem p) {
    final meta = _metas[_keyOf(p)];
    final entry = CatalogIndex.instance.lookup(_typeOf(p), p.serieId);
    return meta?.title ??
        entry?.name ??
        '${_typeOf(p) == 'vod' ? 'Film' : 'Série'} ${p.serieId}';
  }

  String? _posterOf(ProgressItem p) {
    final meta = _metas[_keyOf(p)];
    final entry = CatalogIndex.instance.lookup(_typeOf(p), p.serieId);
    return meta?.poster ?? entry?.poster;
  }

  double _voteOf(ProgressItem p) => _metas[_keyOf(p)]?.vote ?? 0;
  int _lastOf(ProgressItem p) => p.lastWatched?.millisecondsSinceEpoch ?? 0;

  List<ProgressItem> _visibleItems() {
    final needle = _filter.toLowerCase();
    final list = state.progress.where((p) {
      if (needle.isEmpty) return true;
      return _titleOf(p).toLowerCase().contains(needle);
    }).toList();

    final sort = MizuConfig.catalogSort;
    list.sort((a, b) {
      switch (sort) {
        case 'oldest':
          return _lastOf(a).compareTo(_lastOf(b));
        case 'name_asc':
          return _titleOf(a).toLowerCase().compareTo(_titleOf(b).toLowerCase());
        case 'name_desc':
          return _titleOf(b).toLowerCase().compareTo(_titleOf(a).toLowerCase());
        case 'rating_desc':
          final c = _voteOf(b).compareTo(_voteOf(a));
          return c != 0 ? c : _lastOf(b).compareTo(_lastOf(a));
        case 'rating_asc':
          final c = _voteOf(a).compareTo(_voteOf(b));
          return c != 0 ? c : _lastOf(b).compareTo(_lastOf(a));
        case 'recent':
        default:
          return _lastOf(b).compareTo(_lastOf(a));
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    _ensureMetas();
    return ListenableBuilder(
      listenable: Listenable.merge([
        CatalogIndex.instance,
        MizuConfig.thumbSizeListenable,
        MizuConfig.catalogSortListenable,
        MizuConfig.continueViewListenable,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        if (state.progress.isEmpty) return _emptyState(theme);

        final items = _visibleItems();
        final grid = MizuConfig.continueView == 'grid';
        return Column(
          children: [
            _toolbar(theme, items.length, grid),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('Aucun résultat',
                          style: theme.textTheme.bodyMedium),
                    )
                  : grid
                      ? _grid(theme, items)
                      : _list(items),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(ThemeData theme, int count, bool grid) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Rechercher…',
                border: const OutlineInputBorder(),
                suffixIcon: _filter.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _filter = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: grid ? 'Afficher en liste' : 'Afficher en grille',
            icon: Icon(grid ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              final next = grid ? 'list' : 'grid';
              MizuConfig.continueView = next;
              MizuConfig.save(continueView: next);
            },
          ),
          IconButton(
            tooltip: 'Options d\'affichage',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openOptions,
          ),
          Text('$count',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Future<void> _openOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Affichage', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: MizuConfig.continueViewListenable,
                builder: (context, view, _) => SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'list',
                        icon: Icon(Icons.view_list),
                        label: Text('Liste')),
                    ButtonSegment(
                        value: 'grid',
                        icon: Icon(Icons.grid_view),
                        label: Text('Grille')),
                  ],
                  selected: {view},
                  onSelectionChanged: (selection) {
                    final next = selection.first;
                    MizuConfig.continueView = next;
                    MizuConfig.save(continueView: next);
                  },
                ),
              ),
              const SizedBox(height: 20),
              Text('Taille des vignettes (grille)',
                  style: theme.textTheme.titleMedium),
              ValueListenableBuilder<double>(
                valueListenable: MizuConfig.thumbSizeListenable,
                builder: (context, size, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Slider(
                      min: MizuConfig.minThumbSize,
                      max: MizuConfig.maxThumbSize,
                      divisions:
                          ((MizuConfig.maxThumbSize -
                                      MizuConfig.minThumbSize) /
                                  10)
                              .round(),
                      value: size,
                      label: '${size.round()} px',
                      onChanged: (v) => MizuConfig.thumbSize = v,
                      onChangeEnd: (v) {
                        MizuConfig.save(thumbSize: v);
                      },
                    ),
                    Text('${size.round()} px',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Divider(height: 28),
              Text('Tri', style: theme.textTheme.titleMedium),
              ValueListenableBuilder<String>(
                valueListenable: MizuConfig.catalogSortListenable,
                builder: (context, sort, _) => Column(
                  children: [
                    for (final option in continueSortOptions)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(sort == option.value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                        title: Text(option.label),
                        onTap: () {
                          MizuConfig.catalogSort = option.value;
                          MizuConfig.save(catalogSort: option.value);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(List<ProgressItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _ProgressTile(
        state: state,
        item: items[i],
        title: _titleOf(items[i]),
        poster: _posterOf(items[i]),
        autofocus: i == 0,
      ),
    );
  }

  Widget _grid(ThemeData theme, List<ProgressItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: MizuConfig.thumbSize,
        childAspectRatio: 0.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _ProgressCard(
        state: state,
        item: items[i],
        title: _titleOf(items[i]),
        poster: _posterOf(items[i]),
        autofocus: i == 0,
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Rien à reprendre', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'La progression vient de `serie_progress` (par profil).',
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

/// Mode liste : ligne actuelle (affiche, titre, progression, infos).
class _ProgressTile extends StatelessWidget {
  const _ProgressTile({
    required this.state,
    required this.item,
    required this.title,
    required this.poster,
    this.autofocus = false,
  });

  final AppState state;
  final ProgressItem item;
  final String title;
  final String? poster;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = item;
    final type = _ContinueTabState._typeOf(p);
    final entry = CatalogIndex.instance.lookup(type, p.serieId);
    final hasEntry = entry != null && entry.candidates.isNotEmpty;
    final sourceOk = entry != null &&
        entry.candidates.isNotEmpty &&
        entrySourceAvailable(entry, state);
    final sourceMissing = hasEntry && !sourceOk;
    final canOpen = sourceOk;

    void activate() {
      if (!canOpen) return;
      openContent(context, state,
          kind: type, entry: entry, initialSeason: p.season);
    }

    return TvFocus(
      autofocus: autofocus,
      enabled: canOpen,
      onActivate: activate,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          canRequestFocus: false,
          onTap: canOpen ? activate : null,
          mouseCursor:
              canOpen ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 64,
                    child: _posterImage(theme, type, 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _progressInfo(p, entry, sourceMissing: sourceMissing),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              sourceMissing ? theme.colorScheme.error : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: p.watchProgress.clamp(0, 1),
                          minHeight: 4,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      if (sourceMissing)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                _confirmDeleteProgress(context, state, p),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: const Size(0, 30),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Supprimer la reprise'),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ligne brute',
                  icon: const Icon(Icons.data_object, size: 20),
                  onPressed: () => _showRaw(context, p.raw),
                ),
                if (canOpen) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _posterImage(ThemeData theme, String type, double iconSize) {
    final url = poster;
    if (url == null || url.isEmpty) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          type == 'vod' ? Icons.movie_outlined : Icons.video_library_outlined,
          size: iconSize,
          color: theme.colorScheme.primary,
        ),
      );
    }
    return CachedImage(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.movie_outlined, size: iconSize),
      ),
    );
  }
}

/// Mode grille : cover + progression + infos de la liste.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.state,
    required this.item,
    required this.title,
    required this.poster,
    this.autofocus = false,
  });

  final AppState state;
  final ProgressItem item;
  final String title;
  final String? poster;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = item;
    final type = _ContinueTabState._typeOf(p);
    final entry = CatalogIndex.instance.lookup(type, p.serieId);
    final hasEntry = entry != null && entry.candidates.isNotEmpty;
    final sourceOk = entry != null &&
        entry.candidates.isNotEmpty &&
        entrySourceAvailable(entry, state);
    final sourceMissing = hasEntry && !sourceOk;
    final canOpen = sourceOk;
    final percent = (p.watchProgress.clamp(0, 1) * 100).round();

    void activate() {
      if (!canOpen) return;
      openContent(context, state,
          kind: type, entry: entry, initialSeason: p.season);
    }

    return TvFocus(
      autofocus: autofocus,
      enabled: canOpen,
      onActivate: activate,
      child: InkWell(
        canRequestFocus: false,
        onTap: canOpen ? activate : null,
        mouseCursor:
            canOpen ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (poster == null || poster!.isEmpty)
                      Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          type == 'vod'
                              ? Icons.movie_outlined
                              : Icons.video_library_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else
                      CachedImage(
                        poster!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined),
                        ),
                      ),
                    if (sourceMissing)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                _confirmDeleteProgress(context, state, p),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.delete_outline,
                                  size: 20, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: p.watchProgress.clamp(0, 1),
                                minHeight: 9,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.play_circle_outline,
                                    size: 13, color: Colors.white70),
                                const SizedBox(width: 3),
                                Text(
                                  '$percent %',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _kindLabel(p),
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              _progressInfo(p, entry, sourceMissing: sourceMissing),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: sourceMissing
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _kindLabel(ProgressItem p) =>
    p.kind == 'vod' ? 'Film' : 'S${p.season} E${p.episode}';

String _progressInfo(ProgressItem p, IndexEntry? entry,
    {bool sourceMissing = false}) {
  return [
    _kindLabel(p),
    _mmss(p.watchTime),
    if (sourceMissing)
      'source supprimée'
    else if (entry != null && entry.candidates.isNotEmpty)
      entry.candidates.first.sourceName,
    if (p.lastWatched != null) _ago(p.lastWatched!),
  ].join(' · ');
}

Future<void> _confirmDeleteProgress(
    BuildContext context, AppState state, ProgressItem p) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Supprimer la reprise ?'),
      content: const Text(
        'Ce contenu n\'est plus disponible (source supprimée). '
        'Retirer cette ligne de « Reprendre » ?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (ok == true) await state.deleteProgress(p.serieId);
}

String _mmss(double seconds) {
  final s = seconds.round();
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}

void _showRaw(BuildContext context, Map<String, dynamic> raw) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Ligne serie_progress'),
      content: SelectableText(
        raw.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}
