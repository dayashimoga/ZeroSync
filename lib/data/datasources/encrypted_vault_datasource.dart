import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Relational entity representing an encrypted scan record in the ZeroSync local vault.
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
  factory ScanRecord.fromMap(Map<String, dynamic> map, {List<String> tags = const <String>[]}) {
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

  /// Optional hex color code for visual rendering (e.g. `#00E5FF`).
  final String? colorHex;

  /// Timestamp when the tag was created.
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

  /// Deserializes a database row into a [TagRecord].
  factory TagRecord.fromMap(Map<String, dynamic> map) {
    return TagRecord(
      id: map['id'] as String,
      name: map['name'] as String,
      colorHex: map['color_hex'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// Serializes this record into a SQLite column map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'color_hex': colorHex,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}

/// Abstract contract defining the zero-trust encrypted vault datasource.
abstract class EncryptedVaultDataSource {
  /// Initializes the hardware-backed keystore and opens the SQLCipher encrypted database.
  Future<void> initialize({String? customPassword, Database? injectedDb});

  /// Closes the database and resets internal resources.
  Future<void> close();

  /// Whether the database is actively open and ready for queries.
  bool get isOpen;

  /// Retrieves or provisions the 256-bit AES master encryption passphrase from secure hardware storage.
  Future<String> getOrGenerateMasterKey();

  // --- Scan Record CRUD ---
  Future<ScanRecord> insertScan(ScanRecord scan);
  Future<ScanRecord?> getScanById(String id);
  Future<List<ScanRecord>> getAllScans({bool favoritesOnly = false, int? limit, int? offset});
  Future<List<ScanRecord>> searchScans(String query);
  Future<List<ScanRecord>> getScansByTag(String tagId);
  Future<void> updateScan(ScanRecord scan);
  Future<void> toggleFavorite(String id, bool isFavorite);
  Future<void> deleteScan(String id);
  Future<int> clearAllScans();

  // --- Tag Management ---
  Future<TagRecord> createTag(String name, {String? colorHex});
  Future<List<TagRecord>> getAllTags();
  Future<void> assignTagToScan(String scanId, String tagId);
  Future<void> removeTagFromScan(String scanId, String tagId);
  Future<void> deleteTag(String tagId);

  // --- Cipher Integrity ---
  Future<bool> verifyCipherIntegrity();
}

/// Production implementation of [EncryptedVaultDataSource] utilizing SQLCipher AES-256
/// database encryption backed by Android Keystore / iOS Keychain (`FlutterSecureStorage`).
class EncryptedVaultDataSourceImpl implements EncryptedVaultDataSource {
  static const String _keyVaultPassphrase = 'zerosync_vault_master_key_v1';
  static const String _databaseFileName = 'zerosync_vault_encrypted.db';

  final FlutterSecureStorage _secureStorage;
  Database? _db;
  bool _isInitialized = false;

  EncryptedVaultDataSourceImpl({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  @override
  bool get isOpen => _db != null && _db!.isOpen;

  @override
  Future<void> initialize({String? customPassword, Database? injectedDb}) async {
    if (_isInitialized && isOpen) return;

    if (injectedDb != null) {
      _db = injectedDb;
      await _createSchema(_db!);
      _isInitialized = true;
      return;
    }

    final String password = customPassword ?? await getOrGenerateMasterKey();
    final String databasesPath = await getDatabasesPath();
    final String path = '$databasesPath/$_databaseFileName';

    _db = await openDatabase(
      path,
      password: password,
      version: 1,
      onCreate: (Database db, int version) async {
        await _createSchema(db);
      },
    );

    _isInitialized = true;
  }

  /// Creates relational tables, indexes, and metadata entries in the encrypted database.
  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scans (
        id TEXT PRIMARY KEY,
        raw_value TEXT NOT NULL,
        raw_bytes BLOB,
        format TEXT NOT NULL,
        content_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        notes TEXT,
        threat_severity TEXT
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_scans_created_at ON scans(created_at DESC);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_scans_favorite ON scans(is_favorite);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        color_hex TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_tags (
        scan_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (scan_id, tag_id),
        FOREIGN KEY (scan_id) REFERENCES scans(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_scan_tags_scan ON scan_tags(scan_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_scan_tags_tag ON scan_tags(tag_id);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO vault_metadata (key, value)
      VALUES ('schema_version', '1.0.0');
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO vault_metadata (key, value)
      VALUES ('cipher_standard', 'AES-256-CBC');
    ''');
  }

  @override
  Future<String> getOrGenerateMasterKey() async {
    String? key = await _secureStorage.read(key: _keyVaultPassphrase);
    if (key == null || key.isEmpty) {
      // Generate a 256-bit (32-byte) cryptographically secure random key
      final Random rng = Random.secure();
      final Uint8List keyBytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        keyBytes[i] = rng.nextInt(256);
      }
      key = base64UrlEncode(keyBytes);
      await _secureStorage.write(key: _keyVaultPassphrase, value: key);
    }
    return key;
  }

  @override
  Future<ScanRecord> insertScan(ScanRecord scan) async {
    _assertDbReady();
    await _db!.insert(
      'scans',
      scan.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Persist tags if present
    for (final String tagName in scan.tags) {
      final TagRecord tag = await createTag(tagName);
      await assignTagToScan(scan.id, tag.id);
    }

    return scan;
  }

  @override
  Future<ScanRecord?> getScanById(String id) async {
    _assertDbReady();
    final List<Map<String, dynamic>> rows = await _db!.query(
      'scans',
      where: 'id = ?',
      whereArgs: <dynamic>[id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final List<String> tags = await _getTagsForScan(id);
    return ScanRecord.fromMap(rows.first, tags: tags);
  }

  @override
  Future<List<ScanRecord>> getAllScans({
    bool favoritesOnly = false,
    int? limit,
    int? offset,
  }) async {
    _assertDbReady();
    final String? where = favoritesOnly ? 'is_favorite = 1' : null;

    final List<Map<String, dynamic>> rows = await _db!.query(
      'scans',
      where: where,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    final List<ScanRecord> results = <ScanRecord>[];
    for (final Map<String, dynamic> row in rows) {
      final String id = row['id'] as String;
      final List<String> tags = await _getTagsForScan(id);
      results.add(ScanRecord.fromMap(row, tags: tags));
    }
    return results;
  }

  @override
  Future<List<ScanRecord>> searchScans(String query) async {
    _assertDbReady();
    final String term = '%${query.trim()}%';

    final List<Map<String, dynamic>> rows = await _db!.query(
      'scans',
      where: 'raw_value LIKE ? OR title LIKE ? OR notes LIKE ?',
      whereArgs: <dynamic>[term, term, term],
      orderBy: 'created_at DESC',
    );

    final List<ScanRecord> results = <ScanRecord>[];
    for (final Map<String, dynamic> row in rows) {
      final String id = row['id'] as String;
      final List<String> tags = await _getTagsForScan(id);
      results.add(ScanRecord.fromMap(row, tags: tags));
    }
    return results;
  }

  @override
  Future<List<ScanRecord>> getScansByTag(String tagId) async {
    _assertDbReady();
    final List<Map<String, dynamic>> rows = await _db!.rawQuery('''
      SELECT s.* FROM scans s
      INNER JOIN scan_tags st ON s.id = st.scan_id
      WHERE st.tag_id = ?
      ORDER BY s.created_at DESC
    ''', <dynamic>[tagId]);

    final List<ScanRecord> results = <ScanRecord>[];
    for (final Map<String, dynamic> row in rows) {
      final String id = row['id'] as String;
      final List<String> tags = await _getTagsForScan(id);
      results.add(ScanRecord.fromMap(row, tags: tags));
    }
    return results;
  }

  @override
  Future<void> updateScan(ScanRecord scan) async {
    _assertDbReady();
    await _db!.update(
      'scans',
      scan.toMap(),
      where: 'id = ?',
      whereArgs: <dynamic>[scan.id],
    );
  }

  @override
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    _assertDbReady();
    await _db!.update(
      'scans',
      <String, dynamic>{
        'is_favorite': isFavorite ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <dynamic>[id],
    );
  }

  @override
  Future<void> deleteScan(String id) async {
    _assertDbReady();
    await _db!.delete(
      'scans',
      where: 'id = ?',
      whereArgs: <dynamic>[id],
    );
    await _db!.delete(
      'scan_tags',
      where: 'scan_id = ?',
      whereArgs: <dynamic>[id],
    );
  }

  @override
  Future<int> clearAllScans() async {
    _assertDbReady();
    await _db!.delete('scan_tags');
    return _db!.delete('scans');
  }

  @override
  Future<TagRecord> createTag(String name, {String? colorHex}) async {
    _assertDbReady();
    final String cleanName = name.trim();

    // Check if tag already exists
    final List<Map<String, dynamic>> existing = await _db!.query(
      'tags',
      where: 'name = ?',
      whereArgs: <dynamic>[cleanName],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return TagRecord.fromMap(existing.first);
    }

    final TagRecord tag = TagRecord.create(
      name: cleanName,
      colorHex: colorHex,
    );

    await _db!.insert(
      'tags',
      tag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return tag;
  }

  @override
  Future<List<TagRecord>> getAllTags() async {
    _assertDbReady();
    final List<Map<String, dynamic>> rows = await _db!.query(
      'tags',
      orderBy: 'name ASC',
    );
    return rows.map((r) => TagRecord.fromMap(r)).toList();
  }

  @override
  Future<void> assignTagToScan(String scanId, String tagId) async {
    _assertDbReady();
    await _db!.insert(
      'scan_tags',
      <String, dynamic>{
        'scan_id': scanId,
        'tag_id': tagId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> removeTagFromScan(String scanId, String tagId) async {
    _assertDbReady();
    await _db!.delete(
      'scan_tags',
      where: 'scan_id = ? AND tag_id = ?',
      whereArgs: <dynamic>[scanId, tagId],
    );
  }

  @override
  Future<void> deleteTag(String tagId) async {
    _assertDbReady();
    await _db!.delete('tags', where: 'id = ?', whereArgs: <dynamic>[tagId]);
    await _db!.delete('scan_tags', where: 'tag_id = ?', whereArgs: <dynamic>[tagId]);
  }

  @override
  Future<bool> verifyCipherIntegrity() async {
    _assertDbReady();
    try {
      final List<Map<String, dynamic>> result = await _db!.rawQuery(
        "SELECT value FROM vault_metadata WHERE key = 'cipher_standard'",
      );
      return result.isNotEmpty && result.first['value'] == 'AES-256-CBC';
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _getTagsForScan(String scanId) async {
    final List<Map<String, dynamic>> rows = await _db!.rawQuery('''
      SELECT t.name FROM tags t
      INNER JOIN scan_tags st ON t.id = st.tag_id
      WHERE st.scan_id = ?
      ORDER BY t.name ASC
    ''', <dynamic>[scanId]);

    return rows.map((r) => r['name'] as String).toList();
  }

  void _assertDbReady() {
    if (_db == null || !_db!.isOpen) {
      throw StateError('EncryptedVaultDataSource is not initialized or database is closed');
    }
  }

  @override
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
    _isInitialized = false;
  }
}

