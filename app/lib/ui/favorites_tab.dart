import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../mizu_config.dart';
import '../state/app_state.dart';
import 'open_content.dart';
import 'tv_focus.dart';
import 'cached_image.dart';

/// Favoris du profil actif, répartis en trois colonnes : TV, Films, Séries.
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: MizuConfig.sectionOrderListenable,
      builder: (context, order, _) => _buildContent(context, order),
    );
  }

  /// Colonne de favoris pour une clé de section (`live`/`vod`/`serie`).
  static _Column _columnFor(
    String key,
    List<FavoriteItem> channels,
    List<FavoriteItem> movies,
    List<FavoriteItem> series,
  ) {
    switch (key) {
      case 'vod':
        return _Column(title: 'Films', icon: Icons.movie_outlined, items: movies);
      case 'serie':
        return _Column(
            title: 'Séries',
            icon: Icons.video_library_outlined,
            items: series);
      default:
        return _Column(title: 'TV', icon: Icons.live_tv_outlined, items: channels);
    }
  }

  /// Trie les favoris du plus récent au plus ancien (`added_at`).
  static int _recentFirst(FavoriteItem a, FavoriteItem b) {
    final da = a.addedAt?.millisecondsSinceEpoch ?? 0;
    final db = b.addedAt?.millisecondsSinceEpoch ?? 0;
    return db.compareTo(da);
  }

  Widget _buildContent(BuildContext context, List<String> order) {
    final theme = Theme.of(context);
    if (state.favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border,
                  size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('Aucun favori pour ce profil',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Les favoris sont lus dans ta table `favorites`, par profil.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    // Les plus récents d'abord (added_at, puis ordre serveur).
    final channels =
        state.favorites.where((f) => f.contentType == 'channel').toList()
          ..sort(_recentFirst);
    final movies = state.favorites.where((f) => f.contentType == 'vod').toList()
      ..sort(_recentFirst);
    final series =
        state.favorites.where((f) => f.contentType == 'serie').toList()
          ..sort(_recentFirst);

    // Les colonnes suivent l'ordre choisi dans Préférences.
    final columns = [
      for (final key in order) _columnFor(key, channels, movies, series),
    ];

    // Trois colonnes sur un écran large (TV / desktop), sections empilées sinon.
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final column in columns) ...[
            _ColumnHeader(column: column),
            if (column.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun favori'),
              )
            else
              for (final item in column.items)
                _FavoriteTile(
                  key: _favoriteKey(item),
                  state: state,
                  favorite: item,
                ),
            const SizedBox(height: 20),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const VerticalDivider(width: 20),
            Expanded(child: _ColumnView(state: state, column: columns[i])),
          ],
        ],
      ),
    );
  }
}

class _Column {
  _Column({required this.title, required this.icon, required this.items});
  final String title;
  final IconData icon;
  final List<FavoriteItem> items;
}

