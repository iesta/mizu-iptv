import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/xtream_client.dart';
import '../state/app_state.dart';

/// Ajout ou modification d'une source (Xtream ou M3U).
///
/// Les sources vivent dans `playlist_sources` côté Supabase : une modification
/// ici est donc visible par l'app Zen sur les autres appareils.
class SourceFormPage extends StatefulWidget {
  const SourceFormPage({super.key, required this.state, this.source});

  final AppState state;
  final PlaylistSource? source;

  bool get isEdit => source != null;

  @override
  State<SourceFormPage> createState() => _SourceFormPageState();
}

class _SourceFormPageState extends State<SourceFormPage> {
  late String _kind = widget.source?.kind ?? 'xtream';
  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late final _host = TextEditingController(text: widget.source?.host ?? '');
  late final _url = TextEditingController(text: widget.source?.url ?? '');
  late final _username =
      TextEditingController(text: widget.source?.username ?? '');
  late final _password =
      TextEditingController(text: widget.source?.password ?? '');
  late final _epg = TextEditingController(text: widget.source?.epgUrl ?? '');

  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _epg.dispose();
    super.dispose();
  }

  static String _normalizeUrl(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Le nom est requis.';
    if (_kind == 'xtream') {
      if (_host.text.trim().isEmpty) return 'L\'adresse du serveur est requise.';
      if (_username.text.trim().isEmpty) return 'L\'identifiant est requis.';
    } else {
      if (_url.text.trim().isEmpty) return 'L\'URL de la playlist est requise.';
    }
    return null;
  }

  Future<void> _test() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
      _error = null;
    });
    try {
      if (_kind == 'xtream') {
        final client = XtreamClient(
          baseUrl: _normalizeUrl(_host.text),
          username: _username.text.trim(),
          password: _password.text,
        );
        final info = await client.accountInfo();
        final user = info['user_info'] as Map<String, dynamic>? ?? const {};
        final exp = int.tryParse(user['exp_date']?.toString() ?? '');
        setState(() {
          _testOk = true;
          _testResult = [
            'statut ${user['status'] ?? '?'}',
            if (exp != null)
              'expire le ${DateTime.fromMillisecondsSinceEpoch(exp * 1000).toIso8601String().substring(0, 10)}',
            '${user['active_cons'] ?? 0}/${user['max_connections'] ?? '?'} connexions',
          ].join(' · ');
        });
      } else {
        final res = await http.get(Uri.parse(_normalizeUrl(_url.text))).timeout(
            const Duration(seconds: 25));
        final isM3u = res.body.trimLeft().startsWith('#EXTM3U') ||
            res.body.contains('#EXTINF');
        setState(() {
          _testOk = res.statusCode == 200 && isM3u;
          _testResult = 'HTTP ${res.statusCode} · '
              '${isM3u ? 'playlist M3U valide' : 'ce n\'est pas un M3U'}';
        });
      }
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.toString();
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.state.saveSource(
        id: widget.source?.id,
        name: _name.text.trim(),
        kind: _kind,
        host: _kind == 'xtream' ? _normalizeUrl(_host.text) : null,
        url: _kind == 'm3u' ? _normalizeUrl(_url.text) : null,
        username: _kind == 'xtream' ? _username.text.trim() : null,
        password: _kind == 'xtream' ? _password.text : null,
        epgUrl: _epg.text.trim().isEmpty ? null : _epg.text.trim(),
        color: widget.source?.color,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Modifier la source' : 'Nouvelle source'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'xtream',
                label: Text('Xtream'),
                icon: Icon(Icons.dns_outlined),
              ),
              ButtonSegment(
                value: 'm3u',
                label: Text('M3U'),
                icon: Icon(Icons.playlist_play),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nom de la source',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_kind == 'xtream') ...[
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Adresse du serveur',
                hintText: 'http://exemple.tv:8080',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Identifiant',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mot de passe',
                border: OutlineInputBorder(),
              ),
            ),
          ] else
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL de la playlist M3U',
                hintText: 'https://exemple.tv/playlist.m3u',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _epg,
            decoration: const InputDecoration(
              labelText: 'URL EPG (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          if (_testResult != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _testOk ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: _testOk ? Colors.greenAccent : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_testResult!)),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: const Text('Tester'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.isEdit ? 'Enregistrer' : 'Ajouter'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Les identifiants sont stockés côté serveur Zen (comme dans l\'app '
            'd\'origine) et synchronisés sur tous tes appareils.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
