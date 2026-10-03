// Kaduna State electoral geography.
// Senatorial district codes and names align with INEC constituency references.
// LGA memberships use the slugs in [kadunaLgaSlugs].

const kadunaStateId = 'KD';
const kadunaStateName = 'Kaduna';

// INEC delimitation totals for Kaduna State.
const kadunaLgaCount = 23;
const kadunaWardCount = 255;
const kadunaPollingUnitCount = 8012;

class SenatorialDistrictSeed {
  const SenatorialDistrictSeed({
    required this.code,
    required this.name,
    required this.lgaSlugs,
  });

  final String code;
  final String name;
  final List<String> lgaSlugs;
}

const List<SenatorialDistrictSeed> kadunaSenatorialDistricts = [
  SenatorialDistrictSeed(
    code: 'SD/052/KD',
    name: 'Kaduna North',
    lgaSlugs: ['ikara', 'kubau', 'kudan', 'lere', 'makarfi', 'sabon-gari', 'soba', 'zaria'],
  ),
  SenatorialDistrictSeed(
    code: 'SD/053/KD',
    name: 'Kaduna Central',
    lgaSlugs: ['birnin-gwari', 'chikun', 'giwa', 'igabi', 'kaduna-north', 'kaduna-south', 'kajuru'],
  ),
  SenatorialDistrictSeed(
    code: 'SD/054/KD',
    name: 'Kaduna South',
    lgaSlugs: ['jaba', 'jema\'a', 'kachia', 'kagarko', 'kaura', 'kauru', 'sanga', 'zangon-kataf'],
  ),
];

const List<String> kadunaLgaSlugs = [
  'birnin-gwari', 'chikun', 'giwa', 'igabi', 'ikara', 'jaba', 'jema\'a', 'kachia',
  'kaduna-north', 'kaduna-south', 'kagarko', 'kajuru', 'kaura', 'kauru', 'kubau',
  'kudan', 'lere', 'makarfi', 'sabon-gari', 'sanga', 'soba', 'zangon-kataf', 'zaria',
];

const Map<String, String> _lgaDisplayOverrides = {
  'jema\'a': 'Jema\'a',
};

String kadunaLgaDisplayName(String slug) {
  final override = _lgaDisplayOverrides[slug];
  if (override != null) return override;
  return slug
      .split('-')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
