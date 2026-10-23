import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Vue « données brutes » : sert à valider le protocole de synchronisation
/// avant d'écrire quoi que ce soit côté serveur.
class DebugPage extends StatefulWidget {
  const DebugPage({super.key, required this.state});

  final AppState state;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  late Future<Map<String, dynamic>> _future;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _future = widget.state.repo.rawDump(widget.state.activeProfileId);
  }

  Future<void> _save(Map<String, dynamic> data) async {
    final home = Platform.environment['HOME'] ?? '.';
    final file = File('$home/zeniptv-dump.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    setState(() => _savedPath = file.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Données de synchronisation'),
        actions: [
          IconButton(
            tooltip: 'Recharger',
            onPressed: () => setState(() {
              _future = widget.state.repo.rawDump(widget.state.activeProfileId);
            }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erreur: ${snap.error}'));
          }
          final data = snap.data ?? const <String, dynamic>{};
          final pretty = const JsonEncoder.withIndent('  ').convert(data);
          return Column(
            children: [
              if (_savedPath != null)
                MaterialBanner(
                  content: Text('Enregistré dans $_savedPath'),
                  leading: const Icon(Icons.check_circle_outline),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _savedPath = null),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    pretty,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _save(data),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Enregistrer ~/zeniptv-dump.json'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
