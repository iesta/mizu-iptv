import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/metadata_service.dart';
import '../mizu_config.dart';
import '../state/app_state.dart';

/// Préférences : backend Supabase, clé TMDB, compte.
///
/// Les valeurs sont écrites dans `~/.config/mizu/config.json` (ou le dossier
/// applicatif sur mobile). Changer l'URL ou la clé du backend demande un
/// redémarrage : `Supabase.initialize` ne se refait pas à chaud.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state, this.firstRun = false});

  /// `null` au premier lancement (backend pas encore configuré).
  final AppState? state;
  final bool firstRun;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _url = TextEditingController(text: MizuConfig.backendUrl);
  late final _key = TextEditingController(text: MizuConfig.publishableKey);
  late final _tmdb = TextEditingController(text: MizuConfig.tmdbApiKey ?? '');

  int? _cacheCount;
  bool _clearing = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  MetadataService get _metadata => widget.state?.metadata ?? MetadataService();

  Future<void> _loadCacheInfo() async {
    try {
      final count = await _metadata.cacheSize();
      if (mounted) setState(() => _cacheCount = count);
    } catch (_) {
      // Cache illisible : on n'affiche pas de compteur.
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      await _metadata.clearCache();
      await _loadCacheInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache des métadonnées vidé.')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _tmdb.dispose();
    super.dispose();
  }

  String _normalize(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'https://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Future<void> _test() async {
    final url = _normalize(_url.text);
    final key = _key.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _testOk = false;
        _testResult = 'URL et clé requises.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final res = await http.get(
        Uri.parse('$url/auth/v1/settings'),
        headers: {'apikey': key},
      ).timeout(const Duration(seconds: 20));
      final ok = res.statusCode == 200;
      String detail = 'HTTP ${res.statusCode}';
      if (ok) {
        final data = jsonDecode(res.body);
        if (data is Map && data['external'] is Map) {
          final providers = (data['external'] as Map)
              .entries
              .where((e) => e.value == true)
              .map((e) => e.key)
              .join(', ');
          detail = 'GoTrue joignable · méthodes : $providers';
        }
      }
      setState(() {
        _testOk = ok;
        _testResult = detail;
      });
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final restartRequired = await MizuConfig.save(
        backendUrl: _normalize(_url.text),
        publishableKey: _key.text.trim(),
        tmdbApiKey: _tmdb.text.trim(),
      );
      widget.state?.metadata.reloadKey();
      if (!mounted) return;
      if (restartRequired) {
        await _askRestart();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Préférences enregistrées.')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _askRestart() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Redémarrage nécessaire'),
        content: const Text(
          'L\'URL ou la clé du backend a changé. La connexion Supabase est '
          'établie au démarrage : il faut relancer Mizu IPTV pour en tenir '
          'compte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitter maintenant'),
          ),
        ],
      ),
    );
    if (quit == true) exit(0);
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'La session sera effacée de cet appareil. Tes données restent sur '
          'ton compte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.state?.signOut();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.state?.session?.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Configuration' : 'Préférences'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.firstRun) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/logo.png', width: 80, height: 80),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bienvenue sur Mizu IPTV',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Renseigne l\'URL de ton instance Supabase et sa clé publishable. '
              'Elles sont enregistrées localement (~/.config/mizu/config.json) '
              'et ne sont jamais compilées dans l\'application.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
          ],
          Text('Serveur', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Instance Supabase à utiliser : celle de Zen IPTV, ou la tienne '
            '(voir re/supabase/). Rien n\'est compilé dans l\'application.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'URL du backend',
              hintText: 'https://mon-projet.supabase.co',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            decoration: const InputDecoration(
              labelText: 'Clé publishable',
              hintText: 'sb_publishable_…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
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
              if (_testResult != null)
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        _testOk
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                        color: _testOk
                            ? Colors.greenAccent
                            : theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_testResult!,
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Métadonnées', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Clé TMDB (gratuite) pour les titres et affiches des favoris et de '
            'la reprise. Sans elle, les noms viennent de l\'index du catalogue.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tmdb,
            decoration: const InputDecoration(
              labelText: 'Clé API TMDB (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _clearing ? null : _clearCache,
                icon: _clearing
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cleaning_services_outlined),
                label: const Text('Vider le cache'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_cacheCount ?? 0} fiche(s) en cache · conservées 30 jours',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ce produit utilise l\'API TMDB mais n\'est ni approuvé ni certifié '
            'par TMDB.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Enregistrer'),
          ),
          const SizedBox(height: 36),
          if (user != null) ...[
            const Divider(),
            const SizedBox(height: 12),
            Text('Compte', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(user.email ?? 'Compte connecté'),
              subtitle: Text(MizuConfig.backendUrl.isEmpty
                  ? 'Backend non configuré'
                  : MizuConfig.backendUrl),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Backend : ${MizuConfig.backendUrl.isEmpty ? "non configuré" : MizuConfig.backendUrl}'
            '${MizuConfig.source.isEmpty ? "" : " (${MizuConfig.source})"}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
