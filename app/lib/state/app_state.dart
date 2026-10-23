import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/catalog_index.dart';
import '../data/metadata_service.dart';
import '../data/models.dart';
import '../data/sync_repository.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (Supabase.instance.client.auth.currentSession == null) {
        _loaded = false;
      } else if (!_loaded) {
        refresh();
      }
      notifyListeners();
    });
    if (Supabase.instance.client.auth.currentSession != null) {
      refresh();
    }
  }

  late final StreamSubscription<AuthState> _authSub;

  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<WatchProfile> _profiles = const [];
  String? _activeProfileId;
  Map<String, dynamic>? _preferences;
  List<PlaylistSource> _sources = const [];
  List<FavoriteItem> _favorites = const [];
  List<ProgressItem> _progress = const [];

  Session? get session => Supabase.instance.client.auth.currentSession;
  bool get isSignedIn => session != null;
  bool get loading => _loading;
  String? get error => _error;

  List<WatchProfile> get profiles => _profiles;
  String? get activeProfileId => _activeProfileId;
  WatchProfile? get activeProfile {
    for (final p in _profiles) {
      if (p.id == _activeProfileId) return p;
    }
    return null;
  }
  Map<String, dynamic>? get preferences => _preferences;
  List<PlaylistSource> get sources => _sources;
  List<FavoriteItem> get favorites => _favorites;
  List<ProgressItem> get progress => _progress;

  SyncRepository get repo => SyncRepository(Supabase.instance.client);

  final MetadataService metadata = MetadataService();

  final List<RealtimeChannel> _channels = [];
  Timer? _pollTimer;
  Timer? _realtimeDebounce;

  static const _realtimeTables = [
    'favorites',
    'serie_progress',
    'watch_profiles',
    'playlist_sources',
    'user_preferences',
  ];

  /// Écoute les changements Postgres (favoris, progression, profils, sources).
  ///
  /// Une chaîne par table : si une table n'est pas publiée côté Supabase
  /// (« Realtime is enabled »), seule celle-là échoue, les autres continuent.
  void startRealtime() {
    if (_channels.isNotEmpty || !isSignedIn) return;
    final db = Supabase.instance.client;
    for (final table in _realtimeTables) {
      final ch = db.channel('zen-$table-${repo.userId}');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _scheduleRefresh(),
      );
      ch.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError) {
          _realtimeTablesState[table] = false;
          debugPrint('realtime: table $table indisponible (${error ?? ''})');
        } else if (status == RealtimeSubscribeStatus.subscribed) {
          _realtimeTablesState[table] = true;
          debugPrint('realtime: table $table abonnée');
        }
      });
      _channels.add(ch);
    }
    // Realtime n'est pas publié côté serveur : on complète par un polling
    // léger pour retrouver la progression des autres appareils.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_loading && isSignedIn && mounted) {
        debugPrint('poll: ${DateTime.now().toIso8601String()}');
        refresh();
      }
    });
  }

  bool _mounted = true;
  bool get mounted => _mounted;

  @override
  void notifyListeners() {
    if (!_mounted) return;
    super.notifyListeners();
  }

  final Map<String, bool> _realtimeTablesState = {};

  /// Tables pour lesquelles le temps réel est actif (vide = repli polling).
  Map<String, bool> get realtimeTables => Map.unmodifiable(_realtimeTablesState);

  void _scheduleRefresh() {
    debugPrint('realtime: changement reçu');
    _realtimeDebounce?.cancel();
    _realtimeDebounce =
        Timer(const Duration(milliseconds: 900), () => refresh());
  }

  Future<void> stopRealtime() async {
    _realtimeDebounce?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    final db = Supabase.instance.client;
    final channels = List<RealtimeChannel>.from(_channels);
    _channels.clear();
    _realtimeTablesState.clear();
    for (final ch in channels) {
      await db.removeChannel(ch);
    }
  }

  bool isFavorite(String contentId, String contentType) => _favorites
      .any((f) => f.contentId == contentId && f.contentType == contentType);

  Future<void> toggleFavorite(String contentId, String contentType) async {
    final profile = _activeProfileId;
    if (profile == null) return;
    final db = Supabase.instance.client;
    if (isFavorite(contentId, contentType)) {
      await db
          .from('favorites')
          .delete()
          .eq('watch_profile_id', profile)
          .eq('content_id', contentId)
          .eq('content_type', contentType);
    } else {
      await db.from('favorites').insert({
        'watch_profile_id': profile,
        'content_id': contentId,
        'content_type': contentType,
        'sort_order': 0,
        'added_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    _favorites = await repo.favorites(profile);
    notifyListeners();
  }

  /// Crée ou met à jour une source dans `playlist_sources`.
  Future<void> saveSource({
    String? id,
    required String name,
    required String kind,
    String? host,
    String? url,
    String? username,
    String? password,
    String? epgUrl,
    int? color,
  }) async {
    final db = Supabase.instance.client;
    final row = {
      'name': name,
      'runtimeType': kind,
      'host': kind == 'xtream' ? host : null,
      'url': kind == 'm3u' ? url : null,
      'username': kind == 'xtream' ? username : null,
      'password': kind == 'xtream' ? password : null,
      'epg_url': epgUrl,
      if (color != null) 'color': color,
    };
    if (id == null) {
      await db.from('playlist_sources').insert({
        ...row,
        'user_id': repo.userId,
        'group_channels_categories': true,
      });
    } else {
      await db.from('playlist_sources').update(row).eq('id', id);
    }
    _sources = await repo.playlistSources();
    notifyListeners();
    // Une nouvelle source doit entrer dans l'index TMDB → noms.
    unawaited(CatalogIndex.instance.build(_sources));
  }

  /// Supprime une source (et donc chez tous les appareils du compte).
  Future<void> deleteSource(String id) async {
    await Supabase.instance.client
        .from('playlist_sources')
        .delete()
        .eq('id', id);
    _sources = await repo.playlistSources();
    notifyListeners();
  }

  /// Enregistre la position de lecture dans `serie_progress`.
  ///
  /// Le couple (watch_profile_id, serie_id) est unique côté serveur ; si la
  /// contrainte n'est pas exposée à PostgREST, repli sur update puis insert.
  Future<void> saveProgress({
    required String serieId,
    int season = 0,
    int episode = 0,
    required double positionSeconds,
    required double fraction,
    String runtimeType = 'serie',
    bool allEpisodesWatched = false,
  }) async {
    final profile = _activeProfileId;
    if (profile == null) return;
    final db = Supabase.instance.client;
    final row = {
      'watch_profile_id': profile,
      'serie_id': serieId,
      'season_number': season,
      'episode_number': episode,
      'watch_time': positionSeconds.round(),
      'watch_progress': double.parse(fraction.clamp(0, 1).toStringAsFixed(6)),
      'runtimeType': runtimeType,
      'all_episodes_watched': allEpisodesWatched,
      'last_watched': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await db
          .from('serie_progress')
          .upsert(row, onConflict: 'watch_profile_id,serie_id');
    } catch (_) {
      final updated = await db
          .from('serie_progress')
          .update(row)
          .eq('watch_profile_id', profile)
          .eq('serie_id', serieId)
          .select();
      if (updated.isEmpty) {
        await db.from('serie_progress').insert(row);
      }
    }
    _progress = await repo.progress(profile);
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    _error = null;
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signUp(String email, String password) async {
    _error = null;
    try {
      await Supabase.instance.client.auth
          .signUp(email: email.trim(), password: password);
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    await stopRealtime();
    await Supabase.instance.client.auth.signOut();
    _loaded = false;
    _profiles = const [];
    _sources = const [];
    _favorites = const [];
    _progress = const [];
    _preferences = null;
    _activeProfileId = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!isSignedIn) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final p = repo;
      _preferences = await p.preferences();
      _profiles = await p.watchProfiles();

      final prefProfile = _preferences?['preferred_watch_profile_id']?.toString();
      _activeProfileId = _profiles.any((e) => e.id == prefProfile)
          ? prefProfile
          : (_profiles.isNotEmpty ? _profiles.first.id : null);

      _sources = await p.playlistSources();
      await _loadProfileContent();
      _loaded = true;
      startRealtime();
      unawaited(CatalogIndex.instance.ensureLoaded());
      // En arrière-plan : index TMDB → noms du fournisseur, pour afficher des
      // titres dans Favoris/Reprendre sans dépendre de l'API TMDB.
      unawaited(Future<void>.delayed(
        const Duration(seconds: 10),
        () => CatalogIndex.instance.build(_sources),
      ));
    } catch (e) {
      _error = e is PostgrestException ? e.message : e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProfileContent() async {
    final id = _activeProfileId;
    if (id == null) {
      _favorites = const [];
      _progress = const [];
      return;
    }
    final p = repo;
    _favorites = await p.favorites(id);
    _progress = await p.progress(id);
  }

  Future<void> selectProfile(String id) async {
    _activeProfileId = id;
    notifyListeners();
    await _loadProfileContent();
    notifyListeners();
  }

  @override
  void dispose() {
    _mounted = false;
    _authSub.cancel();
    stopRealtime();
    _realtimeDebounce?.cancel();
    super.dispose();
  }
}
