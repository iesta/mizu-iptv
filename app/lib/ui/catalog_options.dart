/// Choix de tri partagés par le catalogue (films/séries) et « Reprendre ».
const catalogSortOptions = <({String value, String label})>[
  (value: 'recent', label: 'Ajout récent'),
  (value: 'oldest', label: 'Ajout ancien'),
  (value: 'name_asc', label: 'Nom A–Z'),
  (value: 'name_desc', label: 'Nom Z–A'),
  (value: 'rating_desc', label: 'Note + (meilleure)'),
  (value: 'rating_asc', label: 'Note - (plus basse)'),
];

/// Mêmes valeurs, libellés adaptés à la reprise (tri par dernière lecture).
const continueSortOptions = <({String value, String label})>[
  (value: 'recent', label: 'Plus récent'),
  (value: 'oldest', label: 'Plus ancien'),
  (value: 'name_asc', label: 'Nom A–Z'),
  (value: 'name_desc', label: 'Nom Z–A'),
  (value: 'rating_desc', label: 'Note +'),
  (value: 'rating_asc', label: 'Note -'),
];
