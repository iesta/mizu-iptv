import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// Palette Omarchy compilée (`~/.local/state/omarchy/current/theme/colors.toml`).
///
/// Omarchy régénère ce fichier à chaque `omarchy theme set` : on le relit
/// périodiquement pour suivre les changements de thème à chaud.
class OmarchyPalette {
  OmarchyPalette(this._values);

  final Map<String, String> _values;

  static File get _colorsFile {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return File('/nonexistent');
    return File('$home/.local/state/omarchy/current/theme/colors.toml');
  }

  /// `null` si Omarchy n'est pas installé (ou pas de thème actif).
  static OmarchyPalette? tryLoad() {
    try {
      final file = _colorsFile;
      if (!file.existsSync()) return null;
      final values = <String, String>{};
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = trimmed.indexOf('=');
        if (eq <= 0) continue;
        final key = trimmed.substring(0, eq).trim();
        var value = trimmed.substring(eq + 1).trim();
        if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
          value = value.substring(1, value.length - 1);
        }
        values[key] = value;
      }
      if (values.isEmpty) return null;
      return OmarchyPalette(values);
    } catch (_) {
      return null;
    }
  }

  DateTime? get lastModified {
    try {
      return _colorsFile.lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  Color? color(String key) => _parse(_values[key]);

  Color? get accent => color('accent');
  Color? get background => color('background') ?? color('dark_background');
  Color? get foreground => color('foreground');
  Color? get muted => color('muted');
  Color? get selection => color('selection');
  Color? get lighterBackground =>
      color('lighter_background') ?? color('selection');
  Color? get red => color('red');
  Color? get green => color('green');
  Color? get blue => color('blue');
  Color? get yellow => color('yellow');
  Color? get cyan => color('cyan');
  Color? get magenta => color('magenta');

  static Color? _parse(String? raw) {
    if (raw == null) return null;
    var v = raw.trim();
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 6) v = 'ff$v';
    if (v.length != 8) return null;
    final value = int.tryParse(v, radix: 16);
    return value == null ? null : Color(value);
  }
}

class ZenTheme {
  static const Color _seed = Color(0xFF7C5CFF);

  /// Thème par défaut (hors Omarchy).
  static ThemeData fallback() => _base(
        ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        background: const Color(0xFF0E0E12),
        card: const Color(0xFF17171F),
      );

  /// Thème dérivé de la palette Omarchy.
  static ThemeData fromOmarchy(OmarchyPalette palette) {
    final background = palette.background ?? const Color(0xFF0E0E12);
    final foreground = palette.foreground ?? Colors.white;
    final accent = palette.accent ?? _seed;
    final card = palette.lighterBackground ??
        Color.alphaBlend(Colors.white.withValues(alpha: 0.06), background);
    final muted = palette.muted ?? foreground.withValues(alpha: 0.6);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: _on(accent),
      secondary: palette.cyan ?? palette.blue ?? accent,
      onSecondary: _on(palette.cyan ?? palette.blue ?? accent),
      tertiary: palette.magenta ?? accent,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainer: card,
      surfaceContainerHigh: card,
      surfaceContainerHighest:
          palette.selection ?? card.withValues(alpha: 0.9),
      outline: muted,
      error: palette.red ?? const Color(0xFFE5484D),
    );

    return _base(scheme, background: background, card: card);
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Color background,
    required Color card,
  }) {
    final click = const WidgetStatePropertyAll(SystemMouseCursors.click);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: click),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(mouseCursor: click),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(mouseCursor: click),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(mouseCursor: click),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(mouseCursor: click),
      ),
    );
  }

  static Color _on(Color background) =>
      background.computeLuminance() > 0.55 ? Colors.black : Colors.white;
}

/// Suit le thème Omarchy et reconstruit l'application quand il change.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _poll());
  }

  Timer? _timer;
  DateTime? _stamp;
  OmarchyPalette? _palette;
  late ThemeData _theme = ZenTheme.fallback();

  ThemeData get theme => _theme;
  bool get usingOmarchy => _palette != null;
  String get paletteName => usingOmarchy ? 'Omarchy' : 'défaut';

  void _reload() {
    final palette = OmarchyPalette.tryLoad();
    _palette = palette;
    _stamp = palette?.lastModified;
    _theme = palette == null ? ZenTheme.fallback() : ZenTheme.fromOmarchy(palette);
    notifyListeners();
  }

  void _poll() {
    final palette = OmarchyPalette.tryLoad();
    final stamp = palette?.lastModified;
    final changed = (palette == null) != (_palette == null) ||
        (stamp != null && _stamp != null && stamp != _stamp);
    if (!changed) return;
    _palette = palette;
    _stamp = stamp;
    _theme = palette == null ? ZenTheme.fallback() : ZenTheme.fromOmarchy(palette);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
