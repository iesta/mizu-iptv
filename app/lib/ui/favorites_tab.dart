import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'open_content.dart';

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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.favorites.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _FavoriteTile(state: state, favorite: state.favorites[i]),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.state, required this.favorite});

  final AppState state;
  final FavoriteItem favorite;

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

            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                mouseCursor: canOpen
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                leading: _Poster(
                    url: poster, isChannel: isChannel, theme: theme),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  [
                    _typeLabel(f.contentType),
                    if (meta?.year != null) '${meta!.year}',
                    if (meta?.vote != null && meta!.vote! > 0)
                      '★ ${meta.vote!.toStringAsFixed(1)}',
                    if (entry != null && entry.candidates.isNotEmpty)
                      entry.candidates.first.sourceName,
                    if (entry == null && !isChannel)
                      state.metadata.enabled
                          ? 'hors catalogue'
                          : 'hors catalogue (index en cours…)',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Retirer des favoris',
                  icon: const Icon(Icons.favorite, size: 20),
                  onPressed: () => state.toggleFavorite(f.contentId, f.contentType),
                ),
                onTap: canOpen
                    ? () => openContent(context, state,
                        kind: f.contentType, entry: entry)
                    : () => _showDetails(context, f, meta),
              ),
            );
          },
        );
      },
    );
  }

  static String _typeLabel(String type) => switch (type) {
        'vod' => 'Film',
        'serie' => 'Série',
        'channel' => 'Chaîne',
        _ => type,
      };

  void _showDetails(BuildContext context, FavoriteItem f, ContentMeta? meta) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(meta?.title ?? f.contentId),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (meta?.overview != null && meta!.overview!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(meta.overview!),
                ),
              SelectableText(
                {
                  'content_type': f.contentType,
                  'content_id': f.contentId,
                  'sort_order': f.sortOrder,
                  'added_at': f.addedAt?.toIso8601String(),
                  if (meta != null) 'tmdb_id': meta.tmdbId,
                }.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
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
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.isChannel, required this.theme});

  final String? url;
  final bool isChannel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 64,
        child: (url == null || url!.isEmpty)
            ? Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  isChannel ? Icons.live_tv_outlined : Icons.movie_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie_outlined, size: 20),
                ),
              ),
      ),
    );
  }
}
