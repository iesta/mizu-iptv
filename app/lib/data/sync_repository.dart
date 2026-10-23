import 'package:supabase_flutter/supabase_flutter.dart';

import '../mizu_config.dart';
import 'models.dart';

/// Accès aux tables de synchronisation du compte Zen.
///
/// Aucune écriture n'est faite ici pour l'instant : uniquement de la lecture,
/// pour valider le protocole avant de coder la synchro bidirectionnelle.
class SyncRepository {
  SyncRepository(this._db);

  final SupabaseClient _db;

  String? get userId => _db.auth.currentUser?.id;

  Future<List<WatchProfile>> watchProfiles() async {
    final rows = await _db
        .from(MizuConfig.tWatchProfiles)
        .select('*')
        .eq('user_id', userId!)
        .order('name');
    return rows.map(WatchProfile.new).toList();
  }

  Future<Map<String, dynamic>?> preferences() async {
    final rows =
        await _db.from(MizuConfig.tUserPreferences).select('*').eq('user_id', userId!).limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<PlaylistSource>> playlistSources() async {
    final rows =
        await _db.from(MizuConfig.tPlaylistSources).select('*').eq('user_id', userId!).order('name');
    return rows.map(PlaylistSource.new).toList();
  }

  Future<List<FavoriteItem>> favorites(String profileId) async {
    final rows = await _db
        .from(MizuConfig.tFavorites)
        .select('*')
        .eq('watch_profile_id', profileId)
        .order('sort_order', ascending: true);
    return rows.map(FavoriteItem.new).toList();
  }

  Future<List<ProgressItem>> progress(String profileId) async {
    final rows = await _db
        .from(MizuConfig.tSerieProgress)
        .select('*')
        .eq('watch_profile_id', profileId)
        .order('last_watched', ascending: false);
    return rows.map(ProgressItem.new).toList();
  }

  Future<List<Map<String, dynamic>>> maskedCategories(String profileId) async {
    return await _db
        .from(MizuConfig.tMaskedCategories)
        .select('*')
        .eq('watch_profile_id', profileId);
  }

  Future<Map<String, dynamic>> rawDump(String? profileId) async {
    final out = <String, dynamic>{
      'user': {
        'id': userId,
        'email': _db.auth.currentUser?.email,
      },
      'watch_profiles': await watchProfiles().then((v) => v.map((e) => e.raw).toList()),
      'user_preferences': await preferences(),
      'playlist_sources': await playlistSources().then((v) => v.map((e) => e.raw).toList()),
      'favorites': profileId == null
          ? null
          : await favorites(profileId).then((v) => v.map((e) => e.raw).toList()),
      'serie_progress': profileId == null
          ? null
          : await progress(profileId).then((v) => v.map((e) => e.raw).toList()),
      'masked_categories': profileId == null ? null : await maskedCategories(profileId),
    };
    return out;
  }
}
