import 'dart:io';

import 'package:flutter/services.dart';

/// Échelle d'interface selon la cible.
///
/// Android TV rapporte ~960×540 logiques en xhdpi : sans correction, tout le
/// texte paraît deux fois trop gros à 3 m. On applique donc un facteur < 1 au
/// texte sur TV uniquement, les autres plateformes restant inchangées.
class UiScale {
  UiScale._();

  static const MethodChannel _channel = MethodChannel('app.mizu.iptv/ui');

  /// Vrai sur un appareil Android TV (`UI_MODE_TYPE_TELEVISION`).
  static bool isTv = false;

  /// Facteur appliqué à l'échelle de texte globale.
  static double get textFactor => isTv ? 0.7 : 1.0;

  /// À appeler une fois au démarrage.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } catch (_) {
      // Canal absent (tests, autre cible) : on reste sur le comportement normal.
    }
  }
}
