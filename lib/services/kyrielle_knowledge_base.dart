/// One fact per chunk, app-specific behavior only — Kyrielle already
/// answers general hiking knowledge (safety basics, Leave No Trace, gear,
/// DENR permits) fine from Gemini's own training; an LLM has no way to know
/// this app's own rules unless we hand them over.
///
/// Bump [kyrielleKnowledgeBaseVersion] whenever this list — or
/// kyrielle_safety_manual.dart's — changes, so KyrielleRagService.dart knows
/// its cached embeddings are stale and recomputes them.
const int kyrielleKnowledgeBaseVersion = 3;

class KyrielleKnowledgeChunk {
  const KyrielleKnowledgeChunk({required this.id, required this.text});

  final String id;
  final String text;
}

const List<KyrielleKnowledgeChunk> kyrielleKnowledgeBase = [
  KyrielleKnowledgeChunk(
    id: 'hike_room_create',
    text:
        'To make or create a Hike Room in Agakbay, you must be an approved, '
        'verified Tour Guide. Open Explore, search for a mountain, select a '
        'mapped trail route, then tap Create Hike Room. A route with at least '
        'two mapped points is required. Agakbay creates the room and a '
        'six-digit room code; share that code with hikers so they can join. '
        'A Tour Guide can have only one active room at a time.',
  ),
  KyrielleKnowledgeChunk(
    id: 'hike_room_join',
    text:
        'To join a Hike Room in Agakbay, sign in with a Hiker account, open '
        'Profile, choose Hike SOS Room, enter the six-digit code supplied '
        'by the Tour Guide, and tap Join Room. You can join only a room that '
        'is waiting for hikers, and a hiker can belong to only one active '
        'room at a time. Ask the Tour Guide for the code if you do not have it.',
  ),
  KyrielleKnowledgeChunk(
    id: 'hike_room_manage',
    text:
        'In a Hike Room, the Tour Guide can share or copy the room code, see '
        'participants, and start the hike session when the group is ready. '
        'When the session is active, participants can start Hiking Mode and '
        'send an SOS to the Tour Guide. The Tour Guide can end the room; '
        'ending it removes participants from the active room. A hiker can '
        'leave a room from its screen.',
  ),
  KyrielleKnowledgeChunk(
    id: 'sos_mechanism',
    text:
        'Agakbay\'s SOS works by relaying the alert from the hiker\'s phone, '
        'over Bluetooth, to a paired Heltec LoRa device, which forwards it to '
        'the Tour Guide\'s device — this works even with zero cellular signal.',
  ),
  KyrielleKnowledgeChunk(
    id: 'sos_cooldown',
    text:
        'There is a 30-second cooldown per user between SOS sends, to '
        'prevent accidental spamming of the alert.',
  ),
  KyrielleKnowledgeChunk(
    id: 'room_limits',
    text:
        'Each Tour Guide can only have one active Hike Room at a time, and '
        'each hiker can only be in one active Hike Room at a time.',
  ),
  KyrielleKnowledgeChunk(
    id: 'become_tour_guide',
    text:
        'Every new Agakbay account starts as a Hiker — there is no option to '
        'choose "Tour Guide" at signup. To become a Tour Guide, a hiker '
        'submits an "Apply as Tour Guide" application from their Profile '
        'screen, including a government ID and a certificate photo. An '
        'admin reviews it and either approves or rejects it — the account '
        'only becomes a verified Tour Guide once approved.',
  ),
  KyrielleKnowledgeChunk(
    id: 'tour_guide_application_rejected',
    text:
        'If a Tour Guide application is rejected, the applicant must wait 7 '
        'days from the rejection date before they can reapply.',
  ),
  KyrielleKnowledgeChunk(
    id: 'why_cant_create_room_yet',
    text:
        'A Hiker cannot create a Hike Room, and an unverified Tour Guide '
        'applicant cannot either — Hike Room creation only unlocks after an '
        'admin has approved the Tour Guide application.',
  ),
  KyrielleKnowledgeChunk(
    id: 'schedule_hike',
    text:
        'To schedule a hike in Agakbay, use the calendar icon to open My '
        'Scheduled Hikes, then pick a mountain and a date. Agakbay '
        'automatically generates a packing checklist based on that trail\'s '
        'difficulty and elevation.',
  ),
  KyrielleKnowledgeChunk(
    id: 'edit_packing_checklist',
    text:
        'The packing checklist for a scheduled hike is fully editable — '
        'items can be added or removed, including the ones Agakbay '
        'auto-generated, not just custom-added ones.',
  ),
  KyrielleKnowledgeChunk(
    id: 'submit_trail',
    text:
        'After recording a GPS hike, Agakbay offers the option to submit '
        'that route as a new trail. If there is no signal, the submission '
        'is saved on the phone and automatically synced once back online. '
        'An admin then reviews the submission on the Trail Verification '
        'page before it is published — only after approval does it appear '
        'as an official route and notify other hikers who\'ve done that '
        'mountain before.',
  ),
  KyrielleKnowledgeChunk(
    id: 'offline_support',
    text:
        'Agakbay\'s GPS tracking, hike recording, and trail submission all '
        'work fully offline with no signal, and sync automatically once the '
        'phone reconnects to the internet.',
  ),
  KyrielleKnowledgeChunk(
    id: 'weather_source',
    text:
        'Weather information in Agakbay comes from the live Google Weather '
        'API, fetched through a Cloud Function and cached briefly — it is '
        'not static or hardcoded data.',
  ),
];
