// Copyright (c) 2026 ZeroSync / AirDrop-QR Team.
// Pure Dart Air-Gap AST & Manifest Security Linter.
// Inviolable Security & Clean Architecture Boundary Auditor.

import 'dart:io';

void main() {
  stdout.writeln('====================================================');
  stdout.writeln('  ZeroSync Air-Gap & Architectural Boundary Linter  ');
  stdout.writeln('====================================================');

  final violations = <String>[];

  // 1. Audit Android Manifests for forbidden network permissions
  _auditAndroidManifests(violations);

  // 2. Audit macOS & iOS Entitlements for forbidden network capabilities
  _auditDesktopAndMobileEntitlements(violations);

  // 3. Audit lib/ Dart files for network imports & socket invocations
  _auditLibNetworkSurface(violations);

  // 4. Audit lib/domain/ for Clean Architecture boundary violations
  _auditDomainLayerIsolation(violations);

  // 5. Audit lib/presentation/ for anti-placeholder and hardcoded telemetry invariants
  _auditAntiPlaceholderAndTelemetry(violations);

  stdout.writeln('');
  if (violations.isEmpty) {
    stdout.writeln(
        '[PASS] Zero-trust air-gap and clean architecture invariants verified.');
    stdout.writeln('       Total violations: 0.');
    exit(0);
  } else {
    stderr.writeln(
        '[FAIL] Air-gap security violations detected (${violations.length}):');
    for (var i = 0; i < violations.length; i++) {
      stderr.writeln('  [${i + 1}] ${violations[i]}');
    }
    exit(1);
  }
}

void _auditAndroidManifests(List<String> violations) {
  stdout.writeln(
      '\n[1/5] Auditing AndroidManifest.xml files for network permissions...');
  final manifestDir = Directory('android/app/src');
  if (!manifestDir.existsSync()) {
    stdout.writeln(
        '  Notice: android/app/src directory not found. Skipping manifest check.');
    return;
  }

  final forbiddenPermissions = RegExp(
    r'android\.permission\.(INTERNET|ACCESS_NETWORK_STATE)',
    caseSensitive: false,
  );

  final manifests = manifestDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('AndroidManifest.xml'));

  for (final manifest in manifests) {
    final content = manifest.readAsStringSync();
    if (forbiddenPermissions.hasMatch(content)) {
      violations.add(
        'Forbidden network permission in manifest: ${manifest.path}',
      );
    } else {
      stdout.writeln('  [OK] Clean manifest: ${manifest.path}');
    }
  }
}

void _auditDesktopAndMobileEntitlements(List<String> violations) {
  stdout.writeln(
      '\n[2/5] Auditing macOS entitlements & mobile plists for network capabilities...');
  final macosDir = Directory('macos/Runner');
  if (macosDir.existsSync()) {
    final forbiddenEntitlements = RegExp(
      r'com\.apple\.security\.network\.(client|server)',
      caseSensitive: false,
    );

    final entitlements = macosDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.entitlements'));

    for (final ent in entitlements) {
      final content = ent.readAsStringSync();
      if (forbiddenEntitlements.hasMatch(content)) {
        violations.add(
          'Forbidden network capability in macOS entitlement: ${ent.path}',
        );
      } else {
        stdout.writeln('  [OK] Clean macOS entitlement: ${ent.path}');
      }
    }
  } else {
    stdout.writeln(
        '  Notice: macos/Runner directory not found. Skipping macOS entitlements.');
  }

  final iosDir = Directory('ios/Runner');
  if (iosDir.existsSync()) {
    final plistFile = File('ios/Runner/Info.plist');
    if (plistFile.existsSync()) {
      final content = plistFile.readAsStringSync();
      final insecureAts = RegExp(
        r'<key>\s*NSAllowsArbitraryLoads\s*</key>\s*<true\s*/>',
        caseSensitive: false,
      );
      if (insecureAts.hasMatch(content)) {
        violations.add(
          'Insecure ATS arbitrary network load permitted in ios/Runner/Info.plist',
        );
      } else {
        stdout.writeln('  [OK] Clean iOS Info.plist: ${plistFile.path}');
      }
    }
  }
}

