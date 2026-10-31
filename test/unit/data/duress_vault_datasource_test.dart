import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class MockDatabase extends Mock implements Database {}

void main() {
  group('EncryptedVaultDataSource Decoy & Duress Mode Specs', () {
    late MockDatabase mockDb;
    late EncryptedVaultDataSourceImpl vault;

    setUp(() {
      mockDb = MockDatabase();
      vault = EncryptedVaultDataSourceImpl();

      when(() => mockDb.isOpen).thenReturn(true);
      when(() => mockDb.execute(any())).thenAnswer((_) async {});
      when(() => mockDb.close()).thenAnswer((_) async {});
    });

    tearDown(() async {
      await vault.close();
    });

    test('initializeDecoy sets isDecoyActive true and seeds records if empty',
        () async {
      when(() => mockDb.rawQuery('SELECT COUNT(*) as count FROM scans'))
          .thenAnswer((_) async => [
                {'count': 0}
              ]);
      when(() => mockDb.insert(
            any(),
            any(),
            conflictAlgorithm: any(named: 'conflictAlgorithm'),
          )).thenAnswer((_) async => 1);

      await vault.initializeDecoy(injectedDb: mockDb);

      expect(vault.isOpen, isTrue);
      expect(vault.isDecoyActive, isTrue);

      // Verify schema creation
      verify(() => mockDb.execute(any())).called(greaterThanOrEqualTo(5));

      // Verify count check
      verify(() => mockDb.rawQuery('SELECT COUNT(*) as count FROM scans'))
          .called(1);

      // Verify decoy seed records inserted
      verify(() => mockDb.insert(
            'scans',
            any(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          )).called(3);
    });

    test('initializeDecoy does not seed if scans table is not empty', () async {
      when(() => mockDb.rawQuery('SELECT COUNT(*) as count FROM scans'))
          .thenAnswer((_) async => [
                {'count': 5}
              ]);

      await vault.initializeDecoy(injectedDb: mockDb);

      expect(vault.isOpen, isTrue);
      expect(vault.isDecoyActive, isTrue);

      verify(() => mockDb.rawQuery('SELECT COUNT(*) as count FROM scans'))
          .called(1);
      verifyNever(() => mockDb.insert(
            'scans',
            any(),
            conflictAlgorithm: any(named: 'conflictAlgorithm'),
          ));
    });

    test('Standard initialize sets isDecoyActive to false', () async {
      when(() => mockDb.rawQuery(any())).thenAnswer((_) async => []);

      await vault.initialize(injectedDb: mockDb);

      expect(vault.isOpen, isTrue);
      expect(vault.isDecoyActive, isFalse);
    });
  });
}
