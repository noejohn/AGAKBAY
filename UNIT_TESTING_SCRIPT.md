# AGAKBAY Unit Testing Script

**Coverage:** To be measured after execution  
**Tools:** Flutter `flutter_test` for the mobile app and admin dashboard. Firmware checks use a compatible Heltec board; isolated firmware unit tests require a host-side harness or testable extracted logic.

Run the current Flutter tests from the project root:

```powershell
flutter test --reporter expanded
```

The test output screenshot provided shows the Kyrielle RAG tests and Mount Apo GPX asset test passing. It does not show admin dashboard or firmware test results. The tables below separate coverage by component. Fill Actual result, Pass/Fail, and Evidence only after each test is performed.

## A. Mobile application

| ID | Test (what to do) | Where to check / procedure | Expected result | Actual result | Pass / Fail | Evidence file name |
|---|---|---|---|---|---|---|
| MOB-UT-001 | **RAG knowledge lookup:** Ask “How do I create a Hike Room?” | **Automated:** Run `flutter test --reporter expanded`; find `finds instructions for creating a Hike Room`. | Relevant Hike Room instructions are returned without an embeddings API. |  |  |  |
| MOB-UT-002 | **RAG empty query:** Query with empty text or stop-word-only text. | **Automated:** Find `returns no match for empty or generic stop-word-only queries`. | No unrelated knowledge result is returned. |  |  |  |
| MOB-UT-003 | **Mountain recommendation:** Search for a mountain or view recommendations for a matching preference. | **Manual app check:** Sign in, open Explore/recommendations, enter a query matching a known mountain, and inspect the result order. For a repeatable unit test, use fixed catalog/preferences with `AgakRecommendationEngine`. | Matching mountains rank ahead of unrelated entries; results are valid catalog entries. |  |  |  |
| MOB-UT-004 | **Packing list:** Open a scheduled hike’s packing list and inspect items. | **Manual app check:** Open a scheduled hike and view its packing list. To check duplicates reliably, add a Dart test for `lib/services/agak_packing_list.dart`. | Applicable items appear without duplicates. |  |  |  |
| MOB-UT-005 | **Offline activity serialization:** Check a sample point’s database map and sync map. | **Automated test needed:** No screen exposes these maps. Add Dart tests for `OfflineActivityPoint.toMap()` and `toSyncMap()` in `lib/services/offline_activity_database.dart`. | Both maps contain the expected coordinate and time fields. |  |  |  |
| MOB-UT-006 | **Offline activity status parsing:** Check valid status values and an unknown value. | **Automated test needed:** Add a Dart test for `ActivityStatus.fromDb()` in `lib/services/offline_activity_database.dart`. | Known values map correctly; unknown values use the safe fallback. |  |  |  |
| MOB-UT-007 | **Offline map caching:** Cache an area, then open it without network. | **Manual app check:** Open Profile → Offline Maps, cache/download an area, turn on airplane mode, and reopen it. Tile path/cache logic needs a Dart test for `OfflineMapService.tilePath()` and `isTileCached()`. | Cached map tiles remain available offline; a missing tile is not reported as cached. |  |  |  |
| MOB-UT-008 | **Offline activity save and sync:** Finish and save an activity offline, then reconnect. | **Manual app check:** Disable Wi-Fi/mobile data, record and finish an offline GPS activity, inspect its status, then reconnect and check for sync. | Activity stays saved and pending offline, then syncs when connectivity returns. |  |  |  |
| MOB-UT-009 | **Hike Room participant location:** Check participants with and without a GPS fix. | **Manual app/integration:** Use two phones in one Hike Room. Allow location on one; deny/disable it on the other. Inspect the guide’s participant list/map. | Valid location is shown; missing location is unavailable, not `(0,0)`. |  |  |  |
| MOB-UT-010 | **Mount Apo GPX asset:** Check the route in the Flutter asset manifest. | **Automated:** The screenshot shows `Mount Apo GPX route is included in the asset manifest` and `All tests passed!`. | The Mount Apo GPX route is included in the asset manifest. | The route was found in the asset manifest; the test passed. | Pass | Screenshot of `flutter test --reporter expanded` |

## B. Admin dashboard

| ID | Test (what to do) | Where to check / procedure | Expected result | Actual result | Pass / Fail | Evidence file name |
|---|---|---|---|---|---|---|
| ADM-UT-001 | **Admin sign-in:** Sign in with valid admin credentials, then try an invalid password. | **Manual app check:** Open the admin login screen. Confirm behavior for both attempts. Auth service: `lib/services/admin_password_auth_service.dart`. | Valid admin credentials grant access; invalid credentials are rejected with an error. |  |  |  |
| ADM-UT-002 | **Role authorization:** Sign in with a normal user account and try to open an admin screen/action. | **Manual app/security check:** Test with a non-admin account and verify its access to dashboard routes and protected actions. | A non-admin user cannot access admin-only screens or actions. |  |  |  |
| ADM-UT-003 | **Account management action:** Perform one supported admin account action, then inspect the affected account. | **Manual/integration:** Use the admin dashboard against the Firebase Emulator Suite or approved test project; choose a test account and verify the resulting state. | The requested change is applied to the intended account and reflected in the dashboard/data. |  |  |  |
| ADM-UT-004 | **Incident/report review:** Open a test incident/report in the admin dashboard and perform an available review action. | **Manual/integration:** Use a seeded test report and verify both the dashboard and persisted state. | The report details display correctly and the selected action updates its status once. |  |  |  |
| ADM-UT-005 | **Your own admin test:** Record another admin-only function in this build. | Name the screen/action, test account/fixture, and exact steps. |  |  |  |  |

