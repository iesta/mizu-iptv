import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/xtream_client.dart';
import '../mizu_config.dart';
import '../state/app_state.dart';
import 'media_detail_page.dart';
import 'catalog_options.dart';
import 'sections.dart';
import 'tv_focus.dart';
import 'player_page.dart';
import 'cached_image.dart';

/// Navigation d'une source Xtream : Live TV, Films, Séries.
class XtreamBrowserPage extends StatefulWidget {
  const XtreamBrowserPage({
    super.key,
    required this.state,
    required this.source,
    this.initialTab,
    this.autoPlayFilter,
  });

  final AppState state;
  final PlaylistSource source;

  /// Section à ouvrir en premier : 0 = Live TV, 1 = Films, 2 = Séries.
  /// `null` (ouverture normale d'une source) = premier onglet de l'ordre des
  /// préférences.
  final int? initialTab;

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
    // L'ordre des sections est une préférence (Préférences, glisser-déposer).
    final order = MizuConfig.sectionOrder;
    final requested = widget.initialTab;
    final initialKey = requested == null
        ? null
        : switch (requested.clamp(0, 2)) {
            1 => 'vod',
            2 => 'serie',
            _ => 'live',
          };
    // Sans section demandée, on ouvre le premier onglet de l'ordre préféré.
    final initialIndex = initialKey == null
        ? 0
        : order.indexOf(initialKey).clamp(0, order.length - 1);
    return DefaultTabController(
      length: order.length,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.source.name),
          bottom: TabBar(
            tabs: [
              for (final key in order)
                Tab(
                  icon: Icon(LibrarySection.icon(key)),
                  text: LibrarySection.label(key),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final key in order)
              _catalogTab(key, key == initialKey ? widget.autoPlayFilter : null),
          ],
        ),
        endDrawer: const _CatalogSettingsDrawer(),
      ),
    );
  }

  /// Onglet de catalogue correspondant à une clé de section (`live`/`vod`/`serie`).
  Widget _catalogTab(String key, String? autoPlayFilter) {
    switch (key) {
      case 'vod':
        return _CatalogTab(
          client: _client,
          kind: _Kind.vod,
          autoPlayFilter: autoPlayFilter,
          loadCategories: _client.vodCategories,
          loadItems: (cat) => _client.vodStreams(categoryId: cat),
          state: widget.state,
        );
      case 'serie':
        return _CatalogTab(
          client: _client,
          kind: _Kind.serie,
          autoPlayFilter: autoPlayFilter,
          loadCategories: _client.seriesCategories,
          loadItems: (cat) => _client.series(categoryId: cat),
          state: widget.state,
        );
      default:
        return _CatalogTab(
          client: _client,
          kind: _Kind.live,
          autoPlayFilter: autoPlayFilter,
          loadCategories: _client.liveCategories,
          loadItems: (cat) => _client.liveStreams(categoryId: cat),
          state: widget.state,
        );
    }
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
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
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
  String? _sortedFor;

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

  /// Note normalisée sur 10 (0 si absente), à partir de `rating_5based` ou
  /// `rating` (souvent sur 10 chez Xtream).
  static double _ratingOf(Map<String, dynamic> item) {
    final five = double.tryParse(item['rating_5based']?.toString() ?? '');
    if (five != null && five > 0) return (five * 2).clamp(0.0, 10.0);
    final raw = double.tryParse(item['rating']?.toString() ?? '');
    if (raw == null || raw <= 0) return 0;
    return (raw > 5 ? raw : raw * 2).clamp(0.0, 10.0);
  }

  int _compareBySort(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String sort,
  ) {
    final nameA = _name(a).toLowerCase();
    final nameB = _name(b).toLowerCase();
    switch (sort) {
      case 'oldest':
        return _addedAt(a).compareTo(_addedAt(b));
      case 'name_asc':
        return nameA.compareTo(nameB);
      case 'name_desc':
        return nameB.compareTo(nameA);
      case 'rating_desc':
        final c = _ratingOf(b).compareTo(_ratingOf(a));
        return c != 0 ? c : nameA.compareTo(nameB);
      case 'rating_asc':
        final c = _ratingOf(a).compareTo(_ratingOf(b));
        return c != 0 ? c : nameA.compareTo(nameB);
      case 'recent':
      default:
        return _addedAt(b).compareTo(_addedAt(a));
    }
  }

  /// Tout le catalogue, trié selon la préférence (`MizuConfig.catalogSort`).
  List<Map<String, dynamic>> get _all {
    final sort = MizuConfig.catalogSort;
    final cached = _sortedCache;
    if (cached != null && _sortedFor == sort) return cached;
    final list = (_items ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    list.sort((a, b) => _compareBySort(a, b, sort));
    _sortedCache = list;
    _sortedFor = sort;
    return list;
  }

  bool get _isLive => widget.kind == _Kind.live;
  String get _favoriteType => switch (widget.kind) {
        _Kind.live => 'channel',
        _Kind.vod => 'vod',
        _Kind.serie => 'serie',
      };

  String? _tmdbOf(Map<String, dynamic> item) {
    final raw = (item['tmdb_id'] ?? item['tmdb'])?.toString();
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
      final tmdb = _tmdbOf(item);
      final versions = <SeriesVersion>[];
      if (tmdb != null) {
        for (final other in _all) {
          if (_tmdbOf(other) != tmdb) continue;
          final otherId = int.tryParse(_id(other));
          if (otherId == null) continue;
          if (versions.any((v) => v.id == otherId)) continue;
          versions.add(SeriesVersion(
            id: otherId,
            name: _name(other),
            poster: _icon(other),
          ));
        }
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaDetailPage(
          state: widget.state,
          client: widget.client,
          kind: MediaKind.serie,
          id: id,
          fallbackName: _name(item),
          fallbackPoster: _icon(item),
          versions: versions,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.state,
        MizuConfig.catalogSortListenable,
      ]),
      builder: (context, _) => Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) => _onCatalogKey(context, event),
        child: _buildCatalog(context),
      ),
    );
  }

  /// Raccourcis : F = focus recherche, « , » = panneau des préférences.
  /// Ignorés quand on saisit dans le champ de recherche.
  KeyEventResult _onCatalogKey(BuildContext context, KeyEvent event) {
    if (_searchFocus.hasFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.comma) {
      Scaffold.of(context).openEndDrawer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
                  controller: _search,
                  focusNode: _searchFocus,
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
                tooltip: 'Options d\'affichage',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
              const SizedBox(width: 4),
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
                  child: CachedImage(
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
    return ValueListenableBuilder<double>(
      valueListenable: MizuConfig.thumbSizeListenable,
      builder: (context, thumbSize, _) => GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: thumbSize,
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
        final rating = _ratingOf(item);
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
                          : CachedImage(
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
                    if (rating > 0)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 17, color: Color(0xFFFFC107)),
                              const SizedBox(width: 3),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (tmdb != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () =>
                                widget.state.toggleFavorite(tmdb, _favoriteType),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                fav ? Icons.favorite : Icons.favorite_border,
                                size: 24,
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
      ),
    );
  }
}

/// Panneau latéral droit (`endDrawer`) : options d'affichage du catalogue.
class _CatalogSettingsDrawer extends StatelessWidget {
  const _CatalogSettingsDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Affichage', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Taille des vignettes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Films et séries.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            ValueListenableBuilder<double>(
              valueListenable: MizuConfig.thumbSizeListenable,
              builder: (context, size, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Slider(
                    min: MizuConfig.minThumbSize,
                    max: MizuConfig.maxThumbSize,
                    divisions: ((MizuConfig.maxThumbSize -
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
                  Text(
                    '${size.round()} px',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Text('Tri', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ValueListenableBuilder<String>(
              valueListenable: MizuConfig.catalogSortListenable,
              builder: (context, sort, _) => Column(
                children: [
                  for (final option in catalogSortOptions)
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
      ),
    );
  }
}