/// Clé stable par contenu : évite qu'un retrait ne réutilise l'état du voisin
/// (sinon le favori suivant hérite de l'animation et disparaît).
Key _favoriteKey(FavoriteItem f) => ValueKey('${f.contentType}:${f.contentId}');

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.column});

  final _Column column;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(column.icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(column.title, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Text('${column.items.length}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

class _ColumnView extends StatelessWidget {
  const _ColumnView({required this.state, required this.column});

  final AppState state;
  final _Column column;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ColumnHeader(column: column),
        Expanded(
          child: column.items.isEmpty
              ? Center(
                  child: Text('Aucun favori',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: column.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _FavoriteTile(
                    key: _favoriteKey(column.items[i]),
                    state: state,
                    favorite: column.items[i],
                    autofocus: i == 0,
                  ),
                ),
        ),
      ],
    );
  }
}

class _FavoriteTile extends StatefulWidget {
  const _FavoriteTile({
    super.key,
    required this.state,
    required this.favorite,
    this.autofocus = false,
  });

  final AppState state;
  final FavoriteItem favorite;
  final bool autofocus;

  @override
  State<_FavoriteTile> createState() => _FavoriteTileState();
}

class _FavoriteTileState extends State<_FavoriteTile> {
  bool _removing = false;
  bool _opening = false;
  bool _collapsed = false;

  FavoriteItem get f => widget.favorite;

  /// Ouvre une chaîne favorite : cherche son flux dans les sources.
  Future<void> _openChannelBusy(String name) async {
    setState(() => _opening = true);
    try {
      await openChannel(context, widget.state, name);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Retrait en deux temps : le coeur grossit et la carte s'efface, puis la
  /// ligne se replie (les suivantes remontent), enfin la suppression est
  /// écrite côté serveur. L'écriture n'arrive qu'à la fin : pas de saut.
  Future<void> _remove() async {
    if (_removing) return;
    setState(() => _removing = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _collapsed = true);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    await widget.state.toggleFavorite(f.contentId, f.contentType);
  }

  Future<void> _showContextMenu(Offset globalPosition, bool canOpen,
      VoidCallback activate) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (canOpen)
          const PopupMenuItem(
            value: 'open',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.open_in_new),
              title: Text('Ouvrir'),
            ),
          ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.favorite_border),
            title: Text('Retirer des favoris'),
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'remove') {
      await _remove();
    } else if (selected == 'open') {
      activate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = f;
    final isChannel = item.contentType == 'channel';

    final content = ListenableBuilder(
      listenable: CatalogIndex.instance,
      builder: (context, _) {
        final entry = isChannel
            ? null
            : CatalogIndex.instance.lookup(item.contentType, item.contentId);
        return FutureBuilder<ContentMeta?>(
          future: isChannel
              ? Future<ContentMeta?>.value(null)
              : widget.state.metadata.fetch(item.contentType, item.contentId),
          builder: (context, snap) {
            final meta = snap.data;
            final title = meta?.title ?? entry?.name ?? item.contentId;
            final poster = meta?.poster ?? entry?.poster;
            final hasEntry = entry != null && entry.candidates.isNotEmpty;
            final sourceOk = isChannel ||
                (entry != null &&
                    entry.candidates.isNotEmpty &&
                    entrySourceAvailable(entry, widget.state));
            final sourceMissing = !isChannel && hasEntry && !sourceOk;
            final canOpen = isChannel || sourceOk;

            void activate() {
              if (_opening) return;
              if (isChannel) {
                _openChannelBusy(item.contentId);
                return;
              }
              if (entry == null || entry.candidates.isEmpty) return;
              openContent(context, widget.state,
                  kind: item.contentType, entry: entry);
            }

            return AnimatedOpacity(
              opacity: _removing ? 0 : 1,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeIn,
              child: AnimatedScale(
                scale: _removing ? 0.92 : 1,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeIn,
                child: GestureDetector(
                  // Clic droit (Linux/desktop) : menu contextuel.
                  onSecondaryTapDown: (details) => _showContextMenu(
                      details.globalPosition, canOpen, activate),
                  child: TvFocus(
                    autofocus: widget.autofocus,
                    enabled: canOpen,
                    borderRadius: 10,
                    onActivate: activate,
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        canRequestFocus: false,
                        onTap: canOpen ? activate : null,
                        mouseCursor: canOpen
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 34,
                                  height: 48,
                                  child: (poster == null || poster.isEmpty)
                                      ? Container(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          child: Icon(
                                            isChannel
                                                ? Icons.live_tv_outlined
                                                : Icons.movie_outlined,
                                            size: 16,
                                            color: theme.colorScheme.primary,
                                          ),
                                        )
                                      : CachedImage(
                                          poster,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Container(
                                            color: theme.colorScheme
                                                .surfaceContainerHighest,
                                            child: const Icon(
                                                Icons.movie_outlined,
                                                size: 16),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (_opening) 'Recherche…',
                                        if (meta?.year != null)
                                          '${meta!.year}',
                                        if (sourceMissing)
                                          'source supprimée'
                                        else if (entry != null &&
                                            entry.candidates.isNotEmpty)
                                          entry.candidates.first.sourceName
                                        else if (!isChannel)
                                          'hors catalogue',
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: sourceMissing
                                            ? theme.colorScheme.error
                                            : theme.colorScheme.outline,
                                      ),
                                    ),
                                    if (sourceMissing)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton(
                                          onPressed: _removing ? null : _remove,
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets
                                                .symmetric(horizontal: 6),
                                            minimumSize: const Size(0, 30),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          child:
                                              const Text('Retirer des favoris'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Retirer des favoris',
                                iconSize: 28,
                                padding: const EdgeInsets.all(10),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: _removing ? null : _remove,
                                icon: AnimatedScale(
                                  scale: _removing ? 1.35 : 1,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    Icons.favorite,
                                    size: 26,
                                    color: _removing
                                        ? theme.colorScheme.error
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    // Replie la ligne après l'effet : les favoris suivants remontent en douceur.
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _collapsed ? const SizedBox(width: double.infinity) : content,
    );
  }
}

