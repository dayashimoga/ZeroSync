import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/main.dart';
import 'package:airdrop_qr/presentation/pages/home_page.dart';

void main() {
  testWidgets(
      'ZeroSyncApp launches and renders ZeroSyncHomePage with air-gap badges',
      (tester) async {
    // Provide explicit test viewport size
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ZeroSyncApp());
    await tester.pump();

    // Verifies app shell and header
    expect(find.byType(ZeroSyncHomePage), findsOneWidget);
    expect(find.text('ZeroSync'), findsOneWidget);
    expect(find.text('AIR-GAPPED'), findsOneWidget);

    // Verifies security card
    expect(find.text('HARDENED ZERO-TRUST AIR-GAP'), findsOneWidget);
  });
}
