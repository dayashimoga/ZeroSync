import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/entities/vcard_payload.dart';
import 'package:airdrop_qr/domain/services/vcard_serializer_service.dart';

void main() {
  late VCardSerializerService service;

  setUp(() {
    service = VCardSerializerService();
  });

  group('Universal Plain Text & URI Serializer', () {
    test('Serializes and normalizes plain text with mixed line-breaks', () {
      const input = 'ZeroSync\r\nAir-Gapped\rOptical\nToolkit';
      final serialized = service.serializeText(input);
      expect(serialized, equals('ZeroSync\nAir-Gapped\nOptical\nToolkit'));
    });

    test('Throws ArgumentError on empty or pure whitespace text', () {
      expect(() => service.serializeText('   \n  '), throwsArgumentError);
    });

    test('Validates and serializes compliant RFC 3986 URIs', () {
      final uri = Uri.parse('https://zerosync.security/airgap?auth=true');
      final serialized = service.serializeUri(uri);
      expect(serialized, equals('https://zerosync.security/airgap?auth=true'));
    });

    test('Blocks forbidden URI schemes under air-gap security rules', () {
      final fileUri = Uri.parse('file:///etc/shadow');
      expect(() => service.serializeUri(fileUri), throwsArgumentError);

      final jsUri = Uri.parse('javascript:alert(1)');
      expect(() => service.serializeUri(jsUri), throwsArgumentError);
    });
  });

  group('vCard 4.0 RFC 6350 Serialization & Invariants', () {
    test('Requires FN (Formatted Name)', () {
      const invalid = VCardPayload(formattedName: '');
      expect(() => service.serializeVCard4(invalid), throwsArgumentError);
    });

    test('Serializes full contact payload with structured properties', () {
      const payload = VCardPayload(
        formattedName: 'Dr. Satoshi Nakamoto, PhD',
        familyName: 'Nakamoto',
        givenName: 'Satoshi',
        prefix: 'Dr.',
        suffix: 'PhD',
        organization: 'ZeroSync Labs',
        department: 'Cryptography Core',
        jobTitle: 'Principal Cryptographer',
        phones: [
          ContactPhone(number: '+1-555-0199', types: ['cell', 'voice']),
          ContactPhone(number: '+1-555-0100', types: ['work']),
        ],
        emails: [
          ContactEmail(address: 'satoshi@zerosync.local', types: ['work']),
        ],
        addresses: [
          ContactAddress(
            street: '123 Air-Gap Way',
            city: 'Zurich',
            state: 'ZH',
            postalCode: '8001',
            country: 'Switzerland',
            types: ['work'],
          ),
        ],
        urls: ['https://zerosync.local'],
        note: 'Air-gapped peer key: 0x9F8B2C4E',
      );

      final vcard = service.serializeVCard4(payload);

      expect(vcard, contains('BEGIN:VCARD'));
      expect(vcard, contains('VERSION:4.0'));
      expect(vcard, contains('FN:Dr. Satoshi Nakamoto\\, PhD'));
      expect(vcard, contains('N:Nakamoto;Satoshi;;Dr.;PhD'));
      expect(vcard, contains('ORG:ZeroSync Labs;Cryptography Core'));
      expect(vcard, contains('TITLE:Principal Cryptographer'));
      expect(vcard, contains('TEL;TYPE=cell,voice:+1-555-0199'));
      expect(vcard, contains('TEL;TYPE=work:+1-555-0100'));
      expect(vcard, contains('EMAIL;TYPE=work:satoshi@zerosync.local'));
      expect(
          vcard,
          contains(
              'ADR;TYPE=work:;;123 Air-Gap Way;Zurich;ZH;8001;Switzerland'));
      expect(vcard, contains('END:VCARD'));
    });

    test('Sanitizes photo base64 strings and handles data URIs', () {
      final rawBase64 =
          base64.encode(utf8.encode('SIMULATED_IMAGE_DATA_BYTES'));
      final withDataUri = 'data:image/png;base64,  \n$rawBase64\r\n ';

      final payload = VCardPayload(
        formattedName: 'Alice Cryptex',
        photoBase64: withDataUri,
        photoMediaType: 'image/png',
      );

      final serialized = service.serializeVCard4(payload);
      final restored = service.deserializeVCard4(serialized);
      expect(restored.photoBase64, equals(rawBase64));
      expect(restored.photoMediaType, equals('image/png'));
    });

    test('Throws on invalid photo base64 encoding', () {
      const corrupt = VCardPayload(
        formattedName: 'Bob Malicious',
        photoBase64: '%%%NOT_BASE64&&&',
      );
      expect(() => service.serializeVCard4(corrupt), throwsArgumentError);
    });
  });

  group('vCard 4.0 Round-Trip Deserialization & Escaping', () {
    test('Correctly escapes and unescapes commas, semicolons, and newlines',
        () {
      const original = VCardPayload(
        formattedName: 'Complex, Name; Escaped',
        note: 'Line 1\nLine 2; with semicolon and, comma\\backslash',
        organization: 'Acme, Inc',
        department: 'R&D',
      );

      final vcard = service.serializeVCard4(original);
      final restored = service.deserializeVCard4(vcard);

      expect(restored.formattedName, equals(original.formattedName));
      expect(restored.note, equals(original.note));
      expect(restored.organization, equals('Acme, Inc'));
      expect(restored.department, equals('R&D'));
    });

    test(
        'Folds long lines at 75 octets and unfolds accurately on deserialization',
        () {
      final longNote =
          'A' * 200; // 200 characters should fold into at least 3 lines
      final payload = VCardPayload(
        formattedName: 'Long Note Tester',
        note: longNote,
      );

      final serialized = service.serializeVCard4(payload);
      expect(serialized,
          contains('\r\n ')); // Confirms RFC 6350 CRLF folding occurred

      final restored = service.deserializeVCard4(serialized);
      expect(restored.note, equals(longNote));
    });

    test(
        'Handles multi-byte UTF-8 international characters cleanly across folding boundaries',
        () {
      // Japanese, Arabic, Russian and Emoji characters
      const international = 'こんにちは世界 🌍 مرحباً بالعالم Привет мир';
      const payload = VCardPayload(
        formattedName: '田中 太郎 🚀',
        familyName: '田中',
        givenName: '太郎',
        note: international,
        jobTitle: '暗号化スペシャリスト',
      );

      final serialized = service.serializeVCard4(payload);
      final restored = service.deserializeVCard4(serialized);

      expect(restored.formattedName, equals('田中 太郎 🚀'));
      expect(restored.familyName, equals('田中'));
      expect(restored.givenName, equals('太郎'));
      expect(restored.note, equals(international));
      expect(restored.jobTitle, equals('暗号化スペシャリスト'));
    });
  });
}
