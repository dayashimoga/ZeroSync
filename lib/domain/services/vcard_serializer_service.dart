import 'dart:convert';
import '../entities/vcard_payload.dart';

/// Pure Domain Serializer for Universal Text, URIs, and RFC 6350 vCard 4.0.
class VCardSerializerService {
  static const int maxLineOctets = 75;

  /// Serializes a [VCardPayload] into an RFC 6350 compliant vCard 4.0 string.
  String serializeVCard4(VCardPayload payload) {
    payload.validateInvariants();
    final lines = <String>[];

    lines.add('BEGIN:VCARD');
    lines.add('VERSION:4.0');

    // Mandatory Formatted Name (FN)
    lines.add('FN:${_escapeText(payload.formattedName)}');

    // Structured Name (N)
    final hasStructuredName = payload.familyName != null ||
        payload.givenName != null ||
        payload.additionalNames != null ||
        payload.prefix != null ||
        payload.suffix != null;

    if (hasStructuredName) {
      final family = _escapeText(payload.familyName ?? '');
      final given = _escapeText(payload.givenName ?? '');
      final additional = _escapeText(payload.additionalNames ?? '');
      final prefix = _escapeText(payload.prefix ?? '');
      final suffix = _escapeText(payload.suffix ?? '');
      lines.add('N:$family;$given;$additional;$prefix;$suffix');
    }

    // Organization & Department (ORG)
    if (payload.organization != null) {
      var orgValue = _escapeText(payload.organization!);
      if (payload.department != null) {
        orgValue += ';${_escapeText(payload.department!)}';
      }
      lines.add('ORG:$orgValue');
    }

    // Job Title (TITLE)
    if (payload.jobTitle != null) {
      lines.add('TITLE:${_escapeText(payload.jobTitle!)}');
    }

    // Telephone Numbers (TEL)
    for (final phone in payload.phones) {
      final typeStr = phone.types.map((t) => t.toLowerCase()).join(',');
      final typeParam = typeStr.isNotEmpty ? ';TYPE=$typeStr' : '';
      lines.add('TEL$typeParam:${_escapeText(phone.number)}');
    }

    // Emails (EMAIL)
    for (final email in payload.emails) {
      final typeStr = email.types.map((t) => t.toLowerCase()).join(',');
      final typeParam = typeStr.isNotEmpty ? ';TYPE=$typeStr' : '';
      lines.add('EMAIL$typeParam:${_escapeText(email.address)}');
    }

    // Postal Addresses (ADR)
    for (final addr in payload.addresses) {
      final typeStr = addr.types.map((t) => t.toLowerCase()).join(',');
      final typeParam = typeStr.isNotEmpty ? ';TYPE=$typeStr' : '';
      final street = _escapeText(addr.street ?? '');
      final city = _escapeText(addr.city ?? '');
      final state = _escapeText(addr.state ?? '');
      final postal = _escapeText(addr.postalCode ?? '');
      final country = _escapeText(addr.country ?? '');
      // RFC 6350 ADR format: PO Box; Extended Address; Street; Locality (City); Region (State); Postal Code; Country
      lines.add('ADR$typeParam:;;$street;$city;$state;$postal;$country');
    }

    // URLs (URL)
    for (final url in payload.urls) {
      lines.add('URL:${_escapeText(url)}');
    }

    // Notes (NOTE)
    if (payload.note != null) {
      lines.add('NOTE:${_escapeText(payload.note!)}');
    }

    // Embedded Photo (PHOTO)
    if (payload.photoBase64 != null) {
      final sanitized = VCardPayload.sanitizeBase64(payload.photoBase64!);
      final mediaType = payload.photoMediaType ?? 'image/jpeg';
      lines.add('PHOTO;MEDIATYPE=$mediaType:data:$mediaType;base64,$sanitized');
    }

    lines.add('END:VCARD');

    // Apply RFC 6350 Line Folding (75 octets) with CRLF endings
    final buffer = StringBuffer();
    for (final line in lines) {
      buffer.write(_foldLine(line));
      buffer.write('\r\n');
    }

    return buffer.toString();
  }

