/// Builds a packing list tailored to a specific mountain. Pure and
/// offline — driven entirely by catalog metadata (difficulty, elevation,
/// trail types, features), no network calls.
///
/// Ordered so the mountain-specific advice comes first and the "always
/// true" essentials come last — a short preview (e.g. `take(3)`) should
/// read as advice, not a generic reminder to bring water.
List<String> buildPackingList({
  required String difficulty,
  int elevationMasl = 0,
  List<String> trailTypes = const [],
  List<String> features = const [],
}) {
  final normalizedDifficulty = difficulty.toLowerCase();
  final normalizedTrailTypes = trailTypes.map((t) => t.toLowerCase()).toSet();
  final normalizedFeatures = features.map((f) => f.toLowerCase()).toSet();

  final items = <String>[];

  if (normalizedTrailTypes.contains('overnight')) {
    items.addAll([
      'Tent or bivy (confirm with your group who is carrying shared gear)',
      'Sleeping bag rated for cold nights',
      'Sleeping mat',
      'Extra food for the additional day',
    ]);
  }

  if (normalizedTrailTypes.contains('technical')) {
    items.add(
      'Gloves, and check with your guide on rope/technical gear needs',
    );
  }

  if (elevationMasl >= 2500 || normalizedFeatures.contains('sunrise-viewpoint')) {
    items.addAll([
      'Insulating jacket or thermal layer for the cold summit push',
      'Beanie and gloves',
    ]);
  }

  if (normalizedFeatures.any((f) => f.contains('forest'))) {
    items.add('Gaiters or trekking poles for muddy, slippery sections');
  }

  if (normalizedFeatures.contains('waterfall') ||
      normalizedFeatures.contains('lake') ||
      normalizedFeatures.contains('lake-view')) {
    items.add('Swimwear or a dry bag if you plan to take a dip');
  }

  if (normalizedFeatures.contains('wildlife-sanctuary')) {
    items.add(
      'Confirm guide/permit requirements for this protected area in advance',
    );
  }

  if (normalizedDifficulty == 'hard') {
    items.addAll([
      'Trekking poles',
      'Sturdy ankle-support hiking boots',
    ]);
  } else if (normalizedDifficulty == 'moderate') {
    items.add('Sturdy hiking shoes');
  } else {
    items.add('Comfortable, broken-in walking shoes');
  }

  items.addAll([
    'Water (at least 2-3L)',
    'Trail food and snacks',
    'First-aid kit',
    'Headlamp or flashlight with spare batteries',
    'Fully charged phone and a power bank',
  ]);

  return items;
}
