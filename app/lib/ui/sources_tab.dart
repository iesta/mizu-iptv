import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';
import 'browse_page.dart';
import 'source_form_page.dart';
import 'xtream_browser_page.dart';

class SourcesTab extends StatelessWidget {
  const SourcesTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.sources.isEmpty) {
      return const _Empty(
        icon: Icons.dns_outlined,
        title: 'Aucune source sur ce compte',
        subtitle: 'Les sources se synchronisent depuis ton compte Zen '
            '(table playlist_sources).',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${state.sources.length} source${state.sources.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SourceFormPage(state: state),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.sources.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) =>
                _SourceCard(state: state, source: state.sources[i]),
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.state, required this.source});

  final AppState state;
  final PlaylistSource source;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _busy = false;
  String? _result;
  bool _ok = false;

  void _open() {
    final s = widget.source;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => s.isM3u
          ? BrowsePlaylistPage(state: widget.state, source: s)
          : XtreamBrowserPage(state: widget.state, source: s),
    ));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Supprimer « ${widget.source.name} » ?'),
        content: const Text(
          'La source sera supprimée de ton compte : elle disparaîtra aussi '
          'de l\'app Zen sur tes autres appareils.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.deleteSource(widget.source.id);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final s = widget.source;
    try {
      if (s.isXtream) {
        final client = XtreamClient(
          baseUrl: s.endpoint,
          username: s.username ?? '',
          password: s.password ?? '',
          userAgent: s.raw['user_agent']?.toString(),
        );
        final info = await client.accountInfo();
        final user = info['user_info'] as Map<String, dynamic>? ?? const {};
        final server = info['server_info'] as Map<String, dynamic>? ?? const {};
        final exp = int.tryParse(user['exp_date']?.toString() ?? '');
        final expDate =
            exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        setState(() {
          _ok = (user['status']?.toString() ?? '') == 'Active';
          _result = [
            'statut: ${user['status'] ?? '?'}',
            if (expDate != null) 'expire: ${_fmtDate(expDate)}',
            'connexions: ${user['active_cons'] ?? 0}/${user['max_connections'] ?? '?'}',
            if (server['url'] != null) 'serveur: ${server['url']}',
          ].join(' · ');
        });
      } else {
        final res = await http.get(
          Uri.parse(s.endpoint),
          headers: {
            if (s.raw['user_agent'] != null)
              'User-Agent': s.raw['user_agent'].toString(),
          },
        ).timeout(const Duration(seconds: 25));
        final body = res.body;
        final isM3u = body.trimLeft().startsWith('#EXTM3U') ||
            body.contains('#EXTINF');
        setState(() {
          _ok = res.statusCode == 200 && isM3u;
          _result = 'HTTP ${res.statusCode} · '
              '${isM3u ? 'playlist M3U valide' : 'ce n\'est pas un M3U'} '
              '· ${(res.bodyBytes.length / 1024).round()} Ko';
        });
      }
    } catch (e) {
      setState(() {
        _ok = false;
        _result = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.source;
    final color = s.color != null ? Color(s.color!) : theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: theme.textTheme.titleMedium),
                      Text(
                        s.endpoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: s.isM3u
                      ? 'Parcourir les chaînes'
                      : 'Parcourir le catalogue',
                  onPressed: _open,
                  icon: Icon(s.isM3u ? Icons.playlist_play : Icons.grid_view),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Gérer la source',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'edit') {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SourceFormPage(
                          state: widget.state,
                          source: s,
                        ),
                      ));
                    } else if (value == 'delete') {
                      _confirmDelete(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Modifier'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Supprimer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _busy ? null : _test,
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Tester'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Chip(
                  label: s.isXtream ? 'Xtream' : 'M3U',
                  icon: s.isXtream ? Icons.dns_outlined : Icons.playlist_play,
                ),
                if (s.username != null && s.username!.isNotEmpty)
                  _Chip(label: s.username!, icon: Icons.person_outline),
                if (s.epgUrl != null && s.epgUrl!.isNotEmpty)
                  const _Chip(label: 'EPG', icon: Icons.calendar_month),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _ok ? Icons.check_circle_outline : Icons.error_outline,
                    size: 18,
                    color: _ok ? Colors.greenAccent : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_result!, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
