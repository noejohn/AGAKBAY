import 'package:tunga/services/gemini_client.dart';

/// Instant, offline reactions to common items a hiker might manually add to
/// their packing list — matched by substring against the lowercased item
/// text. Mirrors buildPackingList's philosophy (agak_packing_list.dart):
/// curated and free before anything network-dependent.
const Map<String, String> _knownItemReactions = {
  'flashlight': "Good call — that's a lifesaver for getting back after dark!",
  'headlamp': 'Smart pick, keeps your hands free on tricky terrain after dark!',
  'rope': 'Just double-check with your guide on rope/technical gear needs for this trail.',
  'map': 'Always a good backup if your phone runs out of battery!',
  'compass': 'Old-school but reliable — great backup navigation.',
  'whistle': 'Small but could really help rescuers find you in an emergency.',
  'poncho': 'Smart — mountain weather can turn fast.',
  'raincoat': 'Smart — mountain weather can turn fast.',
  'umbrella': 'Smart — mountain weather can turn fast.',
  'sunscreen': "Don't forget to reapply — UV is stronger at higher elevation!",
  'sunblock': "Don't forget to reapply — UV is stronger at higher elevation!",
  'gloves': "Good thinking, it's colder up there than it looks.",
  'socks': 'Extra socks are always a good idea for long hikes.',
  'medicine': 'Smart to bring any personal medication you need.',
  'medication': 'Smart to bring any personal medication you need.',
  'power bank': "Nice — you'll want the extra battery for photos and emergencies!",
  'powerbank': "Nice — you'll want the extra battery for photos and emergencies!",
  'battery': "Nice — you'll want the extra battery for photos and emergencies!",
  'knife': 'Handy for all sorts of trail situations — just pack it safely.',
  'tent': 'Good call if you might end up camping overnight.',
  'insect repellent': 'Smart — you\'ll thank yourself on forested trails.',
  'bug spray': "Smart — you'll thank yourself on forested trails.",
};

String? localReactionForPackingItem(String item) {
  final normalized = item.toLowerCase();
  for (final entry in _knownItemReactions.entries) {
    if (normalized.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

/// Generic line used when neither the local dictionary nor Gemini can say
/// anything more specific — still warm, never a dead end.
const String genericItemReaction = "Good thinking — every bit of prep helps!";

/// Full reaction pipeline for a user-added packing item: instant local
/// dictionary first, then Gemini for anything unrecognized, then the
/// generic fallback if that's unavailable too. Never throws — always
/// returns a usable message.
Future<String> reactionForPackingItem(String item) async {
  final local = localReactionForPackingItem(item);
  if (local != null) {
    return local;
  }

  final apiKey = await loadGeminiApiKey();
  final aiReply = await fetchGeminiResponse(
    apiKey: apiKey,
    systemInstruction:
        "You are Kyrielle, a friendly, encouraging hiking companion bird "
        'mascot inside a Philippine hiking safety app. The user just added '
        'an item to their packing list for an upcoming hike. React in ONE '
        'short, warm sentence (max ~20 words) — no greeting, no "As an AI" '
        'disclaimers, just the reaction, as if speaking directly to a '
        'friend.',
    prompt: 'The user added: "$item"',
    maxOutputTokens: 60,
  );
  if (aiReply.isNotEmpty) {
    return aiReply;
  }

  return genericItemReaction;
}
