import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../entities/infrastructure_payload.dart';

/// Pure Domain Serializer for Network & Infrastructure Payloads (Wi-Fi, RFC 5870 Geo, RFC 5545 iCalendar).
class InfrastructureSerializerService {
  static const int maxLineOctets = 75;
  final Uuid _uuid;

  InfrastructureSerializerService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  // ===========================================================================
  // 1. WI-FI NETWORK SERIALIZATION (ZXing Standard)
  // ===========================================================================

  /// Serializes a [WifiConfigPayload] into standard ZXing Wi-Fi QR syntax:
  /// `WIFI:T:WPA;S:MySSID;P:MyPassword;H:false;;`
  String serializeWifi(WifiConfigPayload payload) {
    payload.validateInvariants();

    final buffer = StringBuffer('WIFI:');

    // Security Type (T)
    buffer.write('T:${payload.securityType.wireValue};');

    // SSID (S)
    buffer.write('S:${_escapeWifi(payload.ssid)};');

    // Password (P)
    if (payload.securityType != WifiSecurityType.nopass &&
        payload.password != null) {
      buffer.write('P:${_escapeWifi(payload.password!)};');
    }

    // Hidden Network (H)
    if (payload.isHidden) {
      buffer.write('H:true;');
    }

    // EAP Method (E) if applicable
    if (payload.eapMethod != null && payload.eapMethod!.isNotEmpty) {
      buffer.write('E:${_escapeWifi(payload.eapMethod!)};');
    }

    // Trailing double semicolon per ZXing specification
    buffer.write(';');

    return buffer.toString();
  }

  /// Deserializes raw Wi-Fi syntax string into a [WifiConfigPayload].
  WifiConfigPayload deserializeWifi(String rawWifi) {
    final trimmed = rawWifi.trim();
    if (!trimmed.toUpperCase().startsWith('WIFI:')) {
      throw const FormatException(
          'Invalid Wi-Fi QR format: must start with WIFI:');
    }

    // Strip 'WIFI:' prefix and trailing ';;' or ';'
    var content = trimmed.substring(5);
    while (content.endsWith(';')) {
      content = content.substring(0, content.length - 1);
    }

    final tokens = _splitUnescaped(content, ';');

    String? ssid;
    var securityType = WifiSecurityType.nopass;
    String? password;
    var isHidden = false;
    String? eapMethod;

    for (final token in tokens) {
      if (token.isEmpty) continue;
      final colonIdx = token.indexOf(':');
      if (colonIdx == -1) continue;

      final key = token.substring(0, colonIdx).trim().toUpperCase();
      final val = token.substring(colonIdx + 1);

      switch (key) {
        case 'S':
          ssid = _unescapeWifi(val);
          break;
        case 'T':
          securityType = WifiSecurityType.fromWireValue(_unescapeWifi(val));
          break;
        case 'P':
          password = _unescapeWifi(val);
          break;
        case 'H':
          isHidden = val.toLowerCase() == 'true';
          break;
        case 'E':
          eapMethod = _unescapeWifi(val);
          break;
      }
    }

    if (ssid == null || ssid.isEmpty) {
      throw const FormatException(
          'Missing required SSID (S:) field in Wi-Fi payload');
    }

    final payload = WifiConfigPayload(
      ssid: ssid,
      securityType: securityType,
      password: password,
      isHidden: isHidden,
      eapMethod: eapMethod,
    );
    payload.validateInvariants();
    return payload;
  }

  // ===========================================================================
  // 2. GEOLOCATION SERIALIZATION (RFC 5870)
  // ===========================================================================

  /// Serializes a [GeoLocationPayload] into an RFC 5870 URI:
  /// `geo:latitude,longitude[,altitude][;u=uncertainty]`
  String serializeGeo(GeoLocationPayload payload) {
    payload.validateInvariants();

    final buffer = StringBuffer('geo:');
    buffer.write('${payload.latitude},${payload.longitude}');

    if (payload.altitude != null) {
      buffer.write(',${payload.altitude}');
    }

    if (payload.uncertainty != null) {
      buffer.write(';u=${payload.uncertainty}');
    }

    return buffer.toString();
  }

