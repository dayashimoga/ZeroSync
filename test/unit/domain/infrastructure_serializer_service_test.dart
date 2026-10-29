import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/entities/infrastructure_payload.dart';
import 'package:airdrop_qr/domain/services/infrastructure_serializer_service.dart';

void main() {
  late InfrastructureSerializerService service;

  setUp(() {
    service = InfrastructureSerializerService();
  });

  group('Wi-Fi Network QR Serializer & Deserializer', () {
    test('Serializes standard WPA2 network configuration with escaping', () {
      const payload = WifiConfigPayload(
        ssid: 'ZeroSync_Guest',
        securityType: WifiSecurityType.wpa2,
        password: 'AirGapSecretPassword123',
        isHidden: false,
      );

      final wire = service.serializeWifi(payload);
      expect(wire,
          equals('WIFI:T:WPA2;S:ZeroSync_Guest;P:AirGapSecretPassword123;;'));

      final restored = service.deserializeWifi(wire);
      expect(restored, equals(payload));
    });

    test('Serializes open (nopass) Wi-Fi network without password field', () {
      const payload = WifiConfigPayload(
        ssid: 'OpenMeshAirport',
        securityType: WifiSecurityType.nopass,
        isHidden: true,
      );

      final wire = service.serializeWifi(payload);
      expect(wire, equals('WIFI:T:nopass;S:OpenMeshAirport;H:true;;'));

      final restored = service.deserializeWifi(wire);
      expect(restored.ssid, equals('OpenMeshAirport'));
      expect(restored.securityType, equals(WifiSecurityType.nopass));
      expect(restored.password, isNull);
      expect(restored.isHidden, isTrue);
    });

    test(
        'Escapes special characters in SSID and password (colon, semicolon, comma, backslash, quote)',
        () {
      const payload = WifiConfigPayload(
        ssid: r'My;Net:With,Chars\"Special',
        securityType: WifiSecurityType.wpa3,
        password: r'Pass;Word:123,456\"Special',
      );

      final wire = service.serializeWifi(payload);
      expect(wire, contains(r'S:My\;Net\:With\,Chars\\\"Special;'));
      expect(wire, contains(r'P:Pass\;Word\:123\,456\\\"Special;'));

      final restored = service.deserializeWifi(wire);
      expect(restored.ssid, equals(r'My;Net:With,Chars\"Special'));
      expect(restored.password, equals(r'Pass;Word:123,456\"Special'));
      expect(restored.securityType, equals(WifiSecurityType.wpa3));
    });

    test('Enforces IEEE 802.11 Wi-Fi invariants', () {
      // Empty SSID
      const emptySsid =
          WifiConfigPayload(ssid: '', password: 'ValidPassword123');
      expect(() => service.serializeWifi(emptySsid), throwsArgumentError);

      // Password missing for WPA
      const missingPass = WifiConfigPayload(
        ssid: 'ValidSSID',
        securityType: WifiSecurityType.wpa2,
      );
      expect(() => service.serializeWifi(missingPass), throwsArgumentError);

      // Password too short (< 8 chars) for WPA
      const shortPass = WifiConfigPayload(
        ssid: 'ValidSSID',
        securityType: WifiSecurityType.wpa2,
        password: 'short',
      );
      expect(() => service.serializeWifi(shortPass), throwsArgumentError);
    });
  });

  group('RFC 5870 Geolocation URI Serializer & Deserializer', () {
    test('Serializes standard 2D coordinates', () {
      const payload = GeoLocationPayload(
        latitude: 37.7749,
        longitude: -122.4194,
      );

      final uri = service.serializeGeo(payload);
      expect(uri, equals('geo:37.7749,-122.4194'));

      final restored = service.deserializeGeo(uri);
      expect(restored.latitude, closeTo(37.7749, 0.0001));
      expect(restored.longitude, closeTo(-122.4194, 0.0001));
      expect(restored.altitude, isNull);
      expect(restored.uncertainty, isNull);
    });

    test('Serializes 3D coordinates with altitude and uncertainty parameter',
        () {
      const payload = GeoLocationPayload(
        latitude: 47.3769,
        longitude: 8.5417,
        altitude: 408.5,
        uncertainty: 15.0,
      );

      final uri = service.serializeGeo(payload);
      expect(uri, equals('geo:47.3769,8.5417,408.5;u=15.0'));

      final restored = service.deserializeGeo(uri);
      expect(restored.latitude, closeTo(47.3769, 0.0001));
      expect(restored.longitude, closeTo(8.5417, 0.0001));
      expect(restored.altitude, closeTo(408.5, 0.01));
      expect(restored.uncertainty, closeTo(15.0, 0.01));
    });

    test('Throws on coordinate invariant violations', () {
      const invalidLat = GeoLocationPayload(latitude: 95.0, longitude: 0.0);
      expect(() => service.serializeGeo(invalidLat), throwsArgumentError);

      const invalidLon = GeoLocationPayload(latitude: 0.0, longitude: -185.0);
      expect(() => service.serializeGeo(invalidLon), throwsArgumentError);

      const invalidUncertainty = GeoLocationPayload(
        latitude: 0.0,
        longitude: 0.0,
        uncertainty: -5.0,
      );
      expect(
          () => service.serializeGeo(invalidUncertainty), throwsArgumentError);
    });
  });

  group('RFC 5545 iCalendar Serializer & Deserializer', () {
    test('Serializes and deserializes timed calendar event with UTC timestamps',
        () {
      final start = DateTime.utc(2026, 11, 15, 14, 30, 0);
      final end = DateTime.utc(2026, 11, 15, 16, 0, 0);

      final payload = CalendarEventPayload(
        uid: 'zerosync-evt-12345',
        summary: 'Air-Gap Protocol Symposium',
        description:
            'Discussing optical data transfer protocols\nMeeting in bunker room 4.',
        location: 'Zurich Vault, Level -2',
        start: start,
        end: end,
        url: 'https://zerosync.local/symposium',
      );

      final ical = service.serializeCalendar(payload);

      expect(ical, contains('BEGIN:VCALENDAR'));
      expect(ical, contains('VERSION:2.0'));
      expect(ical, contains('BEGIN:VEVENT'));
      expect(ical, contains('UID:zerosync-evt-12345'));
      expect(ical, contains('DTSTART:20261115T143000Z'));
      expect(ical, contains('DTEND:20261115T160000Z'));
      expect(ical, contains('SUMMARY:Air-Gap Protocol Symposium'));
      expect(ical, contains('LOCATION:Zurich Vault\\, Level -2'));
      expect(ical, contains('URL:https://zerosync.local/symposium'));
      expect(ical, contains('END:VEVENT'));
      expect(ical, contains('END:VCALENDAR'));

      final restored = service.deserializeCalendar(ical);
      expect(restored.uid, equals('zerosync-evt-12345'));
      expect(restored.summary, equals('Air-Gap Protocol Symposium'));
      expect(
          restored.description,
          equals(
              'Discussing optical data transfer protocols\nMeeting in bunker room 4.'));
      expect(restored.location, equals('Zurich Vault, Level -2'));
      expect(restored.start, equals(start));
      expect(restored.end, equals(end));
      expect(restored.isAllDay, isFalse);
    });

    test('Serializes all-day calendar event with DATE value format', () {
      final start = DateTime.utc(2026, 12, 25);
      final payload = CalendarEventPayload(
        summary: 'Winter Solstice Air-Gap Retreat',
        start: start,
        isAllDay: true,
      );

      final ical = service.serializeCalendar(payload);
      expect(ical, contains('DTSTART;VALUE=DATE:20261225'));

      final restored = service.deserializeCalendar(ical);
      expect(restored.isAllDay, isTrue);
      expect(restored.start.year, equals(2026));
      expect(restored.start.month, equals(12));
      expect(restored.start.day, equals(25));
    });

    test('Folds long event descriptions at 75 octets', () {
      final longDesc = 'Important zero-trust operational briefing. ' * 5;
      final payload = CalendarEventPayload(
        summary: 'Briefing',
        description: longDesc,
        start: DateTime.utc(2026, 10, 30, 9, 0),
      );

      final ical = service.serializeCalendar(payload);
      expect(ical, contains('\r\n ')); // Confirms line folding

      final restored = service.deserializeCalendar(ical);
      expect(restored.description, equals(longDesc));
    });

    test('Throws on event invariant violations', () {
      // Empty title
      final emptySummary = CalendarEventPayload(
        summary: '   ',
        start: DateTime.now(),
      );
      expect(
          () => service.serializeCalendar(emptySummary), throwsArgumentError);

      // End time before start time
      final invertedTimes = CalendarEventPayload(
        summary: 'Time Travel Anomaly',
        start: DateTime.now(),
        end: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(
          () => service.serializeCalendar(invertedTimes), throwsArgumentError);
    });
  });
}
