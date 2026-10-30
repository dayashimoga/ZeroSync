import 'dart:async';

import 'package:airdrop_qr/domain/entities/infrastructure_payload.dart';
import 'package:airdrop_qr/domain/entities/vcard_payload.dart';
import 'package:flutter/services.dart';

/// Structured outcome of a native platform intent dispatch.
class IntentDispatchResult {
  /// Whether the native platform accepted and initiated the requested intent.
  final bool isSuccess;

  /// Identifier of the intent action dispatched (e.g. `connectWifi`, `insertContact`).
  final String action;

  /// Serialized parameters passed to the platform bridge.
  final Map<String, dynamic> payload;

  /// Platform error message or reason if the dispatch failed or was dismissed.
  final String? errorMessage;

  /// Timestamp when the intent invocation concluded.
  final DateTime timestamp;

  const IntentDispatchResult({
    required this.isSuccess,
    required this.action,
    required this.payload,
    this.errorMessage,
    required this.timestamp,
  });

  /// Factory for a successful dispatch.
  factory IntentDispatchResult.success({
    required String action,
    required Map<String, dynamic> payload,
  }) {
    return IntentDispatchResult(
      isSuccess: true,
      action: action,
      payload: payload,
      timestamp: DateTime.now(),
    );
  }

  /// Factory for a rejected, failed, or cancelled intent dispatch.
  factory IntentDispatchResult.failure({
    required String action,
    required Map<String, dynamic> payload,
    required String message,
  }) {
    return IntentDispatchResult(
      isSuccess: false,
      action: action,
      payload: payload,
      errorMessage: message,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'IntentDispatchResult(action: $action, success: $isSuccess, error: ${errorMessage ?? "none"})';
}

/// Pluggable channel invoker signature to facilitate deterministic unit testing without a live OS.
typedef PlatformChannelInvoker = Future<dynamic> Function(
  String method, [
  dynamic arguments,
]);

/// High-integrity, zero-trust intent dispatcher routing sanitized QR payloads to native OS actions.
///
/// Features:
/// - Prompts OS Wi-Fi network configuration (Android `NetworkSpecifier` / iOS `NEHotspotConfiguration`).
/// - Injects contacts into the native address book (Android `Intent.ACTION_INSERT` / iOS `CNContactViewController`).
/// - Schedules events in the native calendar (Android `CalendarContract` / iOS `EventKit`).
/// - Launches native mapping apps for geolocation coordinates without remote tracking.
/// - Opens sanitized, tracker-free URLs in secure in-app sandboxed browsers.
class NativeIntentDispatcher {
  /// Channel identifier for native intent bridge.
  static const String channelName = 'com.zerosync.airdrop_qr/native_intents';

  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  final PlatformChannelInvoker _invoker;

  /// Creates a dispatcher with the specified channel [invoker], defaulting to standard [MethodChannel].
  NativeIntentDispatcher({PlatformChannelInvoker? invoker})
      : _invoker = invoker ?? _defaultChannel.invokeMethod;

  /// Dispatches a native Wi-Fi connection prompt for [wifi].
  ///
  /// Passes SSID, security standard, password, and hidden network configuration to the OS.
  Future<IntentDispatchResult> promptWifiConnection(
      WifiConfigPayload wifi) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'ssid': wifi.ssid,
      'securityType': wifi.securityType.name,
      'password': wifi.password ?? '',
      'isHidden': wifi.isHidden,
      'eapMethod': wifi.eapMethod ?? '',
    };

    try {
      if (wifi.ssid.trim().isEmpty) {
        return IntentDispatchResult.failure(
          action: 'connectWifi',
          payload: payload,
          message: 'Wi-Fi SSID cannot be empty',
        );
      }

      final dynamic result = await _invoker('connectWifi', payload);
      final bool success = result is bool ? result : true;

      return success
          ? IntentDispatchResult.success(
              action: 'connectWifi', payload: payload)
          : IntentDispatchResult.failure(
              action: 'connectWifi',
              payload: payload,
              message:
                  'Native Wi-Fi configuration was rejected or cancelled by user',
            );
    } catch (e) {
      return IntentDispatchResult.failure(
        action: 'connectWifi',
        payload: payload,
        message: e.toString(),
      );
    }
  }

