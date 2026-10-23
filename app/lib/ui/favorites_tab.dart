import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'open_content.dart';
import 'tv_focus.dart';

/// Favoris du profil actif, répartis en trois colonnes : TV, Films, Séries.
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
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

    final channels =
        state.favorites.where((f) => f.contentType == 'channel').toList();
    final movies = state.favorites.where((f) => f.contentType == 'vod').toList();
    final series =
        state.favorites.where((f) => f.contentType == 'serie').toList();

    final columns = [
      _Column(title: 'TV', icon: Icons.live_tv_outlined, items: channels),
      _Column(title: 'Films', icon: Icons.movie_outlined, items: movies),
      _Column(
          title: 'Séries',
          icon: Icons.video_library_outlined,
          items: series),
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
                _FavoriteTile(state: state, favorite: item),
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

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.state,
    required this.favorite,
    this.autofocus = false,
  });

  final AppState state;
  final FavoriteItem favorite;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = favorite;
    final isChannel = f.contentType == 'channel';

    return ListenableBuilder(
      listenable: CatalogIndex.instance,
      builder: (context, _) {
        final entry = isChannel
            ? null
            : CatalogIndex.instance.lookup(f.contentType, f.contentId);
        return FutureBuilder<ContentMeta?>(
          future: isChannel
              ? Future<ContentMeta?>.value(null)
              : state.metadata.fetch(f.contentType, f.contentId),
          builder: (context, snap) {
            final meta = snap.data;
            final title = meta?.title ?? entry?.name ?? f.contentId;
            final poster = meta?.poster ?? entry?.poster;
            final canOpen = entry != null && entry.candidates.isNotEmpty;

            void activate() {
              if (!canOpen) return;
              openContent(context, state, kind: f.contentType, entry: entry);
            }

            return TvFocus(
              autofocus: autofocus,
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
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      isChannel
                                          ? Icons.live_tv_outlined
                                          : Icons.movie_outlined,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : Image.network(
                                    poster,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: theme.colorScheme
                                          .surfaceContainerHighest,
                                      child: const Icon(Icons.movie_outlined,
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
                                  if (meta?.year != null) '${meta!.year}',
                                  if (entry != null &&
                                      entry.candidates.isNotEmpty)
                                    entry.candidates.first.sourceName
                                  else if (!isChannel)
                                    'hors catalogue',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Retirer des favoris',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.favorite, size: 16),
                          onPressed: () =>
                              state.toggleFavorite(f.contentId, f.contentType),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
