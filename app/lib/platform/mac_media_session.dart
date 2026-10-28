import 'dart:io';

import 'package:flutter/services.dart';

/// Touches média macOS (play/pause) et widget « En lecture » du centre de
/// contrôle, via MPNowPlayingInfoCenter / MPRemoteCommandCenter.
///
/// Le canal est branché côté Swift dans `MainFlutterWindow.swift`. Sans
/// `nowPlayingInfo`, macOS ne nous envoie pas les touches : on publie donc
/// titre, durée et position à chaque changement d'état.
class MacMediaSession {
  MacMediaSession._();

  static final MacMediaSession instance = MacMediaSession._();
  static const MethodChannel _channel =
      MethodChannel('app.mizu.iptv/media');

  String _title = 'Mizu IPTV';
  String? _subtitle;
  Duration? _duration;
  Duration _position = Duration.zero;
  bool _playing = false;

  void Function()? _onPlay;
  void Function()? _onPause;
  void Function()? _onPlayPause;
  void Function()? _onStop;

  Future<void> start({
    required String title,
    String? subtitle,
    required void Function() onPlay,
    required void Function() onPause,
    required void Function() onPlayPause,
    required void Function() onStop,
  }) async {
    if (!Platform.isMacOS) return;
    _title = title;
    _subtitle = subtitle;
    _onPlay = onPlay;
    _onPause = onPause;
    _onPlayPause = onPlayPause;
    _onStop = onStop;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          _onPlay?.call();
        case 'pause':
          _onPause?.call();
        case 'toggle':
          _onPlayPause?.call();
        case 'stop':
          _onStop?.call();
      }
      return null;
    });
    await _publish();
  }

  Future<void> setPlaying(bool playing,
      {Duration? position, Duration? duration}) async {
    if (!Platform.isMacOS) return;
    _playing = playing;
    if (position != null) _position = position;
    if (duration != null) _duration = duration;
    await _publish();
  }

  /// Met à jour la durée quand elle devient connue (après le premier buffer).
  Future<void> setDuration(Duration duration) async {
    if (!Platform.isMacOS) return;
    _duration = duration;
    await _publish();
  }

  Future<void> dispose() async {
    if (!Platform.isMacOS) return;
    _onPlay = _onPause = _onPlayPause = _onStop = null;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // L'application se ferme : rien à signaler.
    }
  }

  Future<void> _publish() async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': _title,
        'subtitle': _subtitle ?? '',
        'playing': _playing,
        'position': _position.inMilliseconds / 1000,
        'duration': (_duration?.inMilliseconds ?? 0) / 1000,
      });
    } catch (_) {
      // Canal absent (Linux, tests) : sans effet.
    }
  }
}
