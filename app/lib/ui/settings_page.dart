import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/metadata_service.dart';
import '../mizu_config.dart';
import '../state/app_state.dart';
import 'debug_page.dart';
import 'home_blocks.dart';
import 'sections.dart';

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
  late final _ua = TextEditingController(text: MizuConfig.userAgent);

  /// Ordre local des sections (modifié par glisser-déposer).
  final List<String> _order = List<String>.of(MizuConfig.sectionOrder);

  int? _cacheCount;
  bool _clearing = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  String? _error;

  /// Onglet actif de la page Préférences.
  _SettingsTab _tab = _SettingsTab.preferences;

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

  /// Réordonne les sections (glisser-déposer) et enregistre aussitôt.
  void _reorderSection(int oldIndex, int newIndex) {
    setState(() {
      final item = _order.removeAt(oldIndex);
      _order.insert(newIndex, item);
    });
    _persistOrder();
  }

  /// Déplace une section d'un cran (flèches, pratique à la télécommande).
  void _nudgeSection(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _order.length) return;
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(target, item);
    });
    _persistOrder();
  }

  Future<void> _persistOrder() async {
    await MizuConfig.save(sectionOrder: _order);
  }

  /// Préférence « Ordre des sections » : glisser-déposer + flèches.
  Widget _sectionOrderEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ordre des sections', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Ordre des onglets d\'une source (Live TV / Films / Séries). '
          'Glisse une ligne, ou utilise les flèches pour la déplacer.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _order.length,
          onReorderItem: _reorderSection,
          proxyDecorator: (child, index, animation) => Material(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            elevation: 6,
            child: child,
          ),
          itemBuilder: (context, index) {
            final key = _order[index];
            return Card(
              key: ValueKey(key),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Icon(LibrarySection.icon(key)),
                title: Text(LibrarySection.label(key)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: 'Monter',
                      onPressed:
                          index == 0 ? null : () => _nudgeSection(index, -1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: 'Descendre',
                      onPressed: index == _order.length - 1
                          ? null
                          : () => _nudgeSection(index, 1),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Accueil : onglet activable + blocs ordonnables et activables.
  Widget _homeSectionEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Accueil', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Affiche un onglet Accueil composé de blocs de covers. Chaque bloc '
          'peut être activé/désactivé et réordonné.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Afficher l\'onglet Accueil'),
          value: MizuConfig.homeEnabled,
          onChanged: (value) {
            setState(() => MizuConfig.homeEnabled = value);
            MizuConfig.save(homeEnabled: value);
          },
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<String>>(
          valueListenable: MizuConfig.homeBlockOrderListenable,
          builder: (context, order, _) =>
              ValueListenableBuilder<List<String>>(
            valueListenable: MizuConfig.homeBlocksDisabledListenable,
            builder: (context, disabled, _) => ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorderItem: _reorderHomeBlock,
              itemBuilder: (context, index) {
                final key = order[index];
                final def = homeBlockDef(key);
                final enabled = !disabled.contains(key);
                return Card(
                  key: ValueKey('home-$key'),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    leading: Icon(def.icon),
                    title: Text(def.label),
                    subtitle: enabled ? null : const Text('Désactivé'),
                    onTap: () => _toggleHomeBlock(key),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: enabled,
                          onChanged: (_) => _toggleHomeBlock(key),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _reorderHomeBlock(int oldIndex, int newIndex) {
    final order = List<String>.of(MizuConfig.homeBlockOrder);
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    setState(() => MizuConfig.homeBlockOrder = order);
    MizuConfig.save(homeBlockOrder: MizuConfig.homeBlockOrder);
  }

  void _toggleHomeBlock(String key) {
    final disabled = List<String>.of(MizuConfig.homeBlocksDisabled);
    if (disabled.contains(key)) {
      disabled.remove(key);
    } else {
      disabled.add(key);
    }
    setState(() => MizuConfig.homeBlocksDisabled = disabled);
    MizuConfig.save(homeBlocksDisabled: MizuConfig.homeBlocksDisabled);
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
    _ua.dispose();
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
        userAgent: _ua.text.trim().isEmpty
            ? MizuConfig.defaultUserAgent
            : _ua.text.trim(),
        sectionOrder: _order,
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
    // Premier lancement : formulaire unique de configuration.
    if (widget.firstRun) {
      return Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: _legacyBuild(context),
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Préférences')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _leftNav(theme),
                  const VerticalDivider(width: 1),
                  Expanded(child: _tabContent(theme)),
                ],
              );
            }
            return Column(
              children: [
                _topNav(theme),
                const Divider(height: 1),
                Expanded(child: _tabContent(theme)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Échap / Retour : quitte les préférences.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Navigation verticale (onglets à gauche).
  // ---------------------------------------------------------------------------

  Widget _leftNav(ThemeData theme) {
    return Container(
      width: 280,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: Text('Préférences', style: theme.textTheme.titleLarge),
            ),
            for (final tab in _SettingsTab.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  selected: _tab == tab,
                  selectedColor: theme.colorScheme.primary,
                  selectedTileColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  leading: Icon(_tabIcon(tab)),
                  title: Text(_tabLabel(tab)),
                  onTap: () => setState(() => _tab = tab),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topNav(ThemeData theme) {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          for (final tab in _SettingsTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(_tabIcon(tab), size: 18),
                label: Text(_tabLabel(tab)),
                selected: _tab == tab,
                onSelected: (_) => setState(() => _tab = tab),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabContent(ThemeData theme) {
    switch (_tab) {
      case _SettingsTab.preferences:
        return _preferencesContent(theme);
      case _SettingsTab.account:
        return _accountContent(theme);
      case _SettingsTab.metadata:
        return _metadataContent(theme);
      case _SettingsTab.about:
        return _aboutContent(theme);
    }
  }

  String _tabLabel(_SettingsTab tab) => switch (tab) {
        _SettingsTab.preferences => 'Préférences',
        _SettingsTab.account => 'Compte',
        _SettingsTab.metadata => 'TMDB',
        _SettingsTab.about => 'À propos',
      };

  IconData _tabIcon(_SettingsTab tab) => switch (tab) {
        _SettingsTab.preferences => Icons.tune,
        _SettingsTab.account => Icons.person_outline,
        _SettingsTab.metadata => Icons.movie_filter_outlined,
        _SettingsTab.about => Icons.info_outline,
      };

  // ---------------------------------------------------------------------------
  // Contenu des onglets.
  // ---------------------------------------------------------------------------

  Widget _preferencesContent(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Préférences', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Réglages d\'affichage et de navigation.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        _homeSectionEditor(theme),
        const SizedBox(height: 28),
        _sectionOrderEditor(theme),
        const SizedBox(height: 16),
        Text(
          'D\'autres préférences seront ajoutées ici.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  Widget _accountContent(ThemeData theme) {
    final user = widget.state?.session?.user;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Compte', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (user != null) ...[
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
        ] else
          Text('Aucun compte connecté.', style: theme.textTheme.bodyMedium),
        const Divider(height: 40),
        ..._synchroSection(theme),
        const Divider(height: 40),
        ..._rawSection(theme),
      ],
    );
  }

  List<Widget> _synchroSection(ThemeData theme) {
    return [
        Text('Synchro', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Synchronise ton compte Zen IPTV : profils, sources, favoris et '
          'reprise de lecture. Mizu se connecte à l\'instance Supabase de Zen '
          '(ou à la tienne, voir re/supabase/). La synchronisation nécessite '
          'l\'offre Zen Access.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openUrl('https://zeniptv.app/'),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Créer un compte Zen IPTV'),
          ),
        ),
        const SizedBox(height: 16),
        ..._serverFields(theme),
        const SizedBox(height: 24),
        _saveButton(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text(
          'Backend : ${MizuConfig.backendUrl.isEmpty ? "non configuré" : MizuConfig.backendUrl}'
          '${MizuConfig.source.isEmpty ? "" : " (${MizuConfig.source})"}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
    ];
  }

  /// Ouvre un lien externe (navigateur / app).
  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Aucun navigateur disponible : on ignore.
    }
  }

  Widget _metadataContent(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('TMDB', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Clé TMDB (gratuite) pour les titres et affiches des favoris et de '
          'la reprise. Sans elle, les noms viennent de l\'index du catalogue.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
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
        const SizedBox(height: 24),
        _saveButton(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  List<Widget> _rawSection(ThemeData theme) {
    final state = widget.state;
    return [
      Text('Données brutes', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Vue de diagnostic : profils, sources, favoris, progression et '
          'préférences tels que lus depuis Supabase.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        if (state != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DebugPage(state: state)),
              ),
              icon: const Icon(Icons.data_object),
              label: const Text('Ouvrir les données brutes'),
            ),
          )
        else
          Text(
            'Connecte-toi pour consulter les données brutes.',
            style: theme.textTheme.bodyMedium,
          ),
    ];
  }

  Widget _aboutContent(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/logo.png', width: 64, height: 64),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mizu IPTV', style: theme.textTheme.headlineSmall),
                Text(
                  'Version 1.0.0',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Client IPTV non officiel, interopérable avec un compte Zen IPTV. '
          'Application de lecture uniquement : elle ne fournit aucun contenu.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code),
          title: const Text('Code source'),
          subtitle: const Text('github.com/iesta/mizu-iptv'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openUrl('https://github.com/iesta/mizu-iptv'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Licence MIT'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openUrl(
              'https://github.com/iesta/mizu-iptv/blob/main/LICENSE'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Signaler un problème'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openUrl('https://github.com/iesta/mizu-iptv/issues'),
        ),
        const Divider(),
        const SizedBox(height: 8),
        Text('Crédits', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Flutter · media_kit/libmpv · Supabase · TMDB. '
          'Ce produit utilise l\'API TMDB mais n\'est ni approuvé ni certifié '
          'par TMDB.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text(
          'Interopérabilité : reverse engineering par observation (API '
          'publique, chaînes du binaire, données de notre propre compte). '
          'Vérifie que la loi et les CGU t\'autorisent dans ton cas.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Éléments partagés.
  // ---------------------------------------------------------------------------

  List<Widget> _serverFields(ThemeData theme) {
    return [
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
      const SizedBox(height: 12),
      TextField(
        controller: _ua,
        decoration: const InputDecoration(
          labelText: 'User-Agent des requêtes',
          hintText: MizuConfig.defaultUserAgent,
          helperText: 'Certains panneaux filtrent les User-Agent inconnus. '
              'Laisser vide pour la valeur par défaut.',
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
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _ua.text = MizuConfig.zenUserAgent);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('User-Agent Zen appliqué — pense à Enregistrer.'),
                ),
              );
            },
            icon: const Icon(Icons.badge_outlined),
            label: const Text('UA Zen'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _ua.text = MizuConfig.defaultUserAgent);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('User-Agent Mizu rétabli — pense à Enregistrer.'),
                ),
              );
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('UA Mizu'),
          ),
          const SizedBox(width: 12),
          if (_testResult != null)
            Expanded(
              child: Row(
                children: [
                  Icon(
                    _testOk ? Icons.check_circle_outline : Icons.error_outline,
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
    ];
  }

  Widget _saveButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_outlined),
        label: const Text('Enregistrer'),
      ),
    );
  }

  // Ancienne présentation en une page, conservée pour le premier lancement.
  Widget _legacyBuild(BuildContext context) {
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
          const SizedBox(height: 12),
          TextField(
            controller: _ua,
            decoration: const InputDecoration(
              labelText: 'User-Agent des requêtes',
              hintText: MizuConfig.defaultUserAgent,
              helperText:
                  'Certains panneaux filtrent les User-Agent inconnus. '
                  'Laisser vide pour la valeur par défaut.',
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
          Text('TMDB', style: theme.textTheme.titleMedium),
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
          const SizedBox(height: 28),
          _sectionOrderEditor(theme),
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

/// Onglets de la page Préférences (ordre d'affichage).
enum _SettingsTab { preferences, account, metadata, about }
