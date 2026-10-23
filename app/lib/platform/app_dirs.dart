import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Répertoires de configuration et de cache, selon la plateforme.
///
/// Sur les plateformes de bureau Linux on garde les conventions XDG
/// (`~/.config/mizu`, `~/.cache/mizu`). Sur Android / iOS / macOS / Windows,
/// `$HOME` n'existe pas ou n'est pas inscriptible : on utilise les dossiers
/// applicatifs fournis par le système.
class AppDirs {
  static late String configDir;
  static late String cacheDir;

  static bool get _isDesktopLinux =>
      Platform.isLinux && !Platform.environment.containsKey('ANDROID_DATA');

  static Future<void> init() async {
    if (_isDesktopLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      configDir = '$home/.config/mizu';
      cacheDir = '$home/.cache/mizu';
      return;
    }

    final support = await getApplicationSupportDirectory();
    configDir = support.path;
    try {
      cacheDir = (await getApplicationCacheDirectory()).path;
    } catch (_) {
      cacheDir = support.path;
    }
  }

  static Future<void> ensureConfigDir() async {
    await Directory(configDir).create(recursive: true);
  }

  static Future<void> ensureCacheDir() async {
    await Directory(cacheDir).create(recursive: true);
  }
}
