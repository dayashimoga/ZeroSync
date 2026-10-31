import 'dart:convert';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Available ZeroSync tier levels.
enum LicenseTier {
  community,
  pro,
  enterprise;

  static LicenseTier fromString(String val) {
    for (final tier in LicenseTier.values) {
      if (tier.name.toLowerCase() == val.toLowerCase()) return tier;
    }
    return LicenseTier.community;
  }
}

/// Feature flags gated behind cryptographic offline license entitlements.
enum LicenseFeature {
  /// RGB 3-Channel optical multiplexing (3x speed boost).
  rgbMultiplexing,

  /// Optical payload sizes exceeding 50 MB.
  unlimitedPayloadSize,

  /// Cryptographic forensic PDF audit signing.
  forensicExport,

  /// Decoy SQLCipher panic database mounting under duress.
  duressDecoyVault,

  /// 120 FPS high-speed hardware camera ingestion.
  highSpeedCamera;

  static LicenseFeature? fromString(String val) {
    for (final feat in LicenseFeature.values) {
      if (feat.name.toLowerCase() == val.toLowerCase()) return feat;
    }
    return null;
  }
}

/// Structured entitlement payload carried inside a `.zslic` license.
class LicensePayload extends Equatable {
  final String id;
  final String licensedTo;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final LicenseTier tier;
  final Set<LicenseFeature> features;

  const LicensePayload({
    required this.id,
    required this.licensedTo,
    required this.issuedAt,
    this.expiresAt,
    required this.tier,
    required this.features,
  });

  bool isExpired([DateTime? at]) {
    if (expiresAt == null) return false;
    final now = at ?? DateTime.now();
    return now.isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'licensedTo': licensedTo,
      'issuedAt': issuedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'tier': tier.name,
      'features': features.map((f) => f.name).toList()..sort(),
    };
  }

  factory LicensePayload.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'] as List<dynamic>? ?? const [];
    final features = <LicenseFeature>{};
    for (final item in rawFeatures) {
      final f = LicenseFeature.fromString(item.toString());
      if (f != null) features.add(f);
    }

    return LicensePayload(
      id: json['id'] as String,
      licensedTo: json['licensedTo'] as String,
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      tier: LicenseTier.fromString(json['tier'] as String? ?? 'community'),
      features: features,
    );
  }

  /// Canonical byte serialization used for Ed25519 signing and verification.
  Uint8List toCanonicalBytes() {
    final sortedJson = jsonEncode(toJson());
    return Uint8List.fromList(utf8.encode(sortedJson));
  }

  @override
  List<Object?> get props =>
      [id, licensedTo, issuedAt, expiresAt, tier, features];
}

/// Offline self-verifying license containing an entitlement payload and an Ed25519 signature.
class LicenseCertificate extends Equatable {
  static const int magicConstant = 0x5A534C31; // "ZSL1"
  static const int signatureLength = 64; // Ed25519 signature size

  final LicensePayload payload;
  final Uint8List signature;

  const LicenseCertificate({
    required this.payload,
    required this.signature,
  });

  /// Serializes certificate into a `.zslic` JSON string.
  String toEncodedString() {
    final map = {
      'payload': payload.toJson(),
      'signature': base64Encode(signature),
    };
    return base64Encode(utf8.encode(jsonEncode(map)));
  }

  /// Deserializes a `.zslic` Base64/JSON string into a [LicenseCertificate].
  factory LicenseCertificate.fromEncodedString(String encoded) {
    String jsonString;
    try {
      jsonString = utf8.decode(base64Decode(encoded.trim()));
    } catch (_) {
      // Fallback if raw JSON string was supplied
      jsonString = encoded.trim();
    }

    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Invalid license format: expected JSON object');
    }

    final payloadJson = decoded['payload'] as Map<String, dynamic>?;
    final signatureBase64 = decoded['signature'] as String?;

    if (payloadJson == null || signatureBase64 == null) {
      throw const FormatException(
          'Missing payload or signature in license certificate');
    }

    final payload = LicensePayload.fromJson(payloadJson);
    final signature = base64Decode(signatureBase64);

    if (signature.length != signatureLength) {
      throw FormatException(
        'Invalid Ed25519 signature size: expected $signatureLength bytes, got ${signature.length}',
      );
    }

    return LicenseCertificate(
      payload: payload,
      signature: Uint8List.fromList(signature),
    );
  }

  /// Serializes certificate into compact binary layout:
  /// [0..3]   : Magic "ZSL1" (0x5A534C31)
  /// [4..67]  : Ed25519 signature (64 bytes)
  /// [68..N]  : Canonical JSON UTF-8 payload
  Uint8List toBinary() {
    final canonicalPayload = payload.toCanonicalBytes();
    final bytes = Uint8List(4 + signatureLength + canonicalPayload.length);
    final view = ByteData.sublistView(bytes);

    view.setUint32(0, magicConstant, Endian.big);
    bytes.setRange(4, 4 + signatureLength, signature);
    bytes.setRange(4 + signatureLength, bytes.length, canonicalPayload);

    return bytes;
  }

  /// Deserializes compact binary format into a [LicenseCertificate].
  factory LicenseCertificate.fromBinary(Uint8List bytes) {
    if (bytes.length < 4 + signatureLength) {
      throw FormatException(
        'Binary license too short: ${bytes.length} bytes (minimum ${4 + signatureLength})',
      );
    }

    final view = ByteData.sublistView(bytes);
    final magic = view.getUint32(0, Endian.big);
    if (magic != magicConstant) {
      throw FormatException(
        'Invalid license magic: expected 0x5A534C31, received 0x${magic.toRadixString(16).padLeft(8, '0').toUpperCase()}',
      );
    }

    final sigBytes = Uint8List.sublistView(bytes, 4, 4 + signatureLength);
    final payloadJsonBytes = Uint8List.sublistView(bytes, 4 + signatureLength);
    final payloadJson =
        jsonDecode(utf8.decode(payloadJsonBytes)) as Map<String, dynamic>;
    final payload = LicensePayload.fromJson(payloadJson);

    return LicenseCertificate(
      payload: payload,
      signature: sigBytes,
    );
  }

  @override
  List<Object?> get props => [payload, signature];
}
