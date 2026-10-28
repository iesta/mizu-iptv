import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'browse_page.dart';
import 'continue_tab.dart';
import 'settings_page.dart';
import 'favorites_tab.dart';
import 'sources_tab.dart';
import 'source_form_page.dart';
import 'xtream_browser_page.dart';
import 'media_detail_page.dart';
import '../data/catalog_index.dart';
import '../data/xtream_client.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _initialTab = 0;
  bool _devRouteOpened = false;

  @override
  void initState() {
    super.initState();
    _initialTab = int.tryParse(Platform.environment['MIZU_TAB'] ?? '') ?? 0;
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: _initialTab.clamp(0, 2),
    );
    if (Platform.environment['MIZU_ROUTE'] == null) return;
    if (widget.state.sources.isEmpty) {
      // Les sources arrivent après le premier rafraîchissement du compte.
      void listener() {
        if (widget.state.sources.isNotEmpty) {
          widget.state.removeListener(listener);
          _maybeOpenDevRoute();
        }
      }

      widget.state.addListener(listener);
    } else {
      _maybeOpenDevRoute();
    }
  }

  /// Routes de développement (captures, tests manuels) :
  /// `MIZU_ROUTE=browse:<nom source>` ou `play:<nom source>:<filtre>`.
  Future<void> _maybeOpenDevRoute() async {
    final spec = Platform.environment['MIZU_ROUTE'];
    debugPrint('devroute: spec=$spec opened=$_devRouteOpened');
    if (spec == null || spec.isEmpty || _devRouteOpened) return;
    _devRouteOpened = true;
    final parts = spec.split(':');
    if (parts.first == 'add') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SourceFormPage(state: widget.state),
      ));
      return;
    }
    final wanted = parts.length > 1 ? parts[1].toLowerCase() : '';
    PlaylistSourceMatch? found;
    for (final s in widget.state.sources) {
      if (s.name.toLowerCase() == wanted) {
        found = PlaylistSourceMatch(s);
        break;
      }
    }
    debugPrint('devroute: source=${found?.source.name}');
    if (found == null) return;
    final source = found.source;

    if (parts.first == 'browse') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BrowsePlaylistPage(state: widget.state, source: source),
      ));
    } else if (parts.first == 'xt') {
      final tab = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => XtreamBrowserPage(
          state: widget.state,
          source: source,
          initialTab: tab,
        ),
      ));
    } else if (parts.first == 'detail' && parts.length > 2) {
      await CatalogIndex.instance.ensureLoaded();
      final serieEntry = CatalogIndex.instance.lookup('serie', parts[2]);
      final entry =
          serieEntry ?? CatalogIndex.instance.lookup('vod', parts[2]);
      final kind = serieEntry != null ? MediaKind.serie : MediaKind.vod;
      debugPrint('devroute: entry=${entry?.name} cands=${entry?.candidates.length}');
      if (entry != null && entry.candidates.isNotEmpty) {
        final clients = <XtreamClient>[];
        for (final c in entry.candidates) {
          for (final s in widget.state.sources) {
            if (s.id == c.sourceId) {
              clients.add(XtreamClient(
                baseUrl: s.endpoint,
                username: s.username ?? '',
                password: s.password ?? '',
                userAgent: s.raw['user_agent']?.toString(),
              ));
            }
          }
        }
        final providerId = int.tryParse(entry.candidates.first.providerId);
        debugPrint('devroute: clients=${clients.length} providerId=$providerId cands=${entry.candidates.map((c) => '${c.sourceName}/${c.sourceId}/${c.providerId}').join(',')}');
        if (clients.isNotEmpty && providerId != null) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MediaDetailPage(
              state: widget.state,
              client: clients.first,
              fallbackClients: clients.skip(1).toList(),
              kind: kind,
              id: providerId,
              fallbackName: entry.name,
              fallbackPoster: entry.poster,
            ),
          ));
        }
      }
    } else if (parts.first == 'xtplay' && parts.length > 3) {
      final tab = int.tryParse(parts[2]) ?? 0;
      final filter = parts.sublist(3).join(':');
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => XtreamBrowserPage(
          state: widget.state,
          source: source,
          initialTab: tab,
          autoPlayFilter: filter,
        ),
      ));
    } else if (parts.first == 'play' && parts.length > 2) {
      final filter = parts.sublist(2).join(':').toLowerCase();
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BrowsePlaylistPage(
          state: widget.state,
          source: source,
          autoPlayFilter: filter,
        ),
      ));
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _goTab(int index) {
    final target = index.clamp(0, 2);
    if (target != _tabs.index) _tabs.animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    // Télécommande : CH+ / CH- (PageUp / PageDown) changent d'onglet.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _goTab(_tabs.index - 1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _goTab(_tabs.index + 1),
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset('assets/logo.png', width: 26, height: 26),
              ),
              const SizedBox(width: 10),
              const Text('Mizu IPTV'),
            ],
          ),
          actions: [
            if (state.profiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: state.activeProfileId,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      for (final p in state.profiles)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (id) {
                      if (id != null) state.selectProfile(id);
                    },
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Rafraîchir',
              onPressed: state.loading ? null : state.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Préférences',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsPage(state: state)),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.favorite_border), text: 'Favoris'),
              Tab(icon: Icon(Icons.play_circle_outline), text: 'Reprendre'),
              Tab(icon: Icon(Icons.dns_outlined), text: 'Sources'),
            ],
            indicatorSize: TabBarIndicatorSize.tab,
          ),
        ),
        body: Column(
          children: [
            if (state.loading) const LinearProgressIndicator(minHeight: 2),
            if (state.error != null)
              MaterialBanner(
                content: Text(state.error!),
                leading: const Icon(Icons.error_outline),
                actions: [
                  TextButton(onPressed: state.refresh, child: const Text('Réessayer')),
                ],
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  FavoritesTab(state: state),
                  ContinueTab(state: state),
                  SourcesTab(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Petit porteur pour éviter une dépendance à `collection.firstOrNull`.
class PlaylistSourceMatch {
  PlaylistSourceMatch(this.source);
  final PlaylistSource source;
}