void _auditLibNetworkSurface(List<String> violations) {
  stdout.writeln(
      '\n[3/5] Auditing lib/ Dart source files for forbidden network libraries...');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    violations.add('CRITICAL: lib/ directory does not exist.');
    return;
  }

  final forbiddenImports = RegExp(
    r'''import\s+['"]package:(http|dio|web_socket_channel).*['"]''',
  );

  final forbiddenTokens = RegExp(
    r'\b(HttpClient|RawDatagramSocket|ServerSocket|Socket\.connect)\b',
  );

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  var scanned = 0;
  for (final file in dartFiles) {
    scanned++;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Skip comments
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      if (forbiddenImports.hasMatch(line)) {
        violations.add(
          'Forbidden network import at ${file.path}:${i + 1}: $trimmed',
        );
      }
      if (forbiddenTokens.hasMatch(line)) {
        violations.add(
          'Forbidden network socket/client invocation at ${file.path}:${i + 1}: $trimmed',
        );
      }
    }
  }
  stdout.writeln('  Scanned $scanned files across lib/.');
}

void _auditDomainLayerIsolation(List<String> violations) {
  stdout.writeln(
      '\n[4/5] Auditing lib/domain/ for Clean Architecture boundary isolation...');
  final domainDir = Directory('lib/domain');
  if (!domainDir.existsSync()) {
    stdout.writeln(
        '  Notice: lib/domain directory not found. Skipping domain audit.');
    return;
  }

  final forbiddenDomainImports = RegExp(
    r'''import\s+['"](package:flutter\/|package:flutter|package:airdrop_qr\/data\/|package:airdrop_qr\/presentation\/|\.\.\/data\/|\.\.\/presentation\/)''',
  );

  final domainFiles = domainDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  var scanned = 0;
  for (final file in domainFiles) {
    scanned++;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      if (forbiddenDomainImports.hasMatch(line)) {
        violations.add(
          'Clean Architecture violation in domain layer at ${file.path}:${i + 1}: $trimmed',
        );
      }
    }
  }
  stdout.writeln('  Scanned $scanned domain files for pure Dart compliance.');
}

void _auditAntiPlaceholderAndTelemetry(List<String> violations) {
  stdout.writeln(
      '\n[5/5] Auditing lib/presentation/ for anti-placeholder & hardcoded telemetry invariants...');
  final presentationDir = Directory('lib/presentation');
  if (!presentationDir.existsSync()) {
    stdout.writeln(
        '  Notice: lib/presentation directory not found. Skipping presentation audit.');
    return;
  }

  // Detect empty callback stubs like onPressed: () {} or onTap: () {}
  final emptyCallbackPattern = RegExp(
    r'''(onPressed|onTap)\s*:\s*\(\)\s*\{\s*\}''',
  );

  // Detect hardcoded demo TransferProgressMetrics with non-zero totalChunks in presentation files
  final hardcodedTelemetryPattern = RegExp(
    r'''TransferProgressMetrics\s*\([^)]*totalChunks:\s*[1-9]''',
    dotAll: true,
  );

  final presentationFiles = presentationDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  var scanned = 0;
  for (final file in presentationFiles) {
    scanned++;
    final content = file.readAsStringSync();

    // Presentation pages must NEVER instantiate hardcoded demo telemetry
    if (file.path.contains('pages') &&
        hardcodedTelemetryPattern.hasMatch(content)) {
      violations.add(
        'Hardcoded demo TransferProgressMetrics detected in page: ${file.path}. All UI telemetry must be initialized from reactive BLoC state or TransferProgressMetrics.initial().',
      );
    }

    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      if (emptyCallbackPattern.hasMatch(line)) {
        violations.add(
          'Empty callback stub detected in presentation layer at ${file.path}:${i + 1}: $trimmed',
        );
      }
    }
  }
  stdout.writeln(
      '  Scanned $scanned presentation files for anti-placeholder compliance.');
}
