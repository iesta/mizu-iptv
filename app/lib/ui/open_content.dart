import 'package:flutter/material.dart';

import '../data/catalog_index.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';
import 'media_detail_page.dart';

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
