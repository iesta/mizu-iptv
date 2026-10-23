import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _seekable = false;
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
        _seekable = d > const Duration(seconds: 1);
      });
      final pending = _pendingSeek;
      if (pending != null && d > const Duration(seconds: 1)) {
        _pendingSeek = null;
        _player.seek(pending);
      }
    }));
    _subs.add(_player.stream.playing.listen((p) => setState(() => _playing = p)));
    _subs.add(_player.stream.error.listen((e) => setState(() => _error = e)));
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

    _player.open(Media(widget.url));

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
    _saveProgress();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            if (widget.subtitle != null)
              Text(widget.subtitle!,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
          ],
        ),
        actions: [
          if (widget.contentId != null && widget.contentType != null)
            ListenableBuilder(
              listenable: widget.state,
              builder: (context, _) {
                final fav = widget.state
                    .isFavorite(widget.contentId!, widget.contentType!);
                return IconButton(
                  tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
                  onPressed: () => widget.state
                      .toggleFavorite(widget.contentId!, widget.contentType!),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text('Lecture impossible : $_error',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          Expanded(
            child: Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainer,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                if (_seekable)
                  Slider(
                    min: 0,
                    max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    value: _position.inMilliseconds
                        .toDouble()
                        .clamp(0, _duration.inMilliseconds.toDouble()),
                    onChanged: (v) =>
                        _player.seek(Duration(milliseconds: v.round())),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.podcasts, size: 14),
                        SizedBox(width: 6),
                        Text('Flux direct', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      iconSize: 36,
                      icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
                      onPressed: _player.playOrPause,
                    ),
                    if (_seekable)
                      Text('${_fmt(_position)} / ${_fmt(_duration)}',
                          style: const TextStyle(fontSize: 12)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Langue audio (${_tracks.audio.length})',
                      icon: const Icon(Icons.record_voice_over_outlined),
                      onPressed: _tracks.audio.isEmpty ? null : _pickAudio,
                    ),
                    IconButton(
                      tooltip: 'Sous-titres (${_tracks.subtitle.length})',
                      icon: const Icon(Icons.subtitles_outlined),
                      onPressed: _pickSubtitles,
                    ),
                    IconButton(
                      tooltip: 'Avancer de 90 s',
                      icon: const Icon(Icons.skip_next),
                      onPressed: () => _player.seek(_position + const Duration(seconds: 90)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
