import 'package:airdrop_qr/domain/services/tracker_stripper_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TrackerStripperService stripper;

  setUp(() {
    stripper = TrackerStripperService();
  });

  group('Commercial Tracking Identifier Sanitization', () {
    test('Strips all UTM tracking parameters (utm_*)', () {
      const url =
          'https://example.com/blog/article?utm_source=twitter&utm_medium=social&utm_campaign=spring_sale&utm_term=qr+codes&utm_content=logolink';

      final result = stripper.sanitize(url);

      expect(result.wasModified, isTrue);
      expect(result.sanitizedUrl, equals('https://example.com/blog/article'));
      expect(result.preservedParameters, isEmpty);
      expect(
        result.strippedParameters,
        containsAll([
          'utm_source',
          'utm_medium',
          'utm_campaign',
          'utm_term',
          'utm_content',
        ]),
      );
      expect(result.bytesSaved, greaterThan(0));
    });

    test('Strips Meta / Facebook click IDs (fbclid)', () {
      const url = 'https://shop.example.com/product/123?fbclid=IwAR2V8X9abc123DEF456';
      final result = stripper.sanitize(url);

      expect(result.wasModified, isTrue);
      expect(result.sanitizedUrl, equals('https://shop.example.com/product/123'));
      expect(result.strippedParameters, contains('fbclid'));
    });

    test('Strips Google Ad click IDs (gclid, gbraid, wbraid, gad_source)', () {
      const url =
          'https://services.example.com/quote?gclid=CjwKCAjw&gbraid=0AAAAAD&gad_source=1&item=solar';
      final result = stripper.sanitize(url);

      expect(result.wasModified, isTrue);
      expect(
        result.sanitizedUrl,
        equals('https://services.example.com/quote?item=solar'),
      );
      expect(result.preservedParameters, equals({'item': 'solar'}));
      expect(
        result.strippedParameters,
        containsAll(['gclid', 'gbraid', 'gad_source']),
      );
    });

    test('Strips Microsoft (msclkid) and Mailchimp (mc_eid, mc_cid) identifiers', () {
      const url =
          'https://newsletter.example.org/read?msclkid=a1b2c3d4&mc_eid=abc1234&mc_cid=998877';
      final result = stripper.sanitize(url);

      expect(result.wasModified, isTrue);
      expect(result.sanitizedUrl, equals('https://newsletter.example.org/read'));
      expect(result.preservedParameters, isEmpty);
      expect(
        result.strippedParameters,
        containsAll(['msclkid', 'mc_eid', 'mc_cid']),
      );
    });

    test('Strips referral prefixes (ref_, ref, aff_id)', () {
      const url =
          'https://portal.example.com/signup?ref_src=affiliate_network&aff_id=9876&ref=partner_link&plan=pro';
      final result = stripper.sanitize(url);

      expect(result.wasModified, isTrue);
      expect(
        result.sanitizedUrl,
        equals('https://portal.example.com/signup?plan=pro'),
      );
      expect(result.preservedParameters, equals({'plan': 'pro'}));
      expect(
        result.strippedParameters,
        containsAll(['ref_src', 'aff_id', 'ref']),
      );
    });

    test('Preserves legitimate functional parameters intact', () {
      const url =
          'https://search.example.com/items?query=flutter+widgets&page=3&sort=desc&category=mobile';
      final result = stripper.sanitize(url);

      expect(result.wasModified, isFalse);
      expect(result.sanitizedUrl, equals(url));
      expect(result.strippedParameters, isEmpty);
      expect(result.preservedParameters.length, equals(4));
      expect(result.preservedParameters['query'], equals('flutter widgets'));
      expect(result.preservedParameters['page'], equals('3'));
    });
  });

  group('Shortlink Obscuration & Masking Warnings', () {
    test('Flags bit.ly URLs with shortlink warning', () {
      const url = 'https://bit.ly/3xY456z?utm_source=sms';
      final result = stripper.sanitize(url);

      expect(result.isShortlink, isTrue);
      expect(result.shortlinkProvider, equals('bit.ly'));
      expect(result.shortlinkWarning, isNotNull);
      expect(result.shortlinkWarning, contains('obscured shortlink'));
      // Tracking param stripped from shortlink query
      expect(result.sanitizedUrl, equals('https://bit.ly/3xY456z'));
    });

    test('Flags tinyurl.com, t.co, and is.gd shortlink domains', () {
      final resTiny = stripper.sanitize('https://tinyurl.com/y2abcde');
      expect(resTiny.isShortlink, isTrue);
      expect(resTiny.shortlinkProvider, equals('tinyurl.com'));

      final resTco = stripper.sanitize('https://t.co/99887766');
      expect(resTco.isShortlink, isTrue);

      final resIsGd = stripper.sanitize('https://is.gd/xyz123');
      expect(resIsGd.isShortlink, isTrue);
    });

    test('Recognizes shortlink subdomain delegation', () {
      final result = stripper.sanitize('https://news.bit.ly/headline');
      expect(result.isShortlink, isTrue);
      expect(result.shortlinkProvider, equals('news.bit.ly'));
    });

    test('Standard domain is not flagged as shortlink', () {
      final result = stripper.sanitize('https://flutter.dev/docs');
      expect(result.isShortlink, isFalse);
      expect(result.shortlinkProvider, isNull);
      expect(result.shortlinkWarning, isNull);
    });
  });

  group('Edge Cases & Resiliency', () {
    test('Handles empty and whitespace inputs gracefully', () {
      final emptyResult = stripper.sanitize('');
      expect(emptyResult.wasModified, isFalse);
      expect(emptyResult.sanitizedUrl, equals(''));

      final spaceResult = stripper.sanitize('   ');
      expect(spaceResult.wasModified, isFalse);
    });

    test('Handles URLs without query strings', () {
      const url = 'https://example.com/about-us';
      final result = stripper.sanitize(url);

      expect(result.wasModified, isFalse);
      expect(result.sanitizedUrl, equals(url));
      expect(result.strippedParameters, isEmpty);
    });

    test('SanitizedUrlResult toString formatting', () {
      final result = stripper.sanitize('https://example.com?utm_source=test');
      expect(result.toString(), contains('modified: true'));
      expect(result.toString(), contains('stripped: 1'));
    });
  });
}

