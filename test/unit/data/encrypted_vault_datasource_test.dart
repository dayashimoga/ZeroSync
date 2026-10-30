import 'dart:typed_data';

import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockDatabase extends Mock implements Database {}

void main() {
  group('ScanRecord Entity & Serialization Specs', () {
    test('ScanRecord.create assigns UUIDv4 and synchronized timestamps', () {
      final scan = ScanRecord.create(
        rawValue: 'WIFI:S:MyNet;T:WPA;P:Secret;;',
        format: 'qrCode',
        contentType: 'wifi',
        isFavorite: true,
        title: 'Office Wi-Fi',
        notes: 'Main floor router',
        threatSeverity: 'none',
        tags: const ['network', 'work'],
      );

      expect(scan.id, isNotEmpty);
      expect(scan.id.length, equals(36)); // Standard UUID length
      expect(scan.rawValue, equals('WIFI:S:MyNet;T:WPA;P:Secret;;'));
      expect(scan.format, equals('qrCode'));
      expect(scan.contentType, equals('wifi'));
      expect(scan.isFavorite, isTrue);
      expect(scan.title, equals('Office Wi-Fi'));
      expect(scan.notes, equals('Main floor router'));
      expect(scan.threatSeverity, equals('none'));
      expect(scan.tags, equals(['network', 'work']));
      expect(scan.createdAt, equals(scan.updatedAt));
    });

    test('Round-trip serialization toMap and fromMap preserves all attributes',
        () {
      final original = ScanRecord(
        id: '11111111-2222-3333-4444-555555555555',
        rawValue: 'https://zerosync.org/payload',
        rawBytes: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
        format: 'qrCode',
        contentType: 'url',
        createdAt: DateTime(2026, 10, 29, 10, 0, 0),
        updatedAt: DateTime(2026, 10, 29, 12, 30, 0),
        isFavorite: true,
        title: 'ZeroSync Portal',
        notes: 'Air-gap transfer landing',
        threatSeverity: 'low',
        tags: const ['web', 'crypto'],
      );

      final map = original.toMap();
      expect(map['id'], equals('11111111-2222-3333-4444-555555555555'));
      expect(map['raw_value'], equals('https://zerosync.org/payload'));
      expect(map['raw_bytes'],
          equals(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])));
      expect(map['format'], equals('qrCode'));
      expect(map['content_type'], equals('url'));
      expect(map['is_favorite'], equals(1));
      expect(map['title'], equals('ZeroSync Portal'));
      expect(map['threat_severity'], equals('low'));

      final restored = ScanRecord.fromMap(map, tags: const ['web', 'crypto']);
      expect(restored.id, equals(original.id));
      expect(restored.rawValue, equals(original.rawValue));
      expect(restored.rawBytes, equals(original.rawBytes));
      expect(restored.format, equals(original.format));
      expect(restored.contentType, equals(original.contentType));
      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.updatedAt, equals(original.updatedAt));
      expect(restored.isFavorite, equals(original.isFavorite));
      expect(restored.title, equals(original.title));
      expect(restored.notes, equals(original.notes));
      expect(restored.threatSeverity, equals(original.threatSeverity));
      expect(restored.tags, equals(['web', 'crypto']));
    });

    test('copyWith updates selected fields immutably', () {
      final scan = ScanRecord.create(
        rawValue: 'ITEM-1',
        format: 'qrCode',
        contentType: 'text',
      );

      final updated = scan.copyWith(
        isFavorite: true,
        title: 'Updated Title',
        threatSeverity: 'high',
        tags: const ['urgent'],
      );

      expect(updated.id, equals(scan.id));
      expect(updated.isFavorite, isTrue);
      expect(updated.title, equals('Updated Title'));
      expect(updated.threatSeverity, equals('high'));
      expect(updated.tags, equals(['urgent']));
    });
  });

  group('TagRecord Entity & Serialization Specs', () {
    test('TagRecord.create assigns UUID and trims name', () {
      final tag = TagRecord.create(name: '  security  ', colorHex: '#00E5FF');
      expect(tag.id, isNotEmpty);
      expect(tag.name, equals('security'));
      expect(tag.colorHex, equals('#00E5FF'));
    });

    test('toMap and fromMap roundtrip serialization', () {
      final original = TagRecord(
        id: 'tag-1234',
        name: 'finance',
        colorHex: '#FF9100',
        createdAt: DateTime(2026, 10, 29, 8, 0, 0),
      );

      final map = original.toMap();
      final restored = TagRecord.fromMap(map);
      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.colorHex, equals(original.colorHex));
      expect(restored.createdAt, equals(original.createdAt));
    });
  });

  group('Master Key Generation via Secure Storage', () {
    late MockFlutterSecureStorage mockStorage;
    late EncryptedVaultDataSourceImpl vault;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      vault = EncryptedVaultDataSourceImpl(secureStorage: mockStorage);
    });

    test('Generates new 256-bit AES master passphrase when non-existent',
        () async {
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'))).thenAnswer((_) async {});

      final key = await vault.getOrGenerateMasterKey();

      expect(key, isNotEmpty);
      // 32 bytes base64URL encoded is 43-44 chars
      expect(key.length, greaterThanOrEqualTo(40));
      verify(() => mockStorage.read(key: 'zerosync_vault_master_key_v1'))
          .called(1);
      verify(() => mockStorage.write(
          key: 'zerosync_vault_master_key_v1', value: key)).called(1);
    });

    test('Reuses existing master passphrase when already in secure storage',
        () async {
      const existingKey = 'k3y-alr3ady-ex1st1ng-in-k3ycha1n-st0r4g3';
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => existingKey);

      final key = await vault.getOrGenerateMasterKey();

      expect(key, equals(existingKey));
      verify(() => mockStorage.read(key: 'zerosync_vault_master_key_v1'))
          .called(1);
      verifyNever(() => mockStorage.write(
          key: any(named: 'key'), value: any(named: 'value')));
    });
  });

  group('EncryptedVaultDataSource Database Operations with Injected DB', () {
    late MockDatabase mockDb;
    late EncryptedVaultDataSourceImpl vault;

    setUp(() async {
      mockDb = MockDatabase();
      vault = EncryptedVaultDataSourceImpl();

      when(() => mockDb.isOpen).thenReturn(true);
      when(() => mockDb.execute(any())).thenAnswer((_) async {});
      when(() => mockDb.close()).thenAnswer((_) async {});

      await vault.initialize(injectedDb: mockDb);
    });

    tearDown(() async {
      await vault.close();
    });

    test('Initializes schema and creates relational tables', () {
      expect(vault.isOpen, isTrue);
      // Verify tables and indexes were executed
      verify(() => mockDb.execute(any())).called(greaterThanOrEqualTo(5));
    });

    test(
        'verifyCipherIntegrity validates AES-256-CBC cipher standard in metadata',
        () async {
      when(() => mockDb.rawQuery(any())).thenAnswer((_) async => [
            {'value': 'AES-256-CBC'},
          ]);

      final isValid = await vault.verifyCipherIntegrity();
      expect(isValid, isTrue);

      when(() => mockDb.rawQuery(any())).thenAnswer((_) async => []);
      final isInvalid = await vault.verifyCipherIntegrity();
      expect(isInvalid, isFalse);
    });

    test('insertScan persists scan and associates tags', () async {
      when(() => mockDb.insert(
            any(),
            any(),
            conflictAlgorithm: any(named: 'conflictAlgorithm'),
          )).thenAnswer((_) async => 1);

      when(() => mockDb.query(
            'tags',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);

      final scan = ScanRecord.create(
        rawValue: 'https://zerosync.airgap/test',
        format: 'qrCode',
        contentType: 'url',
        tags: const ['test-tag'],
      );

      final inserted = await vault.insertScan(scan);
      expect(inserted.id, equals(scan.id));

      verify(() => mockDb.insert('scans', any(),
          conflictAlgorithm: ConflictAlgorithm.replace)).called(1);
      verify(() => mockDb.insert('tags', any(),
          conflictAlgorithm: ConflictAlgorithm.replace)).called(1);
      verify(() => mockDb.insert('scan_tags', any(),
          conflictAlgorithm: ConflictAlgorithm.ignore)).called(1);
    });

    test('getScanById retrieves row and loads associated tags', () async {
      final now = DateTime.now();
      when(() => mockDb.query(
            'scans',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [
            {
              'id': 'scan-1',
              'raw_value': 'HELLO',
              'raw_bytes': null,
              'format': 'qrCode',
              'content_type': 'text',
              'created_at': now.millisecondsSinceEpoch,
              'updated_at': now.millisecondsSinceEpoch,
              'is_favorite': 1,
              'title': 'Test Title',
              'notes': null,
              'threat_severity': 'none',
            }
          ]);

      when(() => mockDb.rawQuery(any(), any())).thenAnswer((_) async => [
            {'name': 'general'},
            {'name': 'scanned'},
          ]);

      final record = await vault.getScanById('scan-1');
      expect(record, isNotNull);
      expect(record!.id, equals('scan-1'));
      expect(record.rawValue, equals('HELLO'));
      expect(record.isFavorite, isTrue);
      expect(record.tags, equals(['general', 'scanned']));
    });

    test('getScanById returns null when scan not found', () async {
      when(() => mockDb.query(
            'scans',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => []);

      final record = await vault.getScanById('nonexistent');
      expect(record, isNull);
    });

    test('getAllScans filters favorites and orders by created_at DESC',
        () async {
      final now = DateTime.now();
      when(() => mockDb.query(
            'scans',
            where: any(named: 'where'),
            orderBy: any(named: 'orderBy'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => [
            {
              'id': 'scan-1',
              'raw_value': 'FAV',
              'raw_bytes': null,
              'format': 'qrCode',
              'content_type': 'url',
              'created_at': now.millisecondsSinceEpoch,
              'updated_at': now.millisecondsSinceEpoch,
              'is_favorite': 1,
              'title': null,
              'notes': null,
              'threat_severity': null,
            }
          ]);

      when(() => mockDb.rawQuery(any(), any())).thenAnswer((_) async => []);

      final favorites = await vault.getAllScans(favoritesOnly: true);
      expect(favorites.length, equals(1));
      expect(favorites.first.rawValue, equals('FAV'));

      verify(() => mockDb.query(
            'scans',
            where: 'is_favorite = 1',
            orderBy: 'created_at DESC',
            limit: null,
            offset: null,
          )).called(1);
    });

    test('searchScans executes LIKE pattern across value, title, and notes',
        () async {
      when(() => mockDb.query(
            'scans',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => []);

      final results = await vault.searchScans('flutter');
      expect(results, isEmpty);

      verify(() => mockDb.query(
            'scans',
            where: 'raw_value LIKE ? OR title LIKE ? OR notes LIKE ?',
            whereArgs: ['%flutter%', '%flutter%', '%flutter%'],
            orderBy: 'created_at DESC',
          )).called(1);
    });

    test('toggleFavorite updates is_favorite flag in database', () async {
      when(() => mockDb.update(
            'scans',
            any(),
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
          )).thenAnswer((_) async => 1);

      await vault.toggleFavorite('scan-42', true);

      verify(() => mockDb.update(
            'scans',
            any(that: containsPair('is_favorite', 1)),
            where: 'id = ?',
            whereArgs: ['scan-42'],
          )).called(1);
    });

    test('deleteScan deletes scan and associated scan_tags', () async {
      when(() => mockDb.delete(
            any(),
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
          )).thenAnswer((_) async => 1);

      await vault.deleteScan('scan-99');

      verify(() =>
              mockDb.delete('scans', where: 'id = ?', whereArgs: ['scan-99']))
          .called(1);
      verify(() => mockDb.delete('scan_tags',
          where: 'scan_id = ?', whereArgs: ['scan-99'])).called(1);
    });

    test('clearAllScans truncates scans and scan_tags', () async {
      when(() => mockDb.delete(any())).thenAnswer((_) async => 5);

      final count = await vault.clearAllScans();
      expect(count, equals(5));

      verify(() => mockDb.delete('scan_tags')).called(1);
      verify(() => mockDb.delete('scans')).called(1);
    });

    test('Tag management: create, retrieve, and delete tags', () async {
      when(() => mockDb.query(
            'tags',
            where: any(named: 'where'),
            whereArgs: any(named: 'whereArgs'),
            limit: any(named: 'limit'),
            orderBy: any(named: 'orderBy'),
          )).thenAnswer((_) async => [
            {
              'id': 'tag-1',
              'name': 'personal',
              'color_hex': '#00FF00',
              'created_at': DateTime.now().millisecondsSinceEpoch,
            }
          ]);

      when(() => mockDb.insert(any(), any(),
              conflictAlgorithm: any(named: 'conflictAlgorithm')))
          .thenAnswer((_) async => 1);
      when(() => mockDb.delete(any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'))).thenAnswer((_) async => 1);

      final tags = await vault.getAllTags();
      expect(tags.length, equals(1));
      expect(tags.first.name, equals('personal'));

      await vault.assignTagToScan('scan-1', 'tag-1');
      verify(() => mockDb.insert(
            'scan_tags',
            {'scan_id': 'scan-1', 'tag_id': 'tag-1'},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          )).called(1);

      await vault.removeTagFromScan('scan-1', 'tag-1');
      verify(() => mockDb.delete(
            'scan_tags',
            where: 'scan_id = ? AND tag_id = ?',
            whereArgs: ['scan-1', 'tag-1'],
          )).called(1);

      await vault.deleteTag('tag-1');
      verify(() => mockDb.delete('tags', where: 'id = ?', whereArgs: ['tag-1']))
          .called(1);
    });

    test('Throws StateError if database operations called when closed',
        () async {
      when(() => mockDb.isOpen).thenReturn(false);

      expect(() => vault.getAllScans(), throwsStateError);
      expect(() => vault.getScanById('id'), throwsStateError);
      expect(() => vault.searchScans('q'), throwsStateError);
      expect(() => vault.createTag('tag'), throwsStateError);
    });
  });
}