  /// Deserializes an RFC 5870 URI into a [GeoLocationPayload].
  GeoLocationPayload deserializeGeo(String rawGeo) {
    final trimmed = rawGeo.trim();
    if (!trimmed.toLowerCase().startsWith('geo:')) {
      throw const FormatException('Invalid Geo URI: must start with geo:');
    }

    final body = trimmed.substring(4);
    final paramParts = body.split(';');
    final coordParts = paramParts[0].split(',');

    if (coordParts.length < 2) {
      throw const FormatException(
          'Geo URI must contain at least latitude and longitude');
    }

    final lat = double.tryParse(coordParts[0].trim());
    final lon = double.tryParse(coordParts[1].trim());

    if (lat == null || lon == null) {
      throw const FormatException('Invalid floating-point coordinate values');
    }

    double? alt;
    if (coordParts.length > 2 && coordParts[2].trim().isNotEmpty) {
      alt = double.tryParse(coordParts[2].trim());
    }

    double? uncertainty;
    for (var i = 1; i < paramParts.length; i++) {
      final p = paramParts[i].trim();
      if (p.toLowerCase().startsWith('u=')) {
        uncertainty = double.tryParse(p.substring(2).trim());
      }
    }

    final payload = GeoLocationPayload(
      latitude: lat,
      longitude: lon,
      altitude: alt,
      uncertainty: uncertainty,
    );
    payload.validateInvariants();
    return payload;
  }

  // ===========================================================================
  // 3. iCALENDAR EVENT SERIALIZATION (RFC 5545)
  // ===========================================================================

  /// Serializes a [CalendarEventPayload] into an RFC 5545 iCalendar VEVENT structure.
  String serializeCalendar(CalendarEventPayload payload) {
    payload.validateInvariants();

    final lines = <String>[];
    lines.add('BEGIN:VCALENDAR');
    lines.add('VERSION:2.0');
    lines.add('PRODID:-//ZeroSync//AirDrop-QR//EN');
    lines.add('BEGIN:VEVENT');

    // UID
    final uid = payload.uid ?? _uuid.v4();
    lines.add('UID:$uid');

    // DTSTAMP (Current UTC)
    lines.add('DTSTAMP:${_formatDateTimeUtc(DateTime.now().toUtc())}');

    // DTSTART
    if (payload.isAllDay) {
      lines.add('DTSTART;VALUE=DATE:${_formatDateOnly(payload.start)}');
    } else {
      lines.add('DTSTART:${_formatDateTimeUtc(payload.start.toUtc())}');
    }

    // DTEND
    if (payload.end != null) {
      if (payload.isAllDay) {
        lines.add('DTEND;VALUE=DATE:${_formatDateOnly(payload.end!)}');
      } else {
        lines.add('DTEND:${_formatDateTimeUtc(payload.end!.toUtc())}');
      }
    }

    // SUMMARY
    lines.add('SUMMARY:${_escapeICal(payload.summary)}');

    // DESCRIPTION
    if (payload.description != null && payload.description!.isNotEmpty) {
      lines.add('DESCRIPTION:${_escapeICal(payload.description!)}');
    }

    // LOCATION
    if (payload.location != null && payload.location!.isNotEmpty) {
      lines.add('LOCATION:${_escapeICal(payload.location!)}');
    }

    // URL
    if (payload.url != null && payload.url!.isNotEmpty) {
      lines.add('URL:${_escapeICal(payload.url!)}');
    }

    lines.add('END:VEVENT');
    lines.add('END:VCALENDAR');

    // Apply RFC 5545 Line Folding (75 octets) with CRLF endings
    final buffer = StringBuffer();
    for (final line in lines) {
      buffer.write(_foldLine(line));
      buffer.write('\r\n');
    }

    return buffer.toString();
  }

  /// Deserializes raw iCalendar text into a [CalendarEventPayload].
  CalendarEventPayload deserializeCalendar(String rawICal) {
    final unfolded = _unfoldLines(rawICal);
    if (unfolded.isEmpty) {
      throw const FormatException('Empty iCalendar content');
    }

    String? uid;
    String? summary;
    String? description;
    String? location;
    DateTime? start;
    DateTime? end;
    var isAllDay = false;
    String? url;

    for (final line in unfolded) {
      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) continue;

      final keyPart = line.substring(0, colonIdx).trim().toUpperCase();
      final valPart = line.substring(colonIdx + 1);
      final propName = keyPart.split(';')[0];

      if (propName == 'UID') {
        uid = valPart;
      } else if (propName == 'SUMMARY') {
        summary = _unescapeICal(valPart);
      } else if (propName == 'DESCRIPTION') {
        description = _unescapeICal(valPart);
      } else if (propName == 'LOCATION') {
        location = _unescapeICal(valPart);
      } else if (propName == 'URL') {
        url = _unescapeICal(valPart);
      } else if (propName == 'DTSTART') {
        isAllDay = keyPart.contains('VALUE=DATE');
        start = _parseICalDateTime(valPart, isAllDay: isAllDay);
      } else if (propName == 'DTEND') {
        end = _parseICalDateTime(valPart, isAllDay: isAllDay);
      }
    }