  /// Dispatches a native contact creation intent for [contact].
  Future<IntentDispatchResult> saveContact(VCardPayload contact) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'formattedName': contact.formattedName,
      'familyName': contact.familyName ?? '',
      'givenName': contact.givenName ?? '',
      'organization': contact.organization ?? '',
      'title': contact.jobTitle ?? '',
      'phones': contact.phones
          .map((p) => <String, dynamic>{
                'number': p.number,
                'types': p.types,
              })
          .toList(),
      'emails': contact.emails
          .map((e) => <String, dynamic>{
                'address': e.address,
                'types': e.types,
              })
          .toList(),
      'note': contact.note ?? '',
      'urls': contact.urls,
    };

    try {
      if (contact.formattedName.trim().isEmpty &&
          (contact.givenName == null || contact.givenName!.trim().isEmpty)) {
        return IntentDispatchResult.failure(
          action: 'insertContact',
          payload: payload,
          message: 'Contact must have a non-empty formattedName or givenName',
        );
      }

      final dynamic result = await _invoker('insertContact', payload);
      final bool success = result is bool ? result : true;

      return success
          ? IntentDispatchResult.success(
              action: 'insertContact', payload: payload)
          : IntentDispatchResult.failure(
              action: 'insertContact',
              payload: payload,
              message: 'Native contact saving intent failed or was dismissed',
            );
    } catch (e) {
      return IntentDispatchResult.failure(
        action: 'insertContact',
        payload: payload,
        message: e.toString(),
      );
    }
  }

  /// Dispatches a native calendar event creation intent for [calendar].
  Future<IntentDispatchResult> injectCalendarEvent(
      CalendarEventPayload calendar) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'title': calendar.summary,
      'description': calendar.description ?? '',
      'location': calendar.location ?? '',
      'startEpochMs': calendar.start.millisecondsSinceEpoch,
      'endEpochMs': calendar.end?.millisecondsSinceEpoch,
      'isAllDay': calendar.isAllDay,
    };

    try {
      if (calendar.summary.trim().isEmpty) {
        return IntentDispatchResult.failure(
          action: 'insertCalendarEvent',
          payload: payload,
          message: 'Calendar event summary cannot be empty',
        );
      }

      if (calendar.end != null && calendar.end!.isBefore(calendar.start)) {
        return IntentDispatchResult.failure(
          action: 'insertCalendarEvent',
          payload: payload,
          message: 'Calendar event end time cannot precede start time',
        );
      }

      final dynamic result = await _invoker('insertCalendarEvent', payload);
      final bool success = result is bool ? result : true;

      return success
          ? IntentDispatchResult.success(
              action: 'insertCalendarEvent',
              payload: payload,
            )
          : IntentDispatchResult.failure(
              action: 'insertCalendarEvent',
              payload: payload,
              message: 'Native calendar insertion was rejected or cancelled',
            );
    } catch (e) {
      return IntentDispatchResult.failure(
        action: 'insertCalendarEvent',
        payload: payload,
        message: e.toString(),
      );
    }
  }

  /// Dispatches a geolocation coordinate intent to the native map application for [geo].
  Future<IntentDispatchResult> launchGeoLocation(
    GeoLocationPayload geo, {
    String? label,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'latitude': geo.latitude,
      'longitude': geo.longitude,
      'altitude': geo.altitude,
      'uncertainty': geo.uncertainty,
      'label': label ?? '',
    };

    try {
      if (geo.latitude < -90.0 || geo.latitude > 90.0) {
        return IntentDispatchResult.failure(
          action: 'openGeoLocation',
          payload: payload,
          message: 'Invalid latitude range (must be between -90 and 90)',
        );
      }

      if (geo.longitude < -180.0 || geo.longitude > 180.0) {
        return IntentDispatchResult.failure(
          action: 'openGeoLocation',
          payload: payload,
          message: 'Invalid longitude range (must be between -180 and 180)',
        );
      }

      final dynamic result = await _invoker('openGeoLocation', payload);
      final bool success = result is bool ? result : true;

      return success
          ? IntentDispatchResult.success(
              action: 'openGeoLocation',
              payload: payload,
            )
          : IntentDispatchResult.failure(
              action: 'openGeoLocation',
              payload: payload,
              message: 'Native mapping application could not be launched',
            );
    } catch (e) {
      return IntentDispatchResult.failure(
        action: 'openGeoLocation',
        payload: payload,
        message: e.toString(),
      );
    }
  }

  /// Dispatches a secure web navigation intent for [sanitizedUrl].
  Future<IntentDispatchResult> openSanitizedUrl(
    String sanitizedUrl, {
    bool requireInAppBrowser = true,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'url': sanitizedUrl,
      'requireInAppBrowser': requireInAppBrowser,
    };

    try {
      final Uri? uri = Uri.tryParse(sanitizedUrl);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return IntentDispatchResult.failure(
          action: 'openUrl',
          payload: payload,
          message: 'Only HTTP/HTTPS URLs are permitted for native web dispatch',
        );
      }

      final dynamic result = await _invoker('openUrl', payload);
      final bool success = result is bool ? result : true;

      return success
          ? IntentDispatchResult.success(action: 'openUrl', payload: payload)
          : IntentDispatchResult.failure(
              action: 'openUrl',
              payload: payload,
              message: 'Native browser intent launch failed or was dismissed',
            );
    } catch (e) {
      return IntentDispatchResult.failure(
        action: 'openUrl',
        payload: payload,
        message: e.toString(),
      );
    }
  }
}
