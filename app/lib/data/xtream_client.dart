import 'dart:convert';

import 'package:http/http.dart' as http;

import '../mizu_config.dart';

/// Petit client de l'API Xtream Codes (`player_api.php`).
///
/// C'est le format standard côté fournisseur IPTV : rien de spécifique à Zen.
class XtreamClient {
  XtreamClient({
    required String baseUrl,
    required this.username,
    required this.password,
    this.userAgent,
    http.Client? httpClient,
  })  : baseUrl = _normalize(baseUrl),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final String? userAgent;
  final http.Client _http;

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri _endpoint([Map<String, String> extra = const {}]) {
    return Uri.parse('$baseUrl/player_api.php').replace(queryParameters: {
      'username': username,
      'password': password,
      ...extra,
    });
  }

  Map<String, String> get _headers => {
        'User-Agent': (userAgent != null && userAgent!.isNotEmpty)
            ? userAgent!
            : MizuConfig.userAgent,
      };

  Future<dynamic> _get([Map<String, String> extra = const {}]) async {
    final res = await _http
        .get(_endpoint(extra), headers: _headers)
        .timeout(const Duration(seconds: 25));
    if (res.statusCode >= 400) {
      throw XtreamException('HTTP ${res.statusCode} sur ${_endpoint(extra)}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw XtreamException('Réponse non JSON (source M3U ou portail fermé ?)');
    }
  }

  Future<Map<String, dynamic>> accountInfo() async {
    final data = await _get();
    if (data is! Map<String, dynamic>) {
      throw XtreamException('Réponse inattendue de player_api.php');
    }
    return data;
  }

  /// Un panneau expiré/bloqué renvoie un objet `user_info` au lieu d'une
  /// liste : on le transforme en erreur explicite plutôt qu'en cast fatal.
  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['user_info'] is Map) {
      final user = data['user_info'] as Map;
      final status = user['status']?.toString() ?? 'inconnu';
      final exp = int.tryParse(user['exp_date']?.toString() ?? '');
      final when = exp == null
          ? ''
          : ' (expire le ${DateTime.fromMillisecondsSinceEpoch(exp * 1000).toIso8601String().substring(0, 10)})';
      throw XtreamException('Compte $status$when — source indisponible');
    }
    if (data == null) return const [];
    throw XtreamException('Réponse inattendue de player_api.php');
  }

  Future<List<dynamic>> liveCategories() async =>
      _asList(await _get({'action': 'get_live_categories'}));

  Future<List<dynamic>> liveStreams({String? categoryId}) async =>
      _asList(await _get({
        'action': 'get_live_streams',
        if (categoryId != null) 'category_id': categoryId,
      }));

  Future<List<dynamic>> vodCategories() async =>
      _asList(await _get({'action': 'get_vod_categories'}));

  Future<List<dynamic>> vodStreams({String? categoryId}) async =>
      _asList(await _get({
        'action': 'get_vod_streams',
        if (categoryId != null) 'category_id': categoryId,
      }));

  Future<List<dynamic>> seriesCategories() async =>
      _asList(await _get({'action': 'get_series_categories'}));

  Future<List<dynamic>> series({String? categoryId}) async =>
      _asList(await _get({
        'action': 'get_series',
        if (categoryId != null) 'category_id': categoryId,
      }));

  Future<Map<String, dynamic>> seriesInfo(int seriesId) async {
    final data = await _get({'action': 'get_series_info', 'series_id': '$seriesId'});
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> vodInfo(int vodId) async {
    final data = await _get({'action': 'get_vod_info', 'vod_id': '$vodId'});
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  String liveUrl(int streamId, {String ext = 'ts'}) =>
      '$baseUrl/live/$username/$password/$streamId.$ext';

  String vodUrl(int streamId, {String ext = 'mp4'}) =>
      '$baseUrl/movie/$username/$password/$streamId.$ext';

  String seriesUrl(int episodeId, {String ext = 'mp4'}) =>
      '$baseUrl/series/$username/$password/$episodeId.$ext';

  void close() => _http.close();
}

class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}