## C. Heltec firmware

| ID | Test (what to do) | Where to check / procedure | Expected result | Actual result | Pass / Fail | Evidence file name |
|---|---|---|---|---|---|---|
| FW-UT-001 | **Firmware BLE service identity:** Connect with a BLE scanner and inspect advertised name and service UUID. | **Hardware check:** Flash the hiker or tour-guide build, scan nearby BLE devices, and inspect the advertised service/characteristics. Compare with UUID definitions in `firmware/agakbay_heltec/agakbay_heltec.ino` and `lib/services/heltec_ble_service.dart`. | Advertised device name and BLE UUIDs match the selected role and app definitions. |  |  |  |
| FW-UT-002 | **SOS payload receive:** Send `SOS|Alex|14.599512|120.984222|Accident` to the SOS BLE characteristic. | **Hardware/integration:** Connect a phone or BLE test tool to a flashed board; inspect serial output and a second board’s received alert. | Firmware captures the name, coordinates, and reason, then queues an SOS relay. |  |  |  |
| FW-UT-003 | **SOS LoRa relay with GPS fix:** Trigger SOS on one board with a valid fix and receive it on another board. | **Hardware/integration:** Use two boards configured to the same LoRa settings and within range; inspect serial output, guide board display, and phone notification. | Receiver identifies the sender and reason, preserves valid coordinates, and forwards the relay over BLE. |  |  |  |
| FW-UT-004 | **SOS without GPS fix:** Trigger/relay an SOS with no location fix. | **Hardware/integration:** Repeat the two-board SOS test with no GPS fix and inspect the guide display/app map. | Alert is delivered; placeholder `0,0` is not presented as a real location. |  |  |  |
| FW-UT-005 | **Stop-hiking relay:** Send `STOP|Alex|Feeling unwell` and receive it on the guide board. | **Hardware/integration:** Connect two boards and their phones; check receiver serial/display and guide app. | Stop status and reason arrive separately from SOS; stop feedback uses the non-emergency behavior. |  |  |  |
| FW-UT-006 | **Guide acknowledgment relay:** Send `ACK|Alex` from the guide board and receive it on the hiker board. | **Hardware/integration:** Continue the stop test; inspect serial/display and hiker phone confirmation. | Acknowledgment is relayed back and associated with Alex. |  |  |  |
| FW-UT-007 | **SOS button debounce/trigger:** Press and release the external SOS switch once, then test repeated presses. | **Hardware check:** With the board safely powered, operate the GPIO4-to-GND switch and inspect serial output, buzzer feedback, and receiver. | A press queues an SOS; contact bounce does not create repeated alerts. |  |  |  |
| FW-UT-008 | **Your own firmware test:** Record another board function or malformed-payload test. | State board setup, input payload/action, and where output is observed (serial, OLED, BLE, or LoRa). |  |  |  |  |

## Execution notes

- Only the mobile RAG and GPX cases listed in the terminal screenshot are evidenced as passing. Do not mark admin or firmware cases passed based on that Flutter run.
- Hardware checks verify the integrated board/app behavior. They are not isolated unit tests; isolated firmware unit tests would require extracting parsing/logic into testable functions and running a suitable host-side test harness.
- For evidence, save terminal output for automated tests and screenshots/photos or serial logs for manual checks. Record board role/firmware configuration and phone used for hardware cases.

## F. Bug list

| Bug ID | Found in test | What went wrong | Severity | Status | Fix plan (who, by when) | Retest build and evidence |
|---|---|---|---|---|---|---|
| BUG-001 | Trail submission and approval; My Hikes → Recorded → Uploaded recordings (functional test to add to the system test form) | After the trail route was approved, its status still displayed **Processing** instead of reflecting the approval. | Major | Open | Owner and target date: TBD. Check the approval status update and the mobile app’s uploaded-recording status refresh. | Retest after fix; screenshot supplied by user showing the recording marked Processing after approval. |
| BUG-002 | Trail recording during an active hike; inspect the route as you approach the destination (ST-F-010) | The trail initially appears correct, but as the hiker gets near the location, the displayed route changes to a straight line instead of continuing to follow the recorded/approved trail. | Minor | Open | Owner and target date: TBD. Check how the active route polyline is updated near the destination and ensure it continues to use the ordered recorded/approved route points. | Retest after fix; screenshot supplied by user showing the straight line during trail recording. |