    if (summary == null || summary.trim().isEmpty) {
      throw const FormatException(
          'Missing required SUMMARY property in VEVENT');
    }
    if (start == null) {
      throw const FormatException(
          'Missing required DTSTART property in VEVENT');
    }

    final payload = CalendarEventPayload(
      uid: uid,
      summary: summary,
      description: description,
      location: location,
      start: start,
      end: end,
      isAllDay: isAllDay,
      url: url,
    );
    payload.validateInvariants();
    return payload;
  }

  // ===========================================================================
  // PRIVATE HELPER ROUTINES
  // ===========================================================================

  static String _escapeWifi(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll(':', r'\:')
        .replaceAll('"', r'\"');
  }

  static String _unescapeWifi(String text) {
    return text
        .replaceAll(r'\"', '"')
        .replaceAll(r'\:', ':')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\');
  }

  static String _escapeICal(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\r', r'\n')
        .replaceAll('\n', r'\n');
  }

  static String _unescapeICal(String text) {
    return text
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\');
  }

  static String _formatDateTimeUtc(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min${s}Z';
  }

  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static DateTime _parseICalDateTime(String value, {required bool isAllDay}) {
    final trimmed = value.trim();
    if (isAllDay || trimmed.length == 8) {
      final y = int.parse(trimmed.substring(0, 4));
      final m = int.parse(trimmed.substring(4, 6));
      final d = int.parse(trimmed.substring(6, 8));
      return DateTime.utc(y, m, d);
    }

    final isUtc = trimmed.endsWith('Z');
    final raw = isUtc ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    final parts = raw.split('T');
    final datePart = parts[0];
    final timePart = parts.length > 1 ? parts[1] : '000000';

    final y = int.parse(datePart.substring(0, 4));
    final m = int.parse(datePart.substring(4, 6));
    final d = int.parse(datePart.substring(6, 8));

    final h = int.parse(timePart.substring(0, 2));
    final min = int.parse(timePart.substring(2, 4));
    final s = timePart.length >= 6 ? int.parse(timePart.substring(4, 6)) : 0;

    if (isUtc) {
      return DateTime.utc(y, m, d, h, min, s);
    }
    return DateTime(y, m, d, h, min, s);
  }

  static List<String> _splitUnescaped(String text, String delimiter) {
    final result = <String>[];
    final current = StringBuffer();
    var isEscaped = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (isEscaped) {
        current.write(char);
        isEscaped = false;
      } else if (char == r'\') {
        current.write(char);
        isEscaped = true;
      } else if (char == delimiter) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  static String _foldLine(String line) {
    final utf8Bytes = utf8.encode(line);
    if (utf8Bytes.length <= maxLineOctets) {
      return line;
    }

    final buffer = StringBuffer();
    var currentLineBytes = <int>[];

    for (var i = 0; i < utf8Bytes.length; i++) {
      currentLineBytes.add(utf8Bytes[i]);
      final limit = buffer.isEmpty ? maxLineOctets : (maxLineOctets - 1);
      if (currentLineBytes.length >= limit && i < utf8Bytes.length - 1) {
        if (_isUtf8CharBoundary(utf8Bytes, i + 1)) {
          if (buffer.isNotEmpty) {
            buffer.write('\r\n ');
          }
          buffer.write(utf8.decode(currentLineBytes));
          currentLineBytes = [];
        }
      }
    }

    if (currentLineBytes.isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.write('\r\n ');
      }
      buffer.write(utf8.decode(currentLineBytes));
    }

    return buffer.toString();
  }

  static bool _isUtf8CharBoundary(List<int> bytes, int index) {
    if (index >= bytes.length) return true;
    final byte = bytes[index];
    return (byte & 0xC0) != 0x80;
  }

  static List<String> _unfoldLines(String raw) {
    final normalized = raw
        .replaceAll('\r\n ', '')
        .replaceAll('\r\n\t', '')
        .replaceAll('\n ', '')
        .replaceAll('\n\t', '');
    return normalized
        .split(RegExp(r'\r?\n'))
        .where((l) => l.isNotEmpty)
        .toList();
  }
}
