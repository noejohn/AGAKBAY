import 'kyrielle_knowledge_base.dart';

/// DENR Protected Area Guidelines and Mountain Safety (Philippines), with a
/// Mt. Apo Natural Park quick reference — "Hiking Safety Manual" PDF
/// (Doc ID: HSM-PH, Rev. 30 September 2026), user-supplied and pre-chunked
/// by the document's own [HSM-PH-xx] section headings, one chunk per
/// section/FAQ item as the document itself recommends for RAG ingestion.
///
/// Each chunk keeps its "Basis" tag inline (DENR/LAW vs BEST PRACTICE) so a
/// retrieved answer can honestly convey whether something is a binding rule
/// or general mountaineering guidance — rules, fees and closures are set
/// per-mountain by each PAMB/LGU and change often, so Kyrielle should still
/// point hikers to the PAMO/DENR/LGU tourism office to confirm current
/// requirements rather than state these as guaranteed-current facts.
const List<KyrielleKnowledgeChunk> kyrielleSafetyManualChunks = [
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-01',
    text:
        '[Basis: DENR/LAW] Who regulates hiking in Philippine protected areas: '
        'the DENR, through its Biodiversity Management Bureau, under RA 11038 '
        '(E-NIPAS Act of 2018). Each protected area is governed by a Protected '
        'Area Management Board (PAMB) — a multi-sector body with DENR, '
        'Congress, LGU, and private-sector representatives — which decides on '
        'trail openings, closures, visitor limits, and trekking policies. '
        'Day-to-day operations are run by the Protected Area Management '
        'Office (PAMO), headed by the Protected Area Superintendent (PASu). '
        'The rules on a specific mountain come from that mountain\'s PAMB '
        'resolutions, enforced by the PAMO with the host LGU and DENR '
        'regional/provincial/community offices.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-02',
    text:
        '[Basis: DENR/LAW] Key Philippine hiking laws: RA 7586 (NIPAS Act of '
        '1992, created the protected areas system), RA 11038 (E-NIPAS Act of '
        '2018, amends RA 7586, widened prohibited acts and raised penalties), '
        'RA 9237 (Mt. Apo Protected Area Act of 2003, the specific law for '
        'Mt. Apo), DAO 2013-19 (ecotourism planning guidelines), DOT '
        'Memorandum Circular 99-15 (mountain guide accreditation), and local '
        'ordinances like Davao City Ordinance No. 0675-21 (2021, requires '
        'Watershed Management Council approval for trekking in '
        'environmentally critical areas). When a PAMB resolution and a '
        'general guideline differ, follow the stricter, more specific rule '
        'for that mountain.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-03',
    text:
        '[Basis: DENR/LAW] Prohibited acts inside Philippine protected areas '
        'under RA 11038: littering or damaging trails; causing forest fires '
        '(including unattended campfires, kaingin/slash-and-burn); '
        'collecting, possessing, or transporting timber, plants, wildlife, or '
        'their by-products (even "souvenir" orchids, rocks, or animals); '
        'hunting or disturbing wildlife; building structures or running a '
        'business without PAMB/DENR clearance; possessing explosives; and '
        'dumping waste, sewage, or toxic substances. Violators face fines and '
        'imprisonment, and convicted officials are perpetually disqualified '
        'from public office.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-04',
    text:
        '[Basis: DENR/LAW] Penalties under RA 11038 depend on the offense: '
        'fines up to ₱5,000,000 and imprisonment up to 12 years across the '
        'law. Example: unauthorized occupation or construction inside a '
        'protected area carries ₱200,000–₱1,000,000 and/or 1–6 years. '
        'Individual protected areas also set their own administrative fines '
        '— e.g. two foreign hikers fined ₱2,000 each in March 2023 for '
        'climbing Mt. Apo\'s Kidapawan (Mandangan) trail without a permit. '
        'DENR has stressed that not knowing the rule is no excuse — always '
        'secure the required permit.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-05',
    text:
        '[Basis: DENR/LAW] Climbing permits, registration and fees: most '
        'mountains in protected areas require a climbing/trekking permit '
        'before entry. Typical requirements: advance registration and paying '
        'trekking/entrance fees (an exit fee may apply if traversing to a '
        'different trail), hiring an accredited local guide (and porters if '
        'required), attending a pre-climb orientation, following only '
        'PAMB-approved trail maps, and valid ID (sometimes a medical/fitness '
        'waiver). Fees vary by resolution and season (peak season, e.g. Holy '
        'Week, is priced higher) — confirm current rates with the host LGU '
        'tourism office before the trip.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-06',
    text:
        '[Basis: DENR/LAW] Carrying capacity and visitor limits: PAMBs cap '
        'how many people may enter a trail per day to protect the ecosystem '
        'and hiker safety. Mt. Apo allowed only 50 trekkers per trail per day '
        'when it reopened in April 2017 (halved to 25 during COVID-19). '
        'Peak-holiday caps have also been applied (e.g. a 1,000-climber limit '
        'for Holy Week 2016). Book early, expect slots to fill on long '
        'weekends, and never join an "unofficial" group promising entry '
        'outside the quota — that is climbing without a permit.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-07',
    text:
        '[Basis: DENR/LAW] Seasonal and emergency closures: only the PAMB '
        'can officially close a protected area, but LGUs may issue their own '
        'advisories or close trails they manage for safety. Mt. Apo has an '
        'annual rest period from 1 June to 31 August every year (no '
        'trekking/camping, both Davao Region and SOCCSKSARGEN sides), plus '
        'fire-risk closures during El Niño dry spells, rehabilitation '
        'closures after fires (all Mt. Apo trails were closed from the March '
        '2016 fire until April 2017), geohazard closures after earthquakes, '
        'and watershed closures. Climbing during a closure is a violation — '
        'always check for closures before traveling.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-08',
    text:
        '[Basis: DENR/LAW] Fire rules: fire is the single biggest '
        'hiker-caused threat to Philippine mountains (the March 2016 Mt. Apo '
        'fire, believed started from an unattended campfire, burned for '
        'about three weeks). Rules: no campfires or burning of trash/debris; '
        'no firewood, logs, or charcoal for cooking — use a portable stove '
        'only, never left unattended; no firecrackers/pyrotechnics; no '
        'smoking at the peak and restricted smoking elsewhere (carry out '
        'every cigarette butt); obey fire-season closures. If you see a '
        'fire: move upslope or crosswind (never uphill ahead of it), alert '
        'your guide/camp manager/PAMO, and call 911.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-09',
    text:
        '[Basis: DENR/LAW + BEST PRACTICE] Waste and sanitation: littering '
        'is a prohibited act under RA 11038 and a stated reason behind '
        'Mt. Apo\'s annual closure and Mt. Pulag\'s 2025 campsite closure. '
        'Carry out everything you bring in (food scraps, wrappers, wet '
        'wipes, sanitary items, cigarette butts); some trails inspect bags '
        'at registration/exit. Use designated toilets; if none, go at least '
        '60 m from water/trails/camps and bury waste in a 15–20 cm cat hole '
        '(pack out toilet paper) — this 60 m/cat-hole figure is standard '
        'Leave No Trace practice, not a DENR numeric rule. Never put soap '
        '(even "biodegradable") directly into streams or crater lakes, and '
        'never contaminate watershed areas.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-10',
    text:
        '[Basis: DENR/LAW] Vandalism, noise, alcohol and prohibited '
        'substances: DENR-Davao teams have documented graffiti, loud noise, '
        'liquor, and drug traces on Mt. Apo — grounds for fines, charges, or '
        'closures. Rules: no writing/painting/carving on rocks, trees, '
        'signs, or shelters; keep noise low (no loudspeakers at camp); '
        'alcohol is restricted on Mt. Apo including at the peak; illegal '
        'drugs are prohibited everywhere and referred to law enforcement; no '
        'cultivation, clearing, or collecting inside the Strict Protection '
        'Zone.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-11',
    text:
        '[Basis: DENR/LAW] Camping rules and peak restrictions: camp only in '
        'PAMB-designated campsites (for Mt. Apo, sites like Lake Venado or '
        'Camp Gudi-Gudi depending on trail). Mt. Apo has a no-camping policy '
        'at the peak area — under 2017 reopening conditions, trekkers may '
        'only visit the summit for photos and must leave before nightfall; '
        'sleeping at the peak at night is prohibited. Pitch tents only in '
        'marked areas, inform the host village/camp manager when your climb '
        'starts and ends, follow camp managers\' instructions, and leave the '
        'campsite cleaner than you found it.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-12',
    text:
        '[Basis: DENR/LAW + BEST PRACTICE] Wildlife and plants: Mt. Apo '
        'Natural Park is an ASEAN Heritage Park and home to the critically '
        'endangered Philippine eagle. Rules: observe animals from a '
        'distance — never approach, chase, feed, or corner them; do not '
        'pick plants, orchids, pitcher plants, mosses, or take rocks/sulfur '
        'as souvenirs (collection is a prohibited act); store food securely; '
        'stay on the trail to avoid trampling vegetation; do not bring pets '
        'or introduce plants/seeds into the protected area.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-13',
    text:
        '[Basis: DENR/LAW] Respect for indigenous peoples and host '
        'communities: many Philippine mountains are ancestral domains — '
        'Mt. Apo (Apo Sandawa) is regarded as sacred, and its 2017 reopening '
        'was driven partly by indigenous and local communities who depend '
        'on guiding/portering for livelihood. Hire local accredited guides '
        'and porters and pay agreed fees; ask before photographing people, '
        'rituals, or sacred sites; respect local customs or offerings that '
        'may be required before a climb; businesses inside a protected area '
        'need PAMB/DENR/barangay/tourism-office (and sometimes NCIP) '
        'clearance.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-14',
    text:
        '[Basis: BEST PRACTICE, endorsed by DENR] The seven Leave No Trace '
        'principles: (1) Plan ahead and prepare — know rules, permits, '
        'weather, closures; (2) Travel and camp on durable surfaces — stay '
        'on established trails/campsites; (3) Dispose of waste properly — '
        'pack it in, pack it out; (4) Leave what you find — no collecting or '
        'vandalism; (5) Minimize campfire impacts — in Philippine protected '
        'areas this generally means no campfires, use a stove; (6) Respect '
        'wildlife — observe from a distance, never feed; (7) Be considerate '
        'of other visitors — keep noise down, yield on trails, share '
        'campsites courteously.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-15',
    text:
        '[Basis: DENR/LAW + BEST PRACTICE] Pre-climb planning checklist: '
        'confirm the trail is open (check DENR regional office, PAMO, LGU '
        'tourism office pages for closures); register and secure permits; '
        'book an accredited guide; check PAGASA forecasts, cyclone '
        'bulletins, El Niño/La Niña advisories, and PHIVOLCS advisories; '
        'choose a route matching the weakest group member\'s fitness; '
        'prepare an itinerary with a turnaround time and leave it with a '
        'trusted person not on the climb, including expected return time '
        'and who to call if overdue; know nearby emergency contacts (911, '
        'local MDRRMO/rescue, PAMO, LGU tourism office); pack essentials and '
        'check gear the day before.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-16',
    text:
        '[Basis: BEST PRACTICE] Essential gear list for every hike, even day '
        'hikes: navigation (trail map, phone with offline map/GPS track, '
        'power bank — a GPS app does not replace a guide or a permit), '
        'headlamp with spare batteries, rain protection (waterproof jacket, '
        'pack cover/dry bags), a warm insulating layer (summits above '
        '2,000 m like Mt. Apo at 2,954 m can drop near freezing at night), '
        'at least 2 litres of water for a day hike plus purification, trail '
        'food plus one extra emergency meal, a first-aid kit with personal '
        'medicines, whistle, emergency blanket, knife/multitool, sun '
        'protection, trash bags and trowel, a portable stove for overnight '
        'trips (no firewood), and sturdy trail shoes (gaiters/leech socks on '
        'wet forest trails).',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-17',
    text:
        '[Basis: BEST PRACTICE] Physical fitness and medical readiness: '
        'major climbs like Mt. Apo involve long days, steep ascents, and '
        'high elevation — train with regular cardio and stair/hill work for '
        'several weeks beforehand. People with heart disease, uncontrolled '
        'high blood pressure, asthma, diabetes, pregnancy, or recent injury '
        'should consult a doctor first. Declare medical conditions and '
        'allergies to your guide and team leader; sleep well and avoid '
        'alcohol the night before a climb.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-18',
    text:
        '[Basis: BEST PRACTICE + DENR/LAW] Group management and the role of '
        'the guide: accredited guides know approved trails, water points, '
        'hazards, and local rules, and many PAMBs require them. Keep the '
        'group together (experienced lead at front, sweeper at back, '
        'slowest hiker sets the pace); do regular headcounts especially at '
        'junctions and before descending; never let a member hike alone '
        '(use the buddy system); agree on whistle signals (one blast = '
        'where are you, three = emergency); respect the turnaround time — '
        'if not at the summit by the agreed time, go down; follow the '
        'guide\'s instructions and do not take shortcuts off the approved '
        'trail.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-19',
    text:
        '[Basis: BEST PRACTICE] Weather hazards — typhoons, heavy rain and '
        'lightning: the Philippines sees frequent tropical cyclones (mainly '
        'June–December) and heavy monsoon rain; trails are more dangerous in '
        'the rainy season since slope conditions change. Do not climb when '
        'a Tropical Cyclone Wind Signal or heavy-rainfall warning is in '
        'effect for the area. Rain triggers landslides/flash floods — slow '
        'down and use trekking poles. For lightning: get off summits, '
        'ridges, and open grassland before afternoon storms, avoid lone '
        'trees and metal, and if caught, crouch low on your pack with feet '
        'together and spread the group apart. Fog can disorient on open '
        'summits — stay on the marked trail together as a group.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-20',
    text:
        '[Basis: BEST PRACTICE] Heat illness and dehydration: low-elevation '
        'Philippine trails are hot and humid. Heat exhaustion signs: heavy '
        'sweating, weakness, dizziness, nausea, headache, cramps. Heat '
        'stroke signs (medical emergency): confusion, hot skin, collapse. '
        'Start early to avoid midday heat, drink regularly with '
        'electrolytes. For heat exhaustion: rest in shade, loosen clothing, '
        'cool with water/fanning, drink fluids. For suspected heat stroke: '
        'cool aggressively, do not give fluids if the person is confused, '
        'and call for evacuation (911) immediately.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-21',
    text:
        '[Basis: BEST PRACTICE] Cold exposure and hypothermia: even in the '
        'tropics, high summits get cold, especially wet and windy. '
        'Hypothermia signs: uncontrollable shivering, clumsiness, slurred '
        'speech, confusion, drowsiness. Stay dry (change out of wet clothes '
        'at camp, keep a dry set in a waterproof bag), eat/drink warm '
        'fluids, insulate from the ground. For a hypothermic hiker: get them '
        'out of wind/rain, replace wet clothing, wrap in a sleeping '
        'bag/emergency blanket, give warm sweet drinks if alert, and seek '
        'help if confused or no longer shivering.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-22',
    text:
        '[Basis: BEST PRACTICE] Altitude and volcanic hazards: Mt. Apo, the '
        'Philippines\' highest peak at 2,954 m, is a dormant stratovolcano '
        'with sulfur (solfataric) vents near the summit, notably the Sta. '
        'Cruz boulder face. Mild altitude symptoms (headache, nausea, poor '
        'sleep) are possible near the summit — ascend steadily, hydrate, and '
        'descend if symptoms worsen. Avoid lingering in sulfur fumes (move '
        'upwind; people with asthma take extra care). Boulder fields are '
        'unstable — test holds, keep three points of contact, and space out '
        'to avoid rockfall onto hikers below. Check PHIVOLCS bulletins '
        'before climbing active volcanoes and never enter permanent danger '
        'zones.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-23',
    text:
        '[Basis: BEST PRACTICE] Trail hazards — river crossings, falls, '
        'leeches, bites: for river crossings, cross only at the guide\'s '
        'chosen point, unbuckle your hip belt, face upstream, use a pole or '
        'linked arms; wait or turn back if water is above knee height and '
        'fast; never cross during flash floods. Most falls are slips on wet '
        'roots/mud/rocks — wear grippy shoes, use poles on descents, never '
        'run downhill. Leeches are common in wet forest — use leech socks, '
        'remove by sliding a fingernail under the sucker (don\'t pull). For '
        'snake bites: keep the person calm and still, immobilize the limb, '
        'remove rings/tight items, do not cut/suck the wound or apply a '
        'tourniquet, and evacuate to a hospital.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-24',
    text:
        '[Basis: BEST PRACTICE] First aid kit and common injuries: minimum '
        'group kit should have adhesive bandages, sterile gauze, elastic '
        'bandage, tape, blister dressings, antiseptic, tweezers, gloves, '
        'triangular bandage, pain/fever relievers, antihistamine, '
        'anti-diarrhea medicine, oral rehydration salts, personal '
        'prescription medicines, and an emergency blanket. Blisters: treat '
        'hot spots early with tape. Sprains: rest, immobilize, compress, '
        'elevate. Wounds: stop bleeding with direct pressure, clean, cover. '
        'Suspected fracture or head/spine injury: do not move the person '
        'unless in immediate danger — keep warm and call for rescue. At '
        'least one group member should have current first-aid training.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-25',
    text:
        '[Basis: BEST PRACTICE] If you get lost, use the STOP method: '
        'Stop (don\'t keep walking, stay where you are); Think (where were '
        'you last sure of your location?); Observe (check GPS/map, look for '
        'trail markers, listen for other hikers or water); Plan (retrace '
        'only if sure of the way back, otherwise stay put, stay visible, '
        'and signal). Signal with three whistle blasts, a light at night, '
        'and bright clothing. Call 911 or your guide if you have signal; '
        'send a text with GPS coordinates since SMS often works when calls '
        'don\'t. Never follow unknown streams down steep gullies — they '
        'often end at waterfalls or cliffs.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-26',
    text:
        '[Basis: BEST PRACTICE] Emergency response and rescue: make the '
        'scene safe, then assess the casualty (breathing, bleeding, '
        'consciousness); give first aid and keep them warm/sheltered; call '
        '911 and the guide/camp manager/PAMO, giving location (GPS '
        'coordinates or nearest campsite), number of casualties, nature of '
        'injuries, group size, and your contact number; if no signal, send '
        'two people for help with a written note of the details while the '
        'rest stay with the casualty; do not attempt risky self-evacuation '
        'of a suspected spinal injury; record times and condition changes '
        'for rescuers. Your itinerary contact should call for help if your '
        'group doesn\'t check in by the agreed time.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-27',
    text:
        '[Basis: BEST PRACTICE + DENR/LAW] Earthquakes, landslides and flash '
        'floods: Mindanao experiences frequent earthquakes, and LGUs have '
        'closed Mt. Apo trails after strong tremors due to landslide risk. '
        'During an earthquake on the trail: move away from steep '
        'slopes/cliffs/loose boulders, crouch and protect your head. '
        'Afterwards, watch for cracks, falling rocks, and debris flows. '
        'Landslide warning signs: new cracks, tilting trees, sudden muddy '
        'stream water, rumbling sounds — leave the area laterally, not '
        'downhill in its path. For flash floods: if a stream rises or turns '
        'muddy, move to high ground immediately and do not cross. Postpone '
        'climbs while tremors or heavy-rain advisories continue.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-28',
    text:
        '[Basis: DENR/LAW] Mt. Apo Natural Park at a glance: elevation '
        '2,954 m (9,692 ft), the highest peak in the Philippines, also '
        'called Apo Sandawa. Straddles Davao Region (Region XI) and '
        'SOCCSKSARGEN (Region XII), covering close to 66,000 hectares. '
        'Established as a park in 1936; governed by RA 9237 (2003) and '
        'RA 11038; declared an ASEAN Heritage Park in 2011; home to the '
        'Philippine eagle. Managed by the MANP Protected Area Management '
        'Board with Sub-PAMBs per province/region. Trail entry points '
        '(openness varies, confirm first): Kidapawan City, Makilala, and '
        'Magpet (Cotabato); Digos City, Sta. Cruz, and Bansalan (Davao del '
        'Sur); Brgy. Tamayong, Calinan (Davao City). Annual off-season: '
        '1 June to 31 August, no trekking or camping.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-29',
    text:
        '[Basis: DENR/LAW] Mt. Apo rules summary, based on the '
        'Unified/Common Trekking Policy and 2017 reopening conditions: '
        'secure a climbing permit and register at the official entry point '
        '(climbing without one is fined); hire an accredited guide; attend '
        'the pre-climb camp-management orientation; follow only '
        'PAMB-provided trail maps; inform the host village at the start of '
        'every climb; the summit is for visiting/photos only — leave before '
        'night, no camping or sleeping at the peak; no liquor or smoking at '
        'the peak, no illegal drugs anywhere; no campfires, burning debris, '
        'firecrackers, firewood, or charcoal cooking; pack out all trash, '
        'no vandalism, no collecting plants/wildlife; daily per-trail '
        'climber limits apply (historically 50/day); pay trekking fees '
        '(higher in peak season) and an exit fee if traversing.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-01',
    text:
        'Q: Can I climb Mt. Apo in July? A: No. Mt. Apo Natural Park has an '
        'annual off-season from 1 June to 31 August, during which trekking '
        'and camping are prohibited on all trails.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-02',
    text:
        'Q: Do I need a permit to hike in a protected area? A: Generally '
        'yes. Most PAMBs require registration and a climbing permit, often '
        'with an accredited guide and orientation. On Mt. Apo, climbing '
        'without a permit has been fined ₱2,000 per person.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-03',
    text:
        'Q: Can I make a campfire? A: No, in Mt. Apo and most Philippine '
        'protected areas. Campfires, burning debris, firecrackers, and '
        'cooking with firewood or charcoal are prohibited — use a portable '
        'stove. Causing forest fires is a prohibited act under RA 11038.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-04',
    text:
        'Q: Can I camp on the summit of Mt. Apo? A: No. Mt. Apo has a '
        'no-camping policy at the peak — visit, take photos, and leave '
        'before night.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-05',
    text:
        'Q: What are the penalties under the E-NIPAS Act? A: Depending on '
        'the offense, fines up to ₱5 million and imprisonment up to 12 '
        'years — e.g. unauthorized occupation or construction carries '
        '₱200,000–₱1,000,000 and/or 1–6 years.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-06',
    text:
        'Q: Who can close a mountain to hikers? A: Officially, the '
        'Protected Area Management Board (PAMB). LGUs can also issue '
        'advisories or close their own trails for safety.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-07',
    text:
        'Q: Can I take plants or rocks home? A: No. Collecting or '
        'transporting plants, wildlife, forest products, or their '
        'by-products is prohibited in protected areas.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-08',
    text:
        'Q: Why does Mt. Apo close during El Niño? A: Dry spells raise the '
        'risk of grass and forest fires — the 2016 fire burned about 115 '
        'hectares. The PAMB suspends trekking until PAGASA lifts its '
        'advisory or conditions improve.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-09',
    text:
        'Q: Is trekking allowed in Davao City watershed areas? A: Not '
        'without approval. Davao City\'s Watershed Management Council '
        'Resolution No. 21 (2021) prohibits trekking in watershed areas '
        'without prior approval.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-10',
    text:
        'Q: What should I do if I get lost? A: Use STOP — Stop, Think, '
        'Observe, Plan. Stay put if unsure, signal with three whistle '
        'blasts, and call or text 911 with your GPS coordinates.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-11',
    text:
        'Q: What number do I call in an emergency? A: 911, the Philippine '
        'national emergency hotline, plus your guide, camp manager, and the '
        'PAMO or LGU rescue.',
  ),
  KyrielleKnowledgeChunk(
    id: 'HSM-PH-FAQ-12',
    text:
        'Q: What are the Leave No Trace principles? A: Plan ahead; travel '
        'and camp on durable surfaces; dispose of waste properly; leave '
        'what you find; minimize campfire impacts; respect wildlife; be '
        'considerate of other visitors.',
  ),
];
