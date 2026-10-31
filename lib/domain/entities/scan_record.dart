import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Relational entity representing a decoded barcode scan entry within the encrypted vault.
@immutable
class ScanRecord {
  /// Unique identifier (UUIDv4).
  final String id;

  /// Decoded UTF-8 string payload or URI.
  final String rawValue;

  /// Optional raw byte buffer preserving binary payloads (e.g. fountain chunks).
  final Uint8List? rawBytes;

  /// Symbology format (e.g. `qrCode`, `aztec`, `dataMatrix`).
  final String format;

  /// Semantic content category (e.g. `url`, `vcard`, `wifi`, `geo`, `calendar`, `totp`, `crypto`, `text`).
  final String contentType;

  /// Timestamp when the code was scanned and committed to storage.
  final DateTime createdAt;

  /// Timestamp when the record was last modified or annotated.
  final DateTime updatedAt;

  /// Whether the user has flagged this record as a favorite.
  final bool isFavorite;

  /// User-defined or auto-generated title.
  final String? title;

  /// User annotations, security observations, or descriptive notes.
  final String? notes;

  /// Security threat assessment level (e.g. `none`, `low`, `medium`, `high`, `critical`).
  final String? threatSeverity;

  /// List of assigned tag names.
  final List<String> tags;

  const ScanRecord({
    required this.id,
    required this.rawValue,
    this.rawBytes,
    required this.format,
    required this.contentType,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.title,
    this.notes,
    this.threatSeverity,
    this.tags = const <String>[],
  });

  /// Factory creating a fresh scan record with auto-generated UUIDv4 and current timestamps.
  factory ScanRecord.create({
    required String rawValue,
    Uint8List? rawBytes,
    required String format,
    required String contentType,
    bool isFavorite = false,
    String? title,
    String? notes,
    String? threatSeverity,
    List<String> tags = const <String>[],
  }) {
    final DateTime now = DateTime.now();
    return ScanRecord(
      id: const Uuid().v4(),
      rawValue: rawValue,
      rawBytes: rawBytes,
      format: format,
      contentType: contentType,
      createdAt: now,
      updatedAt: now,
      isFavorite: isFavorite,
      title: title,
      notes: notes,
      threatSeverity: threatSeverity,
      tags: tags,
    );
  }

  /// Deserializes a database row map into a [ScanRecord].
  factory ScanRecord.fromMap(Map<String, dynamic> map,
      {List<String> tags = const <String>[]}) {
    return ScanRecord(
      id: map['id'] as String,
      rawValue: map['raw_value'] as String,
      rawBytes: map['raw_bytes'] as Uint8List?,
      format: map['format'] as String,
      contentType: map['content_type'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      isFavorite: (map['is_favorite'] as int) == 1,
      title: map['title'] as String?,
      notes: map['notes'] as String?,
      threatSeverity: map['threat_severity'] as String?,
      tags: tags,
    );
  }

  /// Serializes this record into a SQLite column map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'raw_value': rawValue,
      'raw_bytes': rawBytes,
      'format': format,
      'content_type': contentType,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_favorite': isFavorite ? 1 : 0,
      'title': title,
      'notes': notes,
      'threat_severity': threatSeverity,
    };
  }

  /// Creates a copy with specific fields updated.
  ScanRecord copyWith({
    String? rawValue,
    Uint8List? rawBytes,
    String? format,
    String? contentType,
    DateTime? updatedAt,
    bool? isFavorite,
    String? title,
    String? notes,
    String? threatSeverity,
    List<String>? tags,
  }) {
    return ScanRecord(
      id: id,
      rawValue: rawValue ?? this.rawValue,
      rawBytes: rawBytes ?? this.rawBytes,
      format: format ?? this.format,
      contentType: contentType ?? this.contentType,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      threatSeverity: threatSeverity ?? this.threatSeverity,
      tags: tags ?? this.tags,
    );
  }
}

/// Relational entity representing an organizational tag.
@immutable
class TagRecord {
  /// Unique identifier (UUIDv4).
  final String id;

  /// Tag name (unique).
  final String name;

  /// Hexadecimal color string.
  final String? colorHex;

  /// Creation timestamp.
  final DateTime createdAt;

  const TagRecord({
    required this.id,
    required this.name,
    this.colorHex,
    required this.createdAt,
  });

  /// Factory creating a fresh tag record with auto-generated UUIDv4.
  factory TagRecord.create({
    required String name,
    String? colorHex,
  }) {
    return TagRecord(
      id: const Uuid().v4(),
      name: name.trim(),
      colorHex: colorHex,
      createdAt: DateTime.now(),
    );
  }

  /// Deserializes a database row map into a [TagRecord].
  factory TagRecord.fromMap(Map<String, dynamic> map) {
    return TagRecord(
      id: map['id'] as String,
      name: map['name'] as String,
      colorHex: map['color_hex'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// Serializes this tag into a SQLite column map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'color_hex': colorHex,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}
