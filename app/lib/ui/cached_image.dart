import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../mizu_config.dart';
import '../platform/app_dirs.dart';

/// Cache disque des images (covers TMDB / Xtream) pour éviter de re-télécharger
/// à chaque démarrage. TTL 30 jours, taille maximale 500 Mo.
class AppImageCache {
  AppImageCache._();

  static final AppImageCache instance = AppImageCache._();

  static const Duration ttl = Duration(days: 30);
  static const int maxBytes = 500 * 1024 * 1024;

  final Map<String, Future<Uint8List?>> _inflight = {};
  bool _pruned = false;

  Directory get _dir => Directory('${AppDirs.cacheDir}/images');

  static String _key(String url) {
    var hash = 0xcbf29ce484222325;
    for (final code in url.codeUnits) {
      hash ^= code;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<Uint8List?> load(String url) {
    final existing = _inflight[url];
    if (existing != null) return existing;
    if (!_pruned) {
      _pruned = true;
      // Élagage en tâche de fond, une fois par session.
      Future<void>.delayed(Duration.zero, _prune);
    }
    final future = _load(url);
    _inflight[url] = future;
    if (_inflight.length > 800) {
      _inflight.removeWhere((key, _) => key != url);
    }
    return future;
  }

  Future<Uint8List?> _load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final file = File('${_dir.path}/${_key(url)}');
    try {
      if (await file.exists()) {
        final stat = await file.stat();
        if (DateTime.now().difference(stat.modified) < ttl) {
          return await file.readAsBytes();
        }
        await file.delete();
      }
    } catch (_) {
      // Fichier illisible : on retente le réseau.
    }
    try {
      final res = await http.get(
        uri,
        headers: {'User-Agent': MizuConfig.userAgent},
      ).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      try {
        await _dir.create(recursive: true);
        await file.writeAsBytes(res.bodyBytes, flush: false);
      } catch (_) {
        // Cache best-effort : l'image reste utilisable.
      }
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  void _prune() {
    try {
      if (!_dir.existsSync()) return;
      final now = DateTime.now();
      final kept = <File, FileStat>{};
      var total = 0;
      for (final entity in _dir.listSync()) {
        if (entity is! File) continue;
        try {
          final stat = entity.statSync();
          if (now.difference(stat.modified) >= ttl) {
            entity.deleteSync();
          } else {
            kept[entity] = stat;
            total += stat.size;
          }
        } catch (_) {}
      }
      if (total <= maxBytes) return;
      final sorted = kept.entries.toList()
        ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
      for (final entry in sorted) {
        if (total <= maxBytes) break;
        try {
          entry.key.deleteSync();
          total -= entry.value.size;
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// Image avec cache disque, API proche de `Image.network`.
class CachedImage extends StatelessWidget {
  const CachedImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.errorBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: CachedImageProvider(url),
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      errorBuilder: errorBuilder,
    );
  }
}

class CachedImageProvider extends ImageProvider<CachedImageProvider> {
  const CachedImageProvider(this.url);

  final String url;

  @override
  Future<CachedImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      CachedImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      debugLabel: key.url,
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
      CachedImageProvider key, ImageDecoderCallback decode) async {
    final bytes = await AppImageCache.instance.load(key.url);
    if (bytes == null) {
      throw Exception('Image indisponible: ${key.url}');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is CachedImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'CachedImageProvider("$url")';
}
