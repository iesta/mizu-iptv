import 'dart:io';

import 'package:dbus/dbus.dart';

/// Expose le lecteur en MPRIS sous Linux : les touches média / contrôles
/// système (omarchy-shell, playerctl, barres média…) peuvent alors
/// lire / mettre en pause / arrêter le film.
class MprisService {
  MprisService._();

  static final MprisService instance = MprisService._();
  static const String _busName = 'org.mpris.MediaPlayer2.mizu';

  DBusClient? _client;
  _MprisObject? _object;
  bool _starting = false;

  void Function()? _onPlay;
  void Function()? _onPause;
  void Function()? _onPlayPause;
  void Function()? _onStop;
  void Function(Duration)? _onSeek;
  void Function(Duration)? _onSetPosition;
  Duration Function()? _position;

  String _title = 'Mizu IPTV';
  String _artist = '';
  String _status = 'Stopped';

  String get playbackStatus => _status;

  Future<void> start({
    required String title,
    String? subtitle,
    required void Function() onPlay,
    required void Function() onPause,
    required void Function() onPlayPause,
    required void Function() onStop,
    required void Function(Duration) onSeek,
    required void Function(Duration) onSetPosition,
    required Duration Function() position,
  }) async {
    if (!Platform.isLinux) return;
    _title = title;
    _artist = subtitle ?? '';
    _onPlay = onPlay;
    _onPause = onPause;
    _onPlayPause = onPlayPause;
    _onStop = onStop;
    _onSeek = onSeek;
    _onSetPosition = onSetPosition;
    _position = position;

    if (_client != null) {
      await _object?.emitPropertiesChanged(
        'org.mpris.MediaPlayer2.Player',
        changedProperties: {'Metadata': metadataValue()},
      );
      return;
    }
    if (_starting) return;
    _starting = true;
    final client = DBusClient.session();
    try {
      await client.requestName(_busName);
      final object = _MprisObject(this);
      await client.registerObject(object);
      _object = object;
      _client = client;
      _status = 'Stopped';
    } catch (_) {
      try {
        await client.close();
      } catch (_) {}
    } finally {
      _starting = false;
    }
  }

  void setPlaying(bool playing) {
    final status = playing ? 'Playing' : 'Paused';
    if (_status == status) return;
    _status = status;
    _emit({'PlaybackStatus': DBusString(_status)});
  }

  void updateMetadata(String title, {String? subtitle}) {
    _title = title;
    if (subtitle != null) _artist = subtitle;
    _emit({'Metadata': metadataValue()});
  }

  void _emit(Map<String, DBusValue> changed) {
    _object?.emitPropertiesChanged(
      'org.mpris.MediaPlayer2.Player',
      changedProperties: changed,
    );
  }

  DBusValue metadataValue() {
    return DBusDict.stringVariant({
      'mpris:trackid': DBusObjectPath('/org/mpris/MediaPlayer2/Track/1'),
      'xesam:title': DBusString(_title),
      'xesam:artist': DBusArray.string([if (_artist.isNotEmpty) _artist]),
    });
  }

  Duration positionNow() => _position?.call() ?? Duration.zero;

  // Appelés par l'objet D-Bus.

  void play() => _onPlay?.call();
  void pause() => _onPause?.call();
  void playPause() => _onPlayPause?.call();
  void playbackStop() => _onStop?.call();
  void seek(Duration offset) => _onSeek?.call(offset);
  void setPosition(Duration position) => _onSetPosition?.call(position);

  /// Libère le nom et l'objet MPRIS (fermeture du lecteur).
  Future<void> dispose() async {
    final client = _client;
    final object = _object;
    _client = null;
    _object = null;
    _status = 'Stopped';
    if (client == null) return;
    try {
      if (object != null) await client.unregisterObject(object);
    } catch (_) {}
    try {
      await client.releaseName(_busName);
    } catch (_) {}
    try {
      await client.close();
    } catch (_) {}
  }
}

class _MprisObject extends DBusObject {
  _MprisObject(this.service)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  final MprisService service;

