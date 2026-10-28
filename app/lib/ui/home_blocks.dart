import 'package:flutter/material.dart';

/// Blocs de l'onglet Accueil. L'ordre et l'activation sont gérés par
/// `MizuConfig.homeBlockOrder` / `homeBlocksDisabled`.
class HomeBlockDef {
  const HomeBlockDef(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const homeBlockDefs = <String, HomeBlockDef>{
  'latestMovies': HomeBlockDef(
      'latestMovies', 'Dernières sorties — Films', Icons.movie_outlined),
  'latestSeries': HomeBlockDef(
      'latestSeries', 'Dernières sorties — Séries', Icons.video_library_outlined),
  'trending':
      HomeBlockDef('trending', 'Tendances TMDB', Icons.trending_up),
  'resumeMovies': HomeBlockDef(
      'resumeMovies', 'Reprendre — Films', Icons.play_circle_outline),
  'resumeSeries': HomeBlockDef(
      'resumeSeries', 'Reprendre — Séries', Icons.play_circle_outline),
  'favoriteMovies': HomeBlockDef(
      'favoriteMovies', 'Favoris — Films', Icons.favorite_border),
  'favoriteSeries': HomeBlockDef(
      'favoriteSeries', 'Favoris — Séries', Icons.favorite_border),
  'favoriteChannels': HomeBlockDef(
      'favoriteChannels', 'Favoris — TV', Icons.live_tv_outlined),
};

HomeBlockDef homeBlockDef(String key) =>
    homeBlockDefs[key] ?? HomeBlockDef(key, key, Icons.widgets_outlined);
