import 'package:equatable/equatable.dart';

/// Supported Wi-Fi Authentication Security Types.
enum WifiSecurityType {
  wpa('WPA'),
  wpa2('WPA2'),
  wpa3('WPA3'),
  wep('WEP'),
  nopass('nopass');

  final String wireValue;
  const WifiSecurityType(this.wireValue);

  static WifiSecurityType fromWireValue(String value) {
    final upper = value.toUpperCase().trim();
    if (upper == 'WPA2' || upper == 'WPA2-PSK') return WifiSecurityType.wpa2;
    if (upper == 'WPA3' || upper == 'WPA3-SAE') return WifiSecurityType.wpa3;
    if (upper == 'WPA' || upper == 'WPA-PSK') return WifiSecurityType.wpa;
    if (upper == 'WEP') return WifiSecurityType.wep;
    if (upper == 'NOPASS' || upper == 'NONE' || upper.isEmpty) {
      return WifiSecurityType.nopass;
    }
    return WifiSecurityType.wpa;
  }
}

/// Pure Domain Entity representing a Wi-Fi Network Configuration.
class WifiConfigPayload extends Equatable {
  final String ssid;
  final WifiSecurityType securityType;
  final String? password;
  final bool isHidden;
  final String? eapMethod;

  const WifiConfigPayload({
    required this.ssid,
    this.securityType = WifiSecurityType.wpa,
    this.password,
    this.isHidden = false,
    this.eapMethod,
  });

  /// Invariant validations according to IEEE 802.11 standards.
  void validateInvariants() {
    if (ssid.isEmpty) {
      throw ArgumentError('SSID cannot be empty');
    }
    if (ssid.length > 32) {
      throw ArgumentError(
        'SSID exceeds maximum 32 octets (802.11 standard): ${ssid.length}',
      );
    }
    if (securityType != WifiSecurityType.nopass) {
      if (password == null || password!.isEmpty) {
        throw ArgumentError(
          'Password is required for ${securityType.wireValue} networks',
        );
      }
      if (securityType == WifiSecurityType.wpa ||
          securityType == WifiSecurityType.wpa2 ||
          securityType == WifiSecurityType.wpa3) {
        if (password!.length < 8 || password!.length > 64) {
          throw ArgumentError(
            'WPA/WPA2/WPA3 passphrases must be between 8 and 63 characters (or 64 hex)',
          );
        }
      }
    }
  }

  @override
  List<Object?> get props =>
      [ssid, securityType, password, isHidden, eapMethod];
}

/// Pure Domain Entity representing an RFC 5870 Geolocation coordinate.
class GeoLocationPayload extends Equatable {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? uncertainty;

  const GeoLocationPayload({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.uncertainty,
  });

  /// Invariant verification per WGS 84 / RFC 5870.
  void validateInvariants() {
    if (latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError('Latitude must be between -90.0 and 90.0: $latitude');
    }
    if (longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError(
          'Longitude must be between -180.0 and 180.0: $longitude');
    }
    if (uncertainty != null && uncertainty! < 0.0) {
      throw ArgumentError(
          'Uncertainty radius must be non-negative: $uncertainty');
    }
  }

  @override
  List<Object?> get props => [latitude, longitude, altitude, uncertainty];
}

/// Pure Domain Entity representing an RFC 5545 iCalendar VEVENT entry.
class CalendarEventPayload extends Equatable {
  final String? uid;
  final String summary;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime? end;
  final bool isAllDay;
  final String? url;

  const CalendarEventPayload({
    this.uid,
    required this.summary,
    this.description,
    this.location,
    required this.start,
    this.end,
    this.isAllDay = false,
    this.url,
  });

  /// Invariant validation
  void validateInvariants() {
    if (summary.trim().isEmpty) {
      throw ArgumentError('Event summary (title) cannot be empty');
    }
    if (end != null && end!.isBefore(start)) {
      throw ArgumentError('Event end time cannot be before start time');
    }
  }

  @override
  List<Object?> get props => [
        uid,
        summary,
        description,
        location,
        start,
        end,
        isAllDay,
        url,
      ];
}
