import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';
import 'media_detail_page.dart';
import 'tv_focus.dart';
import 'player_page.dart';

/// Navigation d'une source Xtream : Live TV, Films, Séries.
class XtreamBrowserPage extends StatefulWidget {
  const XtreamBrowserPage({
    super.key,
    required this.state,
    required this.source,
    this.initialTab = 0,
    this.autoPlayFilter,
  });

  final AppState state;
  final PlaylistSource source;
  final int initialTab;

  /// Dev uniquement : ouvre le premier élément dont le nom contient ce filtre.
  final String? autoPlayFilter;

  @override
  State<XtreamBrowserPage> createState() => _XtreamBrowserPageState();
}

class _XtreamBrowserPageState extends State<XtreamBrowserPage> {
  late final XtreamClient _client = XtreamClient(
    baseUrl: widget.source.endpoint,
    username: widget.source.username ?? '',
    password: widget.source.password ?? '',
    userAgent: widget.source.raw['user_agent']?.toString(),
  );

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.source.name),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.live_tv_outlined), text: 'Live TV'),
              Tab(icon: Icon(Icons.movie_outlined), text: 'Films'),
              Tab(icon: Icon(Icons.video_library_outlined), text: 'Séries'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CatalogTab(
              client: _client,
              kind: _Kind.live,
              autoPlayFilter: widget.initialTab == 0 ? widget.autoPlayFilter : null,
              loadCategories: _client.liveCategories,
              loadItems: (cat) => _client.liveStreams(categoryId: cat),
              state: widget.state,
            ),
            _CatalogTab(
              client: _client,
              kind: _Kind.vod,
              autoPlayFilter: widget.initialTab == 1 ? widget.autoPlayFilter : null,
              loadCategories: _client.vodCategories,
              loadItems: (cat) => _client.vodStreams(categoryId: cat),
              state: widget.state,
            ),
            _CatalogTab(
              client: _client,
              kind: _Kind.serie,
              autoPlayFilter: widget.initialTab == 2 ? widget.autoPlayFilter : null,
              loadCategories: _client.seriesCategories,
              loadItems: (cat) => _client.series(categoryId: cat),
              state: widget.state,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { live, vod, serie }

class _CatalogTab extends StatefulWidget {
  const _CatalogTab({
    required this.client,
    required this.kind,
    required this.loadCategories,
    required this.loadItems,
    required this.state,
    this.autoPlayFilter,
  });

  final XtreamClient client;
  final _Kind kind;
  final Future<List<dynamic>> Function() loadCategories;
  final Future<List<dynamic>> Function(String? categoryId) loadItems;
  final AppState state;
  final String? autoPlayFilter;

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> {
  List<dynamic>? _categories;
  List<dynamic>? _items;
  String? _categoryId;
  String _filter = '';
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Un seul chargement par section : catégories + catalogue complet.
  /// Le filtrage par catégorie et la recherche sont faits en local (aucune
  /// requête supplémentaire, le panneau Xtream coupe quand on l'interroge trop).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _categories = await widget.loadCategories();
      final items = await widget.loadItems(null);
      setState(() {
        _items = items;
        _sortedCache = null;
      });
      _maybeAutoPlay(items);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _autoPlayed = false;

  void _maybeAutoPlay(List<dynamic> items) {
    final filter = widget.autoPlayFilter;
    if (filter == null || filter.isEmpty || _autoPlayed) return;
    _autoPlayed = true;
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      if (_name(item).toLowerCase().contains(filter.toLowerCase())) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _open(item);
        });
        return;
      }
    }
  }

  String _name(Map<String, dynamic> item) =>
      (item['name'] ?? item['title'] ?? '?').toString();

  String? _icon(Map<String, dynamic> item) {
    final raw = (item['stream_icon'] ?? item['cover'] ?? item['cover_big'])
        ?.toString();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  String _id(Map<String, dynamic> item) => (item['stream_id'] ??
          item['series_id'] ??
          item['id'] ??
          item['num'] ??
          '')
      .toString();

  List<Map<String, dynamic>>? _sortedCache;

  /// Horodatage d'ajout du média (secondes Unix), 0 si absent.
  static int _addedAt(Map<String, dynamic> item) {
    for (final key in const ['added', 'last_modified', 'lastModified']) {
      final raw = item[key];
      final value = int.tryParse(raw?.toString() ?? '');
      if (value != null && value > 0) return value;
    }
    final date = item['releaseDate']?.toString();
    if (date != null && date.length >= 4) {
      return int.tryParse(date.substring(0, 4)) ?? 0;
    }
    return 0;
  }

  /// Tout le catalogue, du plus récemment ajouté au plus ancien.
  List<Map<String, dynamic>> get _all {
    final cached = _sortedCache;
    if (cached != null) return cached;
    final list = (_items ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    list.sort((a, b) => _addedAt(b).compareTo(_addedAt(a)));
    _sortedCache = list;
    return list;
  }

  bool get _isLive => widget.kind == _Kind.live;
  String get _favoriteType => switch (widget.kind) {
        _Kind.live => 'channel',
        _Kind.vod => 'vod',
        _Kind.serie => 'serie',
      };

  String? _tmdbOf(Map<String, dynamic> item) {
    final raw = item['tmdb_id']?.toString();
    if (raw == null || raw.isEmpty || raw == '0') return null;
    return raw;
  }

  bool _isFavorite(Map<String, dynamic> item) {
    if (_isLive) return widget.state.isFavorite(_name(item), 'channel');
    final tmdb = _tmdbOf(item);
    if (tmdb == null) return false;
    return widget.state.isFavorite(tmdb, _favoriteType);
  }

  int get _favoriteCount => _all.where(_isFavorite).length;

  /// Nombre d'éléments par catégorie, calculé localement.
  Map<String, int> get _counts {
    final out = <String, int>{};
    for (final item in _all) {
      final id = item['category_id']?.toString();
      if (id == null) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  bool _favoritesOnly = false;

  List<Map<String, dynamic>> get _visible {
    final needle = _filter.toLowerCase();
    return _all.where((item) {
      if (_favoritesOnly && !_isFavorite(item)) return false;
      if (_categoryId != null && item['category_id']?.toString() != _categoryId) {
        return false;
      }
      if (needle.isEmpty) return true;
      return _name(item).toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> get _categoryList =>
      (_categories ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(growable: false);

  String _categoryLabel(Map<String, dynamic> c) =>
      (c['category_name'] ?? '?').toString();

  void _open(Map<String, dynamic> item) {
    final id = int.tryParse(_id(item));
    if (id == null) return;
    if (widget.kind == _Kind.live) {
      final ext = (item['container_extension']?.toString().isNotEmpty ?? false)
          ? item['container_extension'].toString()
          : 'ts';
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
          state: widget.state,
          url: widget.client.liveUrl(id, ext: ext),
          title: _name(item),
          subtitle: 'Direct',
          contentId: _name(item),
          contentType: 'channel',
        ),
      ));
    } else if (widget.kind == _Kind.vod) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaDetailPage(
          state: widget.state,
          client: widget.client,
          kind: MediaKind.vod,
          id: id,
          fallbackName: _name(item),
          fallbackPoster: _icon(item),
        ),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaDetailPage(
          state: widget.state,
          client: widget.client,
          kind: MediaKind.serie,
          id: id,
          fallbackName: _name(item),
          fallbackPoster: _icon(item),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => _buildCatalog(context),
    );
  }

  Widget _buildCatalog(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _load,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _visible;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 12),
              Text('${visible.length}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('Aucun résultat'))
              : widget.kind == _Kind.live
                  ? _liveList(visible)
                  : _grid(visible),
        ),
      ],
    );

    if (!wide) {
      return Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('Favoris ($_favoriteCount)'),
                    selected: _favoritesOnly,
                    onSelected: (_) => setState(() {
                      _favoritesOnly = true;
                      _categoryId = null;
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('Tout (${_all.length})'),
                    selected: !_favoritesOnly && _categoryId == null,
                    onSelected: (_) => setState(() {
                      _favoritesOnly = false;
                      _categoryId = null;
                    }),
                  ),
                ),
                for (final c in _categoryList)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_categoryLabel(c)),
                      selected: !_favoritesOnly &&
                          _categoryId == c['category_id']?.toString(),
                      onSelected: (_) => setState(() {
                        _favoritesOnly = false;
                        _categoryId = c['category_id']?.toString();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: content),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 268, child: _categoryPanel(theme)),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
  }

  /// Colonne de gauche : toutes les catégories de la section.
  Widget _categoryPanel(ThemeData theme) {
    final counts = _counts;
    final categories = _categoryList;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            widget.kind == _Kind.live ? 'Catégories' : 'Catégories',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              _categoryTile(
                theme: theme,
                label: 'Favoris',
                count: _favoriteCount,
                selected: _favoritesOnly,
                onTap: () => setState(() {
                  _favoritesOnly = true;
                  _categoryId = null;
                }),
                icon: Icons.favorite,
              ),
              const Divider(height: 12),
              _categoryTile(
                theme: theme,
                label: 'Tout',
                count: _all.length,
                selected: !_favoritesOnly && _categoryId == null,
                onTap: () => setState(() {
                  _favoritesOnly = false;
                  _categoryId = null;
                }),
                icon: Icons.apps,
              ),
              const Divider(height: 12),
              for (final c in categories)
                _categoryTile(
                  theme: theme,
                  label: _categoryLabel(c),
                  count: counts[c['category_id']?.toString()] ?? 0,
                  selected: !_favoritesOnly &&
                      _categoryId == c['category_id']?.toString(),
                  onTap: () => setState(() {
                    _favoritesOnly = false;
                    _categoryId = c['category_id']?.toString();
                  }),
                  icon: Icons.folder_outlined,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _categoryTile({
    required ThemeData theme,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return TvFocus(
      borderRadius: 8,
      onActivate: onTap,
      child: Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.16)
          : Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('$count',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _liveList(List<dynamic> items) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = (items[i] as Map).cast<String, dynamic>();
        final icon = _icon(item);
        final fav = widget.state.isFavorite(_name(item), 'channel');
        return ListTile(
          mouseCursor: SystemMouseCursors.click,
          autofocus: i == 0,
          focusColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          leading: icon == null
              ? const Icon(Icons.live_tv_outlined)
              : SizedBox(
                  width: 44,
                  height: 44,
                  child: Image.network(
                    icon,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.live_tv_outlined),
                  ),
                ),
          title: Text(_name(item), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text((item['category_name'] ?? '').toString()),
          trailing: IconButton(
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 20),
            onPressed: () => widget.state.toggleFavorite(_name(item), 'channel'),
          ),
          onTap: () => _open(item),
        );
      },
    );
  }

  Widget _grid(List<dynamic> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = (items[i] as Map).cast<String, dynamic>();
        final icon = _icon(item);
        final tmdb = _tmdbOf(item);
        final fav = tmdb != null && widget.state.isFavorite(tmdb, _favoriteType);
        return TvFocus(
          autofocus: i == 0,
          onActivate: () => _open(item),
          child: InkWell(
          canRequestFocus: false,
          onTap: () => _open(item),
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: icon == null
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.movie_outlined),
                            )
                          : Image.network(
                              icon,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, _, _) => Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(Icons.movie_outlined),
                              ),
                            ),
                    ),
                    if (tmdb != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () =>
                                widget.state.toggleFavorite(tmdb, _favoriteType),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                fav ? Icons.favorite : Icons.favorite_border,
                                size: 16,
                                color: fav
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _name(item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