  static const String _root = 'org.mpris.MediaPlayer2';
  static const String _player = 'org.mpris.MediaPlayer2.Player';

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(
          _root,
          methods: [
            DBusIntrospectMethod('Raise'),
            DBusIntrospectMethod('Quit'),
          ],
          properties: [
            DBusIntrospectProperty('CanQuit', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanRaise', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('HasTrackList', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('Identity', DBusSignature('s'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('DesktopEntry', DBusSignature('s'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('SupportedUriSchemes', DBusSignature('as'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('SupportedMimeTypes', DBusSignature('as'),
                access: DBusPropertyAccess.read),
          ],
        ),
        DBusIntrospectInterface(
          _player,
          methods: [
            DBusIntrospectMethod('Next'),
            DBusIntrospectMethod('Previous'),
            DBusIntrospectMethod('Pause'),
            DBusIntrospectMethod('PlayPause'),
            DBusIntrospectMethod('Stop'),
            DBusIntrospectMethod('Play'),
            DBusIntrospectMethod('Seek', args: [
              DBusIntrospectArgument(DBusSignature('x'),
                  DBusArgumentDirection.in_, name: 'Offset'),
            ]),
            DBusIntrospectMethod('SetPosition', args: [
              DBusIntrospectArgument(DBusSignature('o'),
                  DBusArgumentDirection.in_, name: 'TrackId'),
              DBusIntrospectArgument(DBusSignature('x'),
                  DBusArgumentDirection.in_, name: 'Position'),
            ]),
            DBusIntrospectMethod('OpenUri', args: [
              DBusIntrospectArgument(DBusSignature('s'),
                  DBusArgumentDirection.in_, name: 'Uri'),
            ]),
          ],
          signals: [
            DBusIntrospectSignal('Seeked', args: [
              DBusIntrospectArgument(DBusSignature('x'),
                  DBusArgumentDirection.out, name: 'Position'),
            ]),
          ],
          properties: [
            DBusIntrospectProperty('PlaybackStatus', DBusSignature('s'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('LoopStatus', DBusSignature('s'),
                access: DBusPropertyAccess.readwrite),
            DBusIntrospectProperty('Rate', DBusSignature('d'),
                access: DBusPropertyAccess.readwrite),
            DBusIntrospectProperty('Shuffle', DBusSignature('b'),
                access: DBusPropertyAccess.readwrite),
            DBusIntrospectProperty('Metadata', DBusSignature('a{sv}'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('Volume', DBusSignature('d'),
                access: DBusPropertyAccess.readwrite),
            DBusIntrospectProperty('Position', DBusSignature('x'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('MinimumRate', DBusSignature('d'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('MaximumRate', DBusSignature('d'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanGoNext', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanGoPrevious', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanPlay', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanPause', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanSeek', DBusSignature('b'),
                access: DBusPropertyAccess.read),
            DBusIntrospectProperty('CanControl', DBusSignature('b'),
                access: DBusPropertyAccess.read),
          ],
        ),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == _root) {
      if (call.name == 'Raise' || call.name == 'Quit') {
        return DBusMethodSuccessResponse([]);
      }
      return DBusMethodErrorResponse.unknownMethod();
    }
    if (call.interface == _player) {
      switch (call.name) {
        case 'Play':
          service.play();
          return DBusMethodSuccessResponse([]);
        case 'Pause':
          service.pause();
          return DBusMethodSuccessResponse([]);
        case 'PlayPause':
          service.playPause();
          return DBusMethodSuccessResponse([]);
        case 'Stop':
          service.playbackStop();
          return DBusMethodSuccessResponse([]);
        case 'Next':
        case 'Previous':
        case 'OpenUri':
          return DBusMethodSuccessResponse([]);
        case 'Seek':
          if (call.signature != DBusSignature('x')) {
            return DBusMethodErrorResponse.invalidArgs();
          }
          service.seek(Duration(microseconds: call.values[0].asInt64()));
          return DBusMethodSuccessResponse([]);
        case 'SetPosition':
          if (call.signature != DBusSignature('ox')) {
            return DBusMethodErrorResponse.invalidArgs();
          }
          service.setPosition(Duration(microseconds: call.values[1].asInt64()));
          return DBusMethodSuccessResponse([]);
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final properties = _propertiesFor(interface);
    final value = properties[name];
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(_propertiesFor(interface));
  }

  Map<String, DBusValue> _propertiesFor(String interface) {
    if (interface == _root) {
      return {
        'CanQuit': DBusBoolean(true),
        'CanRaise': DBusBoolean(false),
        'HasTrackList': DBusBoolean(false),
        'Identity': DBusString('Mizu IPTV'),
        'DesktopEntry': DBusString('app.mizu.iptv'),
        'SupportedUriSchemes': DBusArray.string(const []),
        'SupportedMimeTypes': DBusArray.string(const []),
      };
    }
    if (interface == _player) {
      return {
        'PlaybackStatus': DBusString(service.playbackStatus),
        'LoopStatus': DBusString('None'),
        'Rate': DBusDouble(1.0),
        'Shuffle': DBusBoolean(false),
        'Metadata': service.metadataValue(),
        'Volume': DBusDouble(1.0),
        'Position': DBusInt64(service.positionNow().inMicroseconds),
        'MinimumRate': DBusDouble(1.0),
        'MaximumRate': DBusDouble(1.0),
        'CanGoNext': DBusBoolean(false),
        'CanGoPrevious': DBusBoolean(false),
        'CanPlay': DBusBoolean(true),
        'CanPause': DBusBoolean(true),
        'CanSeek': DBusBoolean(true),
        'CanControl': DBusBoolean(true),
      };
    }
    return const {};
  }
}
