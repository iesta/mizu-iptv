import 'package:flutter/material.dart';

/// Sections du catalogue Xtream et leur présentation.
///
/// Les clés (`live`, `vod`, `serie`) sont celles de
/// `MizuConfig.sectionOrder` ; leur ordre détermine les onglets du navigateur
/// de source.
class LibrarySection {
  const LibrarySection._();

  static const List<String> keys = ['live', 'vod', 'serie'];

  static String label(String key) => switch (key) {
        'vod' => 'Films',
        'serie' => 'Séries',
        _ => 'Live TV',
      };

  static IconData icon(String key) => switch (key) {
        'vod' => Icons.movie_outlined,
        'serie' => Icons.video_library_outlined,
        _ => Icons.live_tv_outlined,
      };
}