  /// Deserializes a raw vCard string into a [VCardPayload].
  VCardPayload deserializeVCard4(String rawVcard) {
    final unfolded = _unfoldLines(rawVcard);
    if (unfolded.isEmpty) {
      throw const FormatException('Empty vCard content');
    }

    String? formattedName;
    String? familyName;
    String? givenName;
    String? additionalNames;
    String? prefix;
    String? suffix;
    String? organization;
    String? department;
    String? jobTitle;
    final phones = <ContactPhone>[];
    final emails = <ContactEmail>[];
    final addresses = <ContactAddress>[];
    final urls = <String>[];
    String? note;
    String? photoBase64;
    String? photoMediaType;

    for (final line in unfolded) {
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) continue;

      final keyPart = line.substring(0, colonIndex).trim().toUpperCase();
      final valuePart = line.substring(colonIndex + 1);
      final propName = keyPart.split(';')[0];

      if (propName == 'FN') {
        formattedName = _unescapeText(valuePart);
      } else if (propName == 'N') {
        final parts = _splitUnescaped(valuePart, ';');
        if (parts.isNotEmpty) familyName = _unescapeText(parts[0]);
        if (parts.length > 1) givenName = _unescapeText(parts[1]);
        if (parts.length > 2) additionalNames = _unescapeText(parts[2]);
        if (parts.length > 3) prefix = _unescapeText(parts[3]);
        if (parts.length > 4) suffix = _unescapeText(parts[4]);
      } else if (propName == 'ORG') {
        final parts = _splitUnescaped(valuePart, ';');
        if (parts.isNotEmpty) organization = _unescapeText(parts[0]);
        if (parts.length > 1) department = _unescapeText(parts[1]);
      } else if (propName == 'TITLE') {
        jobTitle = _unescapeText(valuePart);
      } else if (propName == 'TEL') {
        final types = _extractTypes(keyPart);
        phones.add(ContactPhone(
          number: _unescapeText(valuePart),
          types: types.isNotEmpty ? types : const ['cell'],
        ));
      } else if (propName == 'EMAIL') {
        final types = _extractTypes(keyPart);
        emails.add(ContactEmail(
          address: _unescapeText(valuePart),
          types: types.isNotEmpty ? types : const ['work'],
        ));
      } else if (propName == 'ADR') {
        final types = _extractTypes(keyPart);
        final parts = _splitUnescaped(valuePart, ';');
        // Indices: 2 = Street, 3 = City, 4 = State, 5 = PostalCode, 6 = Country
        String? street;
        String? city;
        String? state;
        String? postal;
        String? country;
        if (parts.length > 2 && parts[2].isNotEmpty) {
          street = _unescapeText(parts[2]);
        }
        if (parts.length > 3 && parts[3].isNotEmpty) {
          city = _unescapeText(parts[3]);
        }
        if (parts.length > 4 && parts[4].isNotEmpty) {
          state = _unescapeText(parts[4]);
        }
        if (parts.length > 5 && parts[5].isNotEmpty) {
          postal = _unescapeText(parts[5]);
        }
        if (parts.length > 6 && parts[6].isNotEmpty) {
          country = _unescapeText(parts[6]);
        }
        addresses.add(ContactAddress(
          street: street,
          city: city,
          state: state,
          postalCode: postal,
          country: country,
          types: types.isNotEmpty ? types : const ['work'],
        ));
      } else if (propName == 'URL') {
        urls.add(_unescapeText(valuePart));
      } else if (propName == 'NOTE') {
        note = _unescapeText(valuePart);
      } else if (propName == 'PHOTO') {
        photoMediaType = _extractMediaType(keyPart);
        photoBase64 = VCardPayload.sanitizeBase64(valuePart);
      }
    }

