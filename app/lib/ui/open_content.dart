import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/m3u_playlist.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';
import 'media_detail_page.dart';
import 'player_page.dart';

/// Résout une chaîne (stockée par nom dans `favorites.content_id`) dans les
/// sources du compte, puis lance le premier flux correspondant.
Future<void> openChannel(
  BuildContext context,
  AppState state,
  String name,
) async {
  final wanted = name.trim().toLowerCase();
  for (final source in state.sources) {
    try {
      if (source.isXtream) {
        final client = XtreamClient(
          baseUrl: source.endpoint,
          username: source.username ?? '',
          password: source.password ?? '',
          userAgent: source.raw['user_agent']?.toString(),
        );
        try {
          final streams = await client.liveStreams();
          for (final raw in streams) {
            if (raw is! Map) continue;
            final item = raw.cast<String, dynamic>();
            final label = (item['name'] ?? '').toString().trim();
            if (label.toLowerCase() != wanted) continue;
            final id = int.tryParse(
              (item['stream_id'] ?? item['id'] ?? '').toString(),
            );
            if (id == null) continue;
            final ext =
                (item['container_extension']?.toString().isNotEmpty ?? false)
                    ? item['container_extension'].toString()
                    : 'ts';
            if (!context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerPage(
                state: state,
                url: client.liveUrl(id, ext: ext),
                title: label.isEmpty ? name : label,
                subtitle: 'Direct',
                contentId: name,
                contentType: 'channel',
              ),
            ));
            return;
          }
        } finally {
          client.close();
        }
      } else {
        final channels = await loadM3u(
          source.endpoint,
          userAgent: source.raw['user_agent']?.toString(),
        );
        for (final channel in channels) {
          if (channel.name.trim().toLowerCase() != wanted) continue;
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlayerPage(
              state: state,
              url: channel.url,
              title: channel.name,
              subtitle: channel.group,
              contentId: name,
              contentType: 'channel',
            ),
          ));
          return;
        }
      }
    } catch (_) {
      // Source indisponible ou expirée : on tente la suivante.
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Chaîne « $name » introuvable dans tes sources.')),
    );
  }
}

/// Vrai si au moins un candidat de l'index pointe encore vers une source
/// configurée sur le compte (sinon le contenu n'est plus lisible).
bool entrySourceAvailable(IndexEntry entry, AppState state) {
  for (final candidate in entry.candidates) {
    if (state.sources.any((s) => s.id == candidate.sourceId)) return true;
  }
  return false;
}

/// Ouvre la fiche d'un contenu référencé par un id TMDB (favoris, reprise).
///
/// L'index fournit les sources où le contenu existe ; on passe les clients
/// suivants en secours pour basculer automatiquement si l'un répond 461.
Future<void> openContent(
  BuildContext context,
  AppState state, {
  required String kind,
  required IndexEntry entry,
  int? initialSeason,
}) async {
  final clients = <XtreamClient>[];
  for (final candidate in entry.candidates) {
    for (final source in state.sources) {
      if (source.id != candidate.sourceId) continue;
      clients.add(XtreamClient(
        baseUrl: source.endpoint,
        username: source.username ?? '',
        password: source.password ?? '',
        userAgent: source.raw['user_agent']?.toString(),
      ));
    }
  }
  final providerId = int.tryParse(entry.candidates.first.providerId);
  if (clients.isEmpty || providerId == null) return;

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MediaDetailPage(
      state: state,
      client: clients.first,
      fallbackClients: clients.skip(1).toList(),
      kind: kind == 'vod' ? MediaKind.vod : MediaKind.serie,
      id: providerId,
      fallbackName: entry.name,
      fallbackPoster: entry.poster,
      initialSeason: initialSeason,
    ),
  ));
}
