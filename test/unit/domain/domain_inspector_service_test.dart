import 'package:airdrop_qr/domain/services/domain_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DomainInspectorService inspector;

  setUp(() {
    inspector = DomainInspectorService();
  });

  group('Safe & Benign URL Inspection', () {
    test('Standard HTTPS domain reports safe with zero threats', () {
      final report = inspector.inspect('https://github.com/flutter/flutter');

      expect(report.isValidUrl, isTrue);
      expect(report.isSafe, isTrue);
      expect(report.isHighRisk, isFalse);
      expect(report.overallSeverity, equals(ThreatSeverity.none));
      expect(report.scheme, equals('https'));
      expect(report.host, equals('github.com'));
      expect(report.rootDomain, equals('github.com'));
      expect(report.subdomains, isEmpty);
      expect(report.path, equals('/flutter/flutter'));
      expect(report.detectedThreats, isEmpty);
      expect(report.preflightData.requiresExplicitConfirmation, isFalse);
      expect(report.preflightData.protocolDescriptor, contains('Secure TLS (HTTPS)'));
      expect(report.preflightData.registrableRootDomain, equals('github.com'));
    });

    test('Standard subdomain structure extracts rootDomain and subdomains correctly', () {
      final report = inspector.inspect('https://docs.flutter.dev/get-started/install');

      expect(report.isSafe, isTrue);
      expect(report.host, equals('docs.flutter.dev'));
      expect(report.rootDomain, equals('flutter.dev'));
      expect(report.subdomains, equals(['docs']));
      expect(report.topLevelDomain, equals('dev'));
    });

    test('Plaintext HTTP triggers low severity unencryptedTransport threat', () {
      final report = inspector.inspect('http://example.org/index.html');

      expect(report.isValidUrl, isTrue);
      expect(report.isSafe, isTrue); // low severity is considered safe with warning
      expect(report.overallSeverity, equals(ThreatSeverity.low));
      expect(
        report.detectedThreats.any(
          (t) => t.category == ThreatCategory.unencryptedTransport,
        ),
        isTrue,
      );
      expect(report.preflightData.protocolDescriptor, contains('Insecure Plaintext'));
      expect(report.preflightData.requiresExplicitConfirmation, isFalse);
    });
  });

  group('Direct IP Host Detection', () {
    test('Flags raw IPv4 dotted-decimal addresses with high severity', () {
      final report = inspector.inspect('http://192.168.1.105:8080/setup.bin');

      expect(report.isDirectIp, isTrue);
      expect(report.isHighRisk, isTrue);
      expect(report.overallSeverity, equals(ThreatSeverity.high));
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.directIpHost &&
              t.severity == ThreatSeverity.high,
        ),
        isTrue,
      );
      expect(report.preflightData.requiresExplicitConfirmation, isTrue);
    });

    test('Flags raw IPv6 addresses with high severity', () {
      final report = inspector.inspect('http://[2001:db8::1]:8080/api');

      expect(report.isDirectIp, isTrue);
      expect(report.isHighRisk, isTrue);
      expect(
        report.detectedThreats.any(
          (t) => t.category == ThreatCategory.directIpHost,
        ),
        isTrue,
      );
    });
  });

  group('Dangerous & Privileged Scheme Detection', () {
    test('Flags javascript: execution scheme with critical severity', () {
      final report = inspector.inspect('javascript:alert(document.cookie)');

      expect(report.isHighRisk, isTrue);
      expect(report.overallSeverity, equals(ThreatSeverity.critical));
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.highRiskScheme &&
              t.severity == ThreatSeverity.critical,
        ),
        isTrue,
      );
      expect(report.preflightData.protocolDescriptor, contains('Executable Script'));
      expect(report.preflightData.requiresExplicitConfirmation, isTrue);
    });

    test('Flags data: and file: schemes with critical severity', () {
      final reportData = inspector.inspect('data:text/html;base64,PHNjcmlwdD4=');
      expect(reportData.overallSeverity, equals(ThreatSeverity.critical));

      final reportFile = inspector.inspect('file:///etc/shadow');
      expect(reportFile.overallSeverity, equals(ThreatSeverity.critical));
    });

    test('Flags telephony (tel:) and SMS (sms:) schemes with medium severity', () {
      final reportTel = inspector.inspect('tel:+18005550199');
      expect(reportTel.overallSeverity, equals(ThreatSeverity.medium));
      expect(
        reportTel.detectedThreats.any(
          (t) => t.category == ThreatCategory.privilegedNativeScheme,
        ),
        isTrue,
      );
      expect(reportTel.preflightData.requiresExplicitConfirmation, isTrue);

      final reportSms = inspector.inspect('sms:+18005550199?body=Hello');
      expect(reportSms.overallSeverity, equals(ThreatSeverity.medium));
    });
  });

  group('Homoglyph & Punycode Deception Detection', () {
    test('Flags Punycode xn-- encoded domains with critical severity', () {
      // Punycode for apple lookalike
      final report = inspector.inspect('https://xn--pple-43d.com/login');

      expect(report.isPunycode, isTrue);
      expect(report.isHighRisk, isTrue);
      expect(report.overallSeverity, equals(ThreatSeverity.critical));
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.punycodeHomograph &&
              t.severity == ThreatSeverity.critical,
        ),
        isTrue,
      );
      expect(report.preflightData.warningList.any((w) => w.contains('Punycode')), isTrue);
    });

    test('Flags confusable Cyrillic homoglyphs spoofing Latin domains', () {
      // 'gооgle.com' with Cyrillic small letter 'о' (U+043E)
      const fakeGoogle = 'https://g\u043E\u043Egle.com/signin';
      final report = inspector.inspect(fakeGoogle);

      expect(report.isHighRisk, isTrue);
      expect(report.overallSeverity, equals(ThreatSeverity.critical));
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.punycodeHomograph &&
              t.severity == ThreatSeverity.critical,
        ),
        isTrue,
      );
    });
  });

  group('Deceptive URL Structures & Exploits', () {
    test('Flags embedded user credentials in authority (user:pass@host)', () {
      final report = inspector.inspect('https://google.com:auth@attacker-host.com/session');

      expect(report.isHighRisk, isTrue);
      expect(report.host, equals('attacker-host.com'));
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.embeddedCredentials &&
              t.severity == ThreatSeverity.high,
        ),
        isTrue,
      );
    });

    test('Flags excessive subdomain hierarchy (>= 4 levels)', () {
      final report = inspector.inspect('https://login.secure.verify.auth.bank.attacker.com/portal');

      expect(report.subdomains.length, equals(5));
      expect(report.rootDomain, equals('attacker.com'));
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.excessiveSubdomains &&
              t.severity == ThreatSeverity.high,
        ),
        isTrue,
      );
    });

    test('Flags suspicious high-abuse TLDs (.zip, .mov, .tk)', () {
      final reportZip = inspector.inspect('https://financial-invoice.zip');
      expect(
        reportZip.detectedThreats.any(
          (t) => t.category == ThreatCategory.suspiciousTld,
        ),
        isTrue,
      );
      expect(reportZip.overallSeverity, equals(ThreatSeverity.medium));

      final reportTk = inspector.inspect('https://free-crypto-giveaway.tk');
      expect(
        reportTk.detectedThreats.any(
          (t) => t.category == ThreatCategory.suspiciousTld,
        ),
        isTrue,
      );
    });

    test('Flags open-redirect parameter patterns pointing to external URLs', () {
      final report = inspector.inspect(
        'https://trusted-portal.com/login?redirect=https://evil-harvest.com/callback',
      );

      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.openRedirectPattern &&
              t.severity == ThreatSeverity.medium,
        ),
        isTrue,
      );
      expect(report.overallSeverity, equals(ThreatSeverity.medium));
      expect(report.preflightData.requiresExplicitConfirmation, isTrue);
    });
  });

  group('Malformed Syntax & Control Character Injection', () {
    test('Flags null-byte injection and control characters', () {
      final report = inspector.inspect('https://trusted.com\x00/evil.exe');

      expect(report.isHighRisk, isTrue);
      expect(
        report.detectedThreats.any(
          (t) =>
              t.category == ThreatCategory.malformedSyntax &&
              t.severity == ThreatSeverity.critical,
        ),
        isTrue,
      );
    });

    test('Constructs graceful malformed report on unparseable inputs', () {
      final report = inspector.inspect(':::://invalid-syntax');

      expect(report.isValidUrl, isFalse);
      expect(report.isHighRisk, isTrue);
      expect(report.overallSeverity, equals(ThreatSeverity.critical));
      expect(report.preflightData.requiresExplicitConfirmation, isTrue);
    });
  });

  group('Preflight Interstitial Data Formatting', () {
    test('Constructs rich formatted pre-flight breakdown for user verification', () {
      final report = inspector.inspect(
        'https://sub.portal.example.com:8443/checkout?item=42&coupon=DISCOUNT#summary',
      );

      final preflight = report.preflightData;
      expect(preflight.protocolDescriptor, equals('Secure TLS (HTTPS)'));
      expect(preflight.registrableRootDomain, equals('example.com'));
      expect(preflight.fullHost, equals('sub.portal.example.com'));
      expect(preflight.pathAndQuery, equals('/checkout?item=42&coupon=DISCOUNT'));
      expect(preflight.requiresExplicitConfirmation, isFalse);
    });
  });
}

