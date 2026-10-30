import 'package:airdrop_qr/domain/entities/infrastructure_payload.dart';
import 'package:airdrop_qr/domain/entities/vcard_payload.dart';
import 'package:airdrop_qr/domain/services/native_intent_dispatcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntentDispatchResult Entity Specs', () {
    test('Constructs success and failure results with accurate properties', () {
      final success = IntentDispatchResult.success(
        action: 'connectWifi',
        payload: {'ssid': 'TestNet'},
      );
      expect(success.isSuccess, isTrue);
      expect(success.action, equals('connectWifi'));
      expect(success.payload['ssid'], equals('TestNet'));
      expect(success.errorMessage, isNull);
      expect(success.toString(), contains('success: true'));

      final failure = IntentDispatchResult.failure(
        action: 'connectWifi',
        payload: {'ssid': 'TestNet'},
        message: 'User rejected permission',
      );
      expect(failure.isSuccess, isFalse);
      expect(failure.errorMessage, equals('User rejected permission'));
      expect(failure.toString(), contains('User rejected permission'));
    });
  });

  group('Wi-Fi Native Connection Intent Dispatcher', () {
    test('Dispatches valid Wi-Fi connection payload to platform channel',
        () async {
      String? invokedMethod;
      dynamic invokedArgs;

      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          invokedMethod = method;
          invokedArgs = args;
          return true;
        },
      );

      const wifi = WifiConfigPayload(
        ssid: 'ZeroSync-AirGap',
        securityType: WifiSecurityType.wpa,
        password: 'SuperSecretPassword',
        isHidden: true,
      );

      final result = await dispatcher.promptWifiConnection(wifi);

      expect(result.isSuccess, isTrue);
      expect(invokedMethod, equals('connectWifi'));
      expect(invokedArgs, isA<Map<String, dynamic>>());
      final map = invokedArgs as Map<String, dynamic>;
      expect(map['ssid'], equals('ZeroSync-AirGap'));
      expect(map['securityType'], equals('wpa'));
      expect(map['password'], equals('SuperSecretPassword'));
      expect(map['isHidden'], isTrue);
    });

    test(
        'Fails immediately when SSID is empty without invoking platform channel',
        () async {
      bool wasInvoked = false;
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          wasInvoked = true;
          return true;
        },
      );

      const invalidWifi = WifiConfigPayload(
        ssid: '   ',
        securityType: WifiSecurityType.nopass,
      );

      final result = await dispatcher.promptWifiConnection(invalidWifi);

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('SSID cannot be empty'));
      expect(wasInvoked, isFalse);
    });

    test('Handles native channel rejection or platform exceptions gracefully',
        () async {
      final dispatcherReject = NativeIntentDispatcher(
        invoker: (method, [args]) async => false,
      );

      final resultReject = await dispatcherReject.promptWifiConnection(
        const WifiConfigPayload(
            ssid: 'Office-LAN', securityType: WifiSecurityType.wpa),
      );
      expect(resultReject.isSuccess, isFalse);
      expect(resultReject.errorMessage, contains('rejected or cancelled'));

      final dispatcherThrow = NativeIntentDispatcher(
        invoker: (method, [args]) async => throw PlatformException(
            code: 'WIFI_UNAVAILABLE', message: 'Radio off'),
      );

      final resultThrow = await dispatcherThrow.promptWifiConnection(
        const WifiConfigPayload(
            ssid: 'Office-LAN', securityType: WifiSecurityType.wpa),
      );
      expect(resultThrow.isSuccess, isFalse);
      expect(resultThrow.errorMessage, contains('Radio off'));
    });
  });

  group('Native Contact Saving Intent Dispatcher', () {
    test('Dispatches rich vCard contact payload to platform channel', () async {
      String? invokedMethod;
      dynamic invokedArgs;

      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          invokedMethod = method;
          invokedArgs = args;
          return true;
        },
      );

      const contact = VCardPayload(
        formattedName: 'Ada Lovelace',
        familyName: 'Lovelace',
        givenName: 'Ada',
        organization: 'Analytical Computing',
        jobTitle: 'Chief Mathematician',
        phones: [
          ContactPhone(number: '+18005550100', types: ['WORK', 'VOICE']),
        ],
        emails: [
          ContactEmail(address: 'ada@computing.org', types: ['WORK']),
        ],
        urls: ['https://lovelace.org'],
        note: 'Pioneer of Computer Programming',
      );

      final result = await dispatcher.saveContact(contact);

      expect(result.isSuccess, isTrue);
      expect(invokedMethod, equals('insertContact'));
      final map = invokedArgs as Map<String, dynamic>;
      expect(map['formattedName'], equals('Ada Lovelace'));
      expect(map['organization'], equals('Analytical Computing'));
      expect(map['title'], equals('Chief Mathematician'));
      expect(map['phones'], isA<List<dynamic>>());
      expect(map['emails'], isA<List<dynamic>>());
    });

    test('Fails when formattedName and givenName are both empty', () async {
      bool wasInvoked = false;
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          wasInvoked = true;
          return true;
        },
      );

      const emptyContact = VCardPayload(
        formattedName: '',
        givenName: '  ',
      );

      final result = await dispatcher.saveContact(emptyContact);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage,
          contains('non-empty formattedName or givenName'));
      expect(wasInvoked, isFalse);
    });

    test('Captures contact saving platform exception cleanly', () async {
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async => throw PlatformException(
            code: 'PERMISSION_DENIED', message: 'Contacts access denied'),
      );

      final result = await dispatcher.saveContact(
        const VCardPayload(formattedName: 'Grace Hopper'),
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Contacts access denied'));
    });
  });

  group('Native Calendar Event Injection Dispatcher', () {
    test('Dispatches valid calendar event payload with UTC epoch bounds',
        () async {
      String? invokedMethod;
      dynamic invokedArgs;

      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          invokedMethod = method;
          invokedArgs = args;
          return true;
        },
      );

      final start = DateTime(2026, 11, 1, 10, 0);
      final end = DateTime(2026, 11, 1, 11, 30);

      final event = CalendarEventPayload(
        summary: 'ZeroSync Architecture Review',
        description: 'Air-gap data transport sprint review',
        location: 'Room 404',
        start: start,
        end: end,
        isAllDay: false,
      );

      final result = await dispatcher.injectCalendarEvent(event);

      expect(result.isSuccess, isTrue);
      expect(invokedMethod, equals('insertCalendarEvent'));
      final map = invokedArgs as Map<String, dynamic>;
      expect(map['title'], equals('ZeroSync Architecture Review'));
      expect(map['startEpochMs'], equals(start.millisecondsSinceEpoch));
      expect(map['endEpochMs'], equals(end.millisecondsSinceEpoch));
      expect(map['isAllDay'], isFalse);
    });

    test('Fails when calendar event summary is empty', () async {
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async => true,
      );

      final invalidEvent = CalendarEventPayload(
        summary: '',
        start: DateTime.now(),
      );

      final result = await dispatcher.injectCalendarEvent(invalidEvent);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('summary cannot be empty'));
    });

    test('Fails when calendar event end time is prior to start time', () async {
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async => true,
      );

      final now = DateTime.now();
      final invalidEvent = CalendarEventPayload(
        summary: 'Backwards Event',
        start: now,
        end: now.subtract(const Duration(hours: 1)),
      );

      final result = await dispatcher.injectCalendarEvent(invalidEvent);
      expect(result.isSuccess, isFalse);
      expect(
          result.errorMessage, contains('end time cannot precede start time'));
    });
  });

  group('Geolocation Navigation Dispatcher', () {
    test('Dispatches valid coordinates and label to native maps', () async {
      String? invokedMethod;
      dynamic invokedArgs;

      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          invokedMethod = method;
          invokedArgs = args;
          return true;
        },
      );

      const geo = GeoLocationPayload(
        latitude: 37.4220,
        longitude: -122.0841,
        altitude: 10.5,
        uncertainty: 2.0,
      );

      final result =
          await dispatcher.launchGeoLocation(geo, label: 'Googleplex HQ');

      expect(result.isSuccess, isTrue);
      expect(invokedMethod, equals('openGeoLocation'));
      final map = invokedArgs as Map<String, dynamic>;
      expect(map['latitude'], equals(37.4220));
      expect(map['longitude'], equals(-122.0841));
      expect(map['label'], equals('Googleplex HQ'));
    });

    test('Validates latitude and longitude coordinate boundaries', () async {
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async => true,
      );

      const invalidLat = GeoLocationPayload(latitude: 95.0, longitude: 0.0);
      final resLat = await dispatcher.launchGeoLocation(invalidLat);
      expect(resLat.isSuccess, isFalse);
      expect(resLat.errorMessage, contains('Invalid latitude range'));

      const invalidLon = GeoLocationPayload(latitude: 0.0, longitude: -190.0);
      final resLon = await dispatcher.launchGeoLocation(invalidLon);
      expect(resLon.isSuccess, isFalse);
      expect(resLon.errorMessage, contains('Invalid longitude range'));
    });
  });

  group('Sanitized Web Navigation Dispatcher', () {
    test('Dispatches valid HTTPS URL to in-app secure browser', () async {
      String? invokedMethod;
      dynamic invokedArgs;

      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          invokedMethod = method;
          invokedArgs = args;
          return true;
        },
      );

      final result = await dispatcher.openSanitizedUrl(
        'https://docs.flutter.dev/ui',
        requireInAppBrowser: true,
      );

      expect(result.isSuccess, isTrue);
      expect(invokedMethod, equals('openUrl'));
      final map = invokedArgs as Map<String, dynamic>;
      expect(map['url'], equals('https://docs.flutter.dev/ui'));
      expect(map['requireInAppBrowser'], isTrue);
    });

    test('Rejects dangerous or non-HTTP schemes (javascript, file, tel)',
        () async {
      bool wasInvoked = false;
      final dispatcher = NativeIntentDispatcher(
        invoker: (method, [args]) async {
          wasInvoked = true;
          return true;
        },
      );

      final resultJs = await dispatcher.openSanitizedUrl('javascript:alert(1)');
      expect(resultJs.isSuccess, isFalse);
      expect(resultJs.errorMessage,
          contains('Only HTTP/HTTPS URLs are permitted'));

      final resultFile = await dispatcher.openSanitizedUrl('file:///etc/hosts');
      expect(resultFile.isSuccess, isFalse);

      expect(wasInvoked, isFalse);
    });
  });
}
