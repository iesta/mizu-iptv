import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../mizu_config.dart';
import '../state/app_state.dart';

/// Lecteur basé sur libmpv (media_kit).
///
/// - pistes audio / sous-titres sélectionnables
/// - reprise : `initialPosition` appliqué dès que la durée est connue
/// - enregistrement de la position toutes les 15 s et à la fermeture
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.state,
    required this.url,
    required this.title,
    this.subtitle,
    this.contentId,
    this.contentType,
    this.season,
    this.episode,
    this.initialPosition,
  });

  final AppState state;
  final String url;
  final String title;
  final String? subtitle;
  final String? contentId;
  final String? contentType;
  final int? season;
  final int? episode;
  final Duration? initialPosition;

  bool get tracksProgress {
    // Les chaînes en direct n'ont pas de progression : ne jamais écrire dans
    // `serie_progress` pour elles (cela créait des lignes parasites).
    if (contentId == null || contentType == null) return false;
    if (contentType == 'serie') return season != null && episode != null;
    if (contentType == 'vod') return true;
    return false;
  }

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _ticker;

  double _volume = 100;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _seekable = false;
  bool _fullscreen = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  String? _osdText;
  Timer? _osdTimer;
  // Accumulation des sauts rapprochés (ex. 3 × +10 s → +30 s).
  int _pendingJump = 0;
  Duration? _pendingTarget;
  Timer? _seekAccumTimer;
  String? _error;
  Duration? _pendingSeek;

  Tracks _tracks = const Tracks();
  AudioTrack _audio = AudioTrack.auto();
  SubtitleTrack _subtitles = SubtitleTrack.auto();

  @override
  void initState() {
    super.initState();
    _pendingSeek = widget.initialPosition;
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Mizu IPTV',
        logLevel: MPVLogLevel.error,
      ),
    );
    _controller = VideoController(_player);

    _subs.add(_player.stream.position.listen((p) => setState(() => _position = p)));
    _subs.add(_player.stream.duration.listen((d) {
      setState(() {
        _duration = d;
        // Un flux direct n'a pas de durée fiable : mpv annonce parfois
        // quelques secondes, ce qui afficherait une fausse barre de progression.
        _seekable = widget.contentType != 'channel' &&
            d > const Duration(seconds: 5);
      });
      final pending = _pendingSeek;
      if (pending != null && d > const Duration(seconds: 1)) {
        _pendingSeek = null;
        _player.seek(pending);
      }
    }));
    _subs.add(_player.stream.playing.listen((p) {
      setState(() => _playing = p);
      if (p) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        setState(() => _controlsVisible = true);
      }
    }));
    _subs.add(_player.stream.volume.listen((v) => setState(() => _volume = v)));
    _subs.add(_player.stream.error.listen((e) => setState(() => _error = e)));
    _subs.add(_player.stream.width.listen(
        (w) => debugPrint('player: video width=$w')));
    _subs.add(_player.stream.height.listen(
        (h) => debugPrint('player: video height=$h')));
    _subs.add(_player.stream.tracks.listen((t) {
      debugPrint('player: pistes audio=${t.audio.length} '
          'subs=${t.subtitle.length} '
          '${t.audio.map((a) => '${a.language ?? a.title ?? a.id}').join(',')}');
      setState(() => _tracks = t);
    }));
    _subs.add(_player.stream.track.listen((t) {
      setState(() {
        _audio = t.audio;
        _subtitles = t.subtitle;
      });
    }));

    // Certains panneaux vérifient le User-Agent aussi sur le flux.
    _player.open(Media(
      widget.url,
      httpHeaders: {'User-Agent': MizuConfig.userAgent},
    ));

    if (widget.tracksProgress) {
      _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _saveProgress());
    }
  }

  Future<void> _saveProgress() async {
    if (!widget.tracksProgress) return;
    final d = _duration.inMilliseconds;
    final p = _position.inMilliseconds;
    if (d <= 0 || p <= 0) return;
    final fraction = (p / d).clamp(0.0, 1.0).toDouble();
    try {
      await widget.state.saveProgress(
        serieId: widget.contentId!,
        season: widget.season ?? 0,
        episode: widget.episode ?? 0,
        positionSeconds: p / 1000,
        fraction: fraction,
        runtimeType: widget.contentType == 'vod' ? 'vod' : 'serie',
        allEpisodesWatched: fraction > 0.95,
      );
    } catch (_) {
      // Une écriture de progression ne doit jamais interrompre la lecture.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _seekAccumTimer?.cancel();
    _saveProgress();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  /// Contrôles visibles quand on les a demandés, ou à l'arrêt (pause).
  bool get _showChrome => _controlsVisible || !_playing;

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  /// Clic sur l'image : affiche les contrôles, ou les masque s'ils sont déjà là.
  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  /// OSD éphémère au centre (« +10 s », « -1m »…).
  void _showOsd(String text) {
    _osdTimer?.cancel();
    setState(() => _osdText = text);
    _osdTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _osdText = null);
    });
  }

  /// Pas de saut : 10 s, 60 s avec Ctrl/⌘, 10 min avec Ctrl/⌘+Maj.
  int get _seekJump {
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && HardwareKeyboard.instance.isShiftPressed) return 600;
    return ctrl ? 60 : 10;
  }

  /// Saut cumulatif : les pressions rapprochées s'additionnent (3 × +10 s →
  /// +30 s) au lieu de repartir d'une position encore périmée. Le cumul est
  /// oublié après [_seekAccumDelay] sans nouvelle pression.
  static const Duration _seekAccumDelay = Duration(milliseconds: 800);

  void _seekBy(int seconds) {
    if (seconds == 0) return;
    // Changement de sens : on repart de la position courante.
    if (_pendingJump != 0 && (_pendingJump < 0) != (seconds < 0)) {
      _pendingJump = 0;
      _pendingTarget = null;
    }
    final target = (_pendingTarget ?? _position) + Duration(seconds: seconds);
    _pendingTarget = target;
    _pendingJump += seconds;
    _player.seek(target);
    _showOsd(_fmtJump(_pendingJump));
    _seekAccumTimer?.cancel();
    _seekAccumTimer = Timer(_seekAccumDelay, () {
      _pendingJump = 0;
      _pendingTarget = null;
    });
  }

  /// « +30s », « -1m », « +1m10 »…
  String _fmtJump(int seconds) {
    final sign = seconds >= 0 ? '+' : '-';
    final total = seconds.abs();
    final minutes = total ~/ 60;
    final rest = total % 60;
    if (minutes == 0) return '$sign${rest}s';
    if (rest == 0) return '$sign${minutes}m';
    return '$sign${minutes}m${rest.toString().padLeft(2, '0')}';
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  static const _languages = {
    'fre': 'Français', 'fra': 'Français', 'fr': 'Français',
    'eng': 'Anglais', 'en': 'Anglais',
    'spa': 'Espagnol', 'es': 'Espagnol',
    'ger': 'Allemand', 'deu': 'Allemand', 'de': 'Allemand',
    'ita': 'Italien', 'it': 'Italien',
    'por': 'Portugais', 'pt': 'Portugais',
    'jpn': 'Japonais', 'ja': 'Japonais',
    'rus': 'Russe', 'ru': 'Russe',
    'ara': 'Arabe', 'ar': 'Arabe',
    'tur': 'Turc', 'tr': 'Turc',
    'nld': 'Néerlandais', 'dut': 'Néerlandais', 'nl': 'Néerlandais',
    'pol': 'Polonais', 'pl': 'Polonais',
  };

  String _trackLabel(String? code, String? title, String? language, int index) {
    final lang = (language ?? code ?? '').toLowerCase();
    final langName = _languages[lang];
    final parts = <String>[
      if (title != null && title.isNotEmpty && title.toLowerCase() != lang) title,
      if (langName != null) langName else if (lang.isNotEmpty) lang.toUpperCase(),
    ];
    return parts.isEmpty ? 'Piste ${index + 1}' : parts.join(' · ');
  }

  Future<void> _pickAudio() async {
    final tracks = _player.state.tracks.audio;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Langue audio'),
              dense: true,
              titleTextStyle: TextStyle(fontWeight: FontWeight.w600),
            ),
            for (var i = 0; i < tracks.length; i++)
              ListTile(
                leading: Icon(_audio.id == tracks[i].id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(_trackLabel(
                    tracks[i].id, tracks[i].title, tracks[i].language, i)),
                onTap: () {
                  _player.setAudioTrack(tracks[i]);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSubtitles() async {
    final tracks = _player.state.tracks.subtitle;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Sous-titres'),
              dense: true,
              titleTextStyle: TextStyle(fontWeight: FontWeight.w600),
            ),
            ListTile(
              leading: Icon(_subtitles.id == 'no' || _subtitles.id == 'auto'
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: const Text('Désactivés'),
              onTap: () {
                _player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.of(context).pop();
              },
            ),
            for (var i = 0; i < tracks.length; i++)
              ListTile(
                leading: Icon(_subtitles.id == tracks[i].id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(_trackLabel(
                    tracks[i].id, tracks[i].title, tracks[i].language, i)),
                onTap: () {
                  _player.setSubtitleTrack(tracks[i]);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _toggleFullscreen() {
    if (!mounted) return;
    setState(() => _fullscreen = !_fullscreen);
    _showControls();
  }

  /// Télécommande / clavier : Espace = pause, ←/→ = ±10 s, ↑/↓ = volume,
  /// Ctrl/⌘+F = plein écran, Échap/Retour = revenir à la fiche.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_seekJump);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(_seekJump);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _player.setVolume((_volume + 5).clamp(0, 100));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _player.setVolume((_volume - 5).clamp(0, 100));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _player.setVolume(_volume > 0 ? 0 : 100);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showChrome = _showChrome;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: _fullscreen ? BoxFit.cover : BoxFit.contain,
                ),
              ),
            ),
            // Clic sur l'image : afficher / masquer les contrôles.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: theme.colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text('Lecture impossible : $_error',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            if (showChrome) ..._chrome(theme),
            // OSD de saut (±10 s / ±1 min), au-dessus du reste.
            Align(
              alignment: const Alignment(0, -0.45),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _osdText == null ? 0 : 1,
                  duration: const Duration(milliseconds: 140),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      _osdText ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Superposition des contrôles : barre haute, bouton central, barre basse.
  List<Widget> _chrome(ThemeData theme) {
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
          child: Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('retour'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              if (widget.contentId != null && widget.contentType != null)
                ListenableBuilder(
                  listenable: widget.state,
                  builder: (context, _) {
                    final fav = widget.state
                        .isFavorite(widget.contentId!, widget.contentType!);
                    return IconButton(
                      color: Colors.white,
                      tooltip:
                          fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                      icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
                      onPressed: () => widget.state.toggleFavorite(
                          widget.contentId!, widget.contentType!),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      Center(
        child: IconButton.filled(
          iconSize: 56,
          padding: const EdgeInsets.all(20),
          tooltip: _playing ? 'Pause' : 'Lecture',
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            _player.playOrPause();
            _showControls();
          },
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_seekable)
                Slider(
                  min: 0,
                  max: _duration.inMilliseconds
                      .toDouble()
                      .clamp(1, double.infinity),
                  value: _position.inMilliseconds
                      .toDouble()
                      .clamp(0, _duration.inMilliseconds.toDouble()),
                  onChanged: (v) {
                    _player.seek(Duration(milliseconds: v.round()));
                    _showControls();
                  },
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.podcasts, size: 14, color: Colors.white70),
                      SizedBox(width: 6),
                      Text('Flux direct',
                          style: TextStyle(
                              fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
              Row(
                children: [
                  if (_seekable)
                    Text('${_fmt(_position)} / ${_fmt(_duration)}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  const Spacer(),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Langue audio (${_tracks.audio.length})',
                    icon: const Icon(Icons.record_voice_over_outlined),
                    onPressed: _tracks.audio.isEmpty ? null : _pickAudio,
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Sous-titres (${_tracks.subtitle.length})',
                    icon: const Icon(Icons.subtitles_outlined),
                    onPressed: _pickSubtitles,
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Avancer de 90 s',
                    icon: const Icon(Icons.skip_next),
                    onPressed: () {
                      _seekBy(90);
                      _showControls();
                    },
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Plein écran (Ctrl+F)',
                    icon: Icon(
                        _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
