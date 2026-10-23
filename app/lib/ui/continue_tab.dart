import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'open_content.dart';

class ContinueTab extends StatelessWidget {
  const ContinueTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.progress.isEmpty) {
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.progress.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _ProgressTile(state: state, item: state.progress[i]),
    );
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({required this.state, required this.item});

  final AppState state;
  final ProgressItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = item;
    final type = p.kind == 'vod' ? 'vod' : 'serie';

    return ListenableBuilder(
      listenable: CatalogIndex.instance,
      builder: (context, _) {
        final entry = CatalogIndex.instance.lookup(type, p.serieId);
        return FutureBuilder<ContentMeta?>(
          future: state.metadata.fetch(type, p.serieId),
          builder: (context, snap) {
            final meta = snap.data;
            final title = meta?.title ??
                entry?.name ??
                '${type == 'vod' ? 'Film' : 'Série'} ${p.serieId}';
            final poster = meta?.poster ?? entry?.poster;
            final canOpen = entry != null && entry.candidates.isNotEmpty;

            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: canOpen
                    ? () => openContent(context, state,
                        kind: type, entry: entry, initialSeason: p.season)
                    : null,
                mouseCursor: canOpen
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
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
                          child: (poster == null || poster.isEmpty)
                              ? Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    type == 'vod'
                                        ? Icons.movie_outlined
                                        : Icons.video_library_outlined,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : Image.network(poster,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                        color: theme
                                            .colorScheme.surfaceContainerHighest,
                                        child: const Icon(Icons.movie_outlined,
                                            size: 20),
                                      )),
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
                              'S${p.season} E${p.episode} · ${_mmss(p.watchTime)}'
                              '${entry != null && entry.candidates.isNotEmpty ? ' · ${entry.candidates.first.sourceName}' : ''}'
                              '${p.lastWatched != null ? ' · ${_ago(p.lastWatched!)}' : ''}',
                              style: theme.textTheme.bodySmall,
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
            );
          },
        );
      },
    );
  }

  static String _mmss(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  static void _showRaw(BuildContext context, Map<String, dynamic> raw) {
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
}