    if (formattedName == null || formattedName.trim().isEmpty) {
      throw const FormatException(
          'Missing required FN (Formatted Name) property');
    }

    final payload = VCardPayload(
      formattedName: formattedName,
      familyName: familyName?.isEmpty == true ? null : familyName,
      givenName: givenName?.isEmpty == true ? null : givenName,
      additionalNames:
          additionalNames?.isEmpty == true ? null : additionalNames,
      prefix: prefix?.isEmpty == true ? null : prefix,
      suffix: suffix?.isEmpty == true ? null : suffix,
      organization: organization?.isEmpty == true ? null : organization,
      department: department?.isEmpty == true ? null : department,
      jobTitle: jobTitle?.isEmpty == true ? null : jobTitle,
      phones: phones,
      emails: emails,
      addresses: addresses,
      urls: urls,
      note: note,
      photoBase64: photoBase64,
      photoMediaType: photoMediaType,
    );
    payload.validateInvariants();
    return payload;
  }

  /// Serializes and validates universal plain text with UTF-8 normalization.
  String serializeText(String input) {
    if (input.trim().isEmpty) {
      throw ArgumentError('Text payload cannot be empty');
    }
    // Normalize newlines to standard UNIX line-feeds
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Ensure UTF-8 encodeable
    utf8.encode(normalized);
    return normalized;
  }

  /// Serializes and validates an RFC 3986 URI.
  String serializeUri(Uri uri) {
    if (!uri.hasScheme || uri.scheme.isEmpty) {
      throw ArgumentError('URI must contain a valid scheme: $uri');
    }
    const permittedSchemes = {
      'https',
      'http',
      'mailto',
      'tel',
      'geo',
      'wifi',
      'otpauth'
    };
    if (!permittedSchemes.contains(uri.scheme.toLowerCase())) {
      throw ArgumentError(
          'Scheme "${uri.scheme}" is prohibited under air-gap safety policy');
    }
    return uri.toString();
  }

  // --- RFC 6350 Escaping & Folding Utilities ---

  static String _escapeText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(',', r'\,')
        .replaceAll(';', r'\;')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\r', r'\n')
        .replaceAll('\n', r'\n');
  }

  static String _unescapeText(String text) {
    return text
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\');
  }

  /// Folds lines longer than 75 octets by inserting CRLF followed by a space.
  static String _foldLine(String line) {
    final utf8Bytes = utf8.encode(line);
    if (utf8Bytes.length <= maxLineOctets) {
      return line;
    }

    final buffer = StringBuffer();
    var currentLineBytes = <int>[];

    for (var i = 0; i < utf8Bytes.length; i++) {
      currentLineBytes.add(utf8Bytes[i]);
      // Limit first line to 75 octets, subsequent to 74 (since leading space takes 1 octet)
      final limit = buffer.isEmpty ? maxLineOctets : (maxLineOctets - 1);
      if (currentLineBytes.length >= limit && i < utf8Bytes.length - 1) {
        // Ensure not splitting multi-byte UTF-8 code point
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
    // In UTF-8, continuation bytes have bit pattern 10xxxxxx (0x80 to 0xBF)
    final byte = bytes[index];
    return (byte & 0xC0) != 0x80;
  }

  static List<String> _unfoldLines(String raw) {
    // RFC 6350 line unfolding: remove CRLF (or LF) followed immediately by a space or tab
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

  static List<String> _extractTypes(String keyPart) {
    final types = <String>[];
    final match =
        RegExp(r'TYPE=([^:;]+)', caseSensitive: false).firstMatch(keyPart);
    if (match != null) {
      final raw = match.group(1);
      if (raw != null) {
        types.addAll(raw.split(',').map((t) => t.trim().toLowerCase()));
      }
    }
    return types;
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

  static String? _extractMediaType(String keyPart) {
    final match =
        RegExp(r'MEDIATYPE=([^:;]+)', caseSensitive: false).firstMatch(keyPart);
    return match?.group(1)?.trim().toLowerCase();
  }
}
