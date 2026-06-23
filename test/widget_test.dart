// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tunga/main.dart';

void main() {
  testWidgets('Agakbay welcome screen renders correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: WelcomeScreen(firebaseReady: false)),
    );

    expect(find.text('Agakbay'), findsOneWidget);
    expect(find.text('EXPLORE PEAKS. TRACK ADVENTURES.'), findsOneWidget);
    expect(find.text('GET STARTED'), findsOneWidget);
  });

  test('Mount Apo GPX route is included in the asset manifest', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), contains('assets/trails/mt_apo.gpx'));
    final gpx = await rootBundle.loadString('assets/trails/mt_apo.gpx');
    expect(gpx, contains('<trkpt'));
  });
}
