import 'package:flutter_test/flutter_test.dart';
import 'package:mizu_iptv/data/m3u_playlist.dart';

void main() {
  test('parse une playlist M3U avec attributs', () {
    const content = '''
#EXTM3U
#EXTINF:-1 tvg-id="france24.fr" tvg-logo="http://x/logo.png" group-title="News",France 24
http://stream/france24.m3u8
#EXTINF:-1,Chaîne sans attributs
http://stream/autre.ts
''';
    final channels = parseM3u(content);
    expect(channels, hasLength(2));
    expect(channels.first.name, 'France 24');
    expect(channels.first.url, 'http://stream/france24.m3u8');
    expect(channels.first.group, 'News');
    expect(channels.first.logo, 'http://x/logo.png');
    expect(channels.last.name, 'Chaîne sans attributs');
  });

  test('ignore les lignes hors EXTINF', () {
    const content = 'http://orphelin\n#EXTINF:-1,Ok\nhttp://ok\n';
    final channels = parseM3u(content);
    expect(channels.map((c) => c.url), ['http://ok']);
  });
}
