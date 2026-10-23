import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class M3uChannel {
  M3uChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.tvgId,
  });

  final String name;
  final String url;
  final String? logo;
  final String? group;
  final String? tvgId;
}

/// Analyse une playlist M3U/M3U8 : `#EXTINF` + URL sur la ligne suivante.
List<M3uChannel> parseM3u(String content) {
  final channels = <M3uChannel>[];
  final lines = const LineSplitter().convert(content);
  Map<String, String> attrs = {};
  String? pendingName;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTINF')) {
      attrs = _attributes(line);
      final comma = line.lastIndexOf(',');
      pendingName = comma >= 0 ? line.substring(comma + 1).trim() : null;
      continue;
    }
    if (line.startsWith('#')) continue;
    if (pendingName == null) continue;

    channels.add(M3uChannel(
      name: pendingName.isEmpty ? line : pendingName,
      url: line,
      logo: attrs['tvg-logo'],
      group: attrs['group-title'],
      tvgId: attrs['tvg-id'],
    ));
    pendingName = null;
  }
  return channels;
}

Map<String, String> _attributes(String line) {
  final out = <String, String>{};
  final re = RegExp(r'([a-zA-Z0-9-]+)="([^"]*)"');
  for (final m in re.allMatches(line)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

Future<List<M3uChannel>> loadM3u(String url, {String? userAgent}) async {
  final res = await http.get(
    Uri.parse(url),
    headers: {
      if (userAgent != null && userAgent.isNotEmpty) 'User-Agent': userAgent,
    },
  ).timeout(const Duration(seconds: 45));
  if (res.statusCode != 200) {
    throw Exception('HTTP ${res.statusCode} sur la playlist M3U');
  }
  return compute(parseM3u, utf8.decode(res.bodyBytes, allowMalformed: true));
}
