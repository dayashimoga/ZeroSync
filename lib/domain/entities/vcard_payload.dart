import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Represents a phone contact entry with RFC 6350 types.
class ContactPhone extends Equatable {
  final String number;
  final List<String> types;

  const ContactPhone({
    required this.number,
    this.types = const ['cell'],
  });

  @override
  List<Object?> get props => [number, types];
}

/// Represents an email contact entry.
class ContactEmail extends Equatable {
  final String address;
  final List<String> types;

  const ContactEmail({
    required this.address,
    this.types = const ['work'],
  });

  @override
  List<Object?> get props => [address, types];
}

/// Represents a physical postal address.
class ContactAddress extends Equatable {
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final List<String> types;

  const ContactAddress({
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.types = const ['work'],
  });

  @override
  List<Object?> get props => [street, city, state, postalCode, country, types];
}

/// Pure Domain Entity representing an RFC 6350 vCard 4.0 Contact Payload.
class VCardPayload extends Equatable {
  final String formattedName;
  final String? familyName;
  final String? givenName;
  final String? additionalNames;
  final String? prefix;
  final String? suffix;
  final String? organization;
  final String? department;
  final String? jobTitle;
  final List<ContactPhone> phones;
  final List<ContactEmail> emails;
  final List<ContactAddress> addresses;
  final List<String> urls;
  final String? note;
  final String? photoBase64;
  final String? photoMediaType;

  const VCardPayload({
    required this.formattedName,
    this.familyName,
    this.givenName,
    this.additionalNames,
    this.prefix,
    this.suffix,
    this.organization,
    this.department,
    this.jobTitle,
    this.phones = const [],
    this.emails = const [],
    this.addresses = const [],
    this.urls = const [],
    this.note,
    this.photoBase64,
    this.photoMediaType,
  });

  /// Invariant verification
  void validateInvariants() {
    if (formattedName.trim().isEmpty) {
      throw ArgumentError('Formatted Name (FN) is mandatory in vCard 4.0');
    }

    if (photoBase64 != null) {
      final sanitized = sanitizeBase64(photoBase64!);
      try {
        base64.decode(sanitized);
      } catch (e) {
        throw ArgumentError('Photo data must be valid base64: $e');
      }
    }
  }

  /// Sanitizes raw base64 string by removing whitespace, line breaks, and data URI prefixes.
  static String sanitizeBase64(String input) {
    var cleaned = input.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.contains(',')) {
      cleaned = cleaned.substring(cleaned.indexOf(',') + 1);
    }
    return cleaned;
  }

  @override
  List<Object?> get props => [
        formattedName,
        familyName,
        givenName,
        additionalNames,
        prefix,
        suffix,
        organization,
        department,
        jobTitle,
        phones,
        emails,
        addresses,
        urls,
        note,
        photoBase64,
        photoMediaType,
      ];
}
