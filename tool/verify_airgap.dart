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

  // 2. Audit lib/ Dart files for network imports & socket invocations
  _auditLibNetworkSurface(violations);

  // 3. Audit lib/domain/ for Clean Architecture boundary violations
  _auditDomainLayerIsolation(violations);

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
      '\n[1/3] Auditing AndroidManifest.xml files for network permissions...');
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

void _auditLibNetworkSurface(List<String> violations) {
  stdout.writeln(
      '\n[2/3] Auditing lib/ Dart source files for forbidden network libraries...');
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
      '\n[3/3] Auditing lib/domain/ for Clean Architecture boundary isolation...');
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
