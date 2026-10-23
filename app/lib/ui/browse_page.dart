import 'package:flutter/material.dart';

import '../data/m3u_playlist.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'player_page.dart';

/// Navigation dans une playlist M3U (source de type `m3u`).
class BrowsePlaylistPage extends StatefulWidget {
  const BrowsePlaylistPage({
    super.key,
    required this.state,
    required this.source,
    this.autoPlayFilter,
  });

  final AppState state;
  final PlaylistSource source;

  /// Ouvre directement la première chaîne dont le nom contient ce filtre
  /// (utilisé par les routes de développement).
  final String? autoPlayFilter;

  @override
  State<BrowsePlaylistPage> createState() => _BrowsePlaylistPageState();
}

class _BrowsePlaylistPageState extends State<BrowsePlaylistPage> {
  late Future<List<M3uChannel>> _future;
  String _filter = '';
  String? _group;

  @override
  void initState() {
    super.initState();
    _future = loadM3u(widget.source.endpoint,
        userAgent: widget.source.raw['user_agent']?.toString());
    final filter = widget.autoPlayFilter;
    if (filter != null && filter.isNotEmpty) {
      _future.then((channels) {
        for (final c in channels) {
          if (c.name.toLowerCase().contains(filter)) {
            _open(c);
            break;
          }
        }
      });
    }
  }

  void _open(M3uChannel c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          state: widget.state,
          url: c.url,
          title: c.name,
          subtitle: c.group,
          contentId: c.name,
          contentType: 'channel',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Filtrer les chaînes…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<M3uChannel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Impossible de charger la playlist :\n${snap.error}'),
              ),
            );
          }
          final all = snap.data ?? const [];
          final groups = <String>{
            for (final c in all) if (c.group != null) c.group!,
          }.toList()
            ..sort();

          final filtered = all.where((c) {
            if (_group != null && c.group != _group) return false;
            if (_filter.isEmpty) return true;
            return c.name.toLowerCase().contains(_filter);
          }).toList();

          return Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('Tout (${all.length})'),
                        selected: _group == null,
                        onSelected: (_) => setState(() => _group = null),
                      ),
                    ),
                    for (final g in groups)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(g),
                          selected: _group == g,
                          onSelected: (_) => setState(() => _group = g),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    final isFav = widget.state.isFavorite(c.name, 'channel');
                    return ListTile(
                      leading: c.logo == null
                          ? const Icon(Icons.live_tv_outlined)
                          : SizedBox(
                              width: 40,
                              height: 40,
                              child: Image.network(
                                c.logo!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.live_tv_outlined),
                              ),
                            ),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: c.group == null ? null : Text(c.group!),
                      trailing: IconButton(
                        icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                            size: 20),
                        onPressed: () =>
                            widget.state.toggleFavorite(c.name, 'channel'),
                      ),
                      onTap: () => _open(c),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
