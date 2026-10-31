import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/payload_encryption_service.dart';

void main() {
  group('EncryptedPayloadEnvelope Wire Specification Specs', () {
    test(
        'Envelope wire layout conforms to 59-byte header + ciphertext structure',
        () {
      final salt = Uint8List(16)..fillRange(0, 16, 0x11);
      final nonce = Uint8List(24)..fillRange(0, 24, 0x22);
      final mac = Uint8List(16)..fillRange(0, 16, 0x33);
      final ciphertext = Uint8List.fromList([1, 2, 3, 4, 5]);

      final envelope = EncryptedPayloadEnvelope(
        salt: salt,
        nonce: nonce,
        mac: mac,
        ciphertext: ciphertext,
      );

      final wire = envelope.toWireBytes();
      expect(wire.length, equals(59 + ciphertext.length));
      expect(wire[0], equals(0x5A)); // 'Z'
      expect(wire[1], equals(0x45)); // 'E'
      expect(wire[2], equals(1)); // Version 1

      final restored = EncryptedPayloadEnvelope.fromWireBytes(wire);
      expect(restored.salt, equals(salt));
      expect(restored.nonce, equals(nonce));
      expect(restored.mac, equals(mac));
      expect(restored.ciphertext, equals(ciphertext));
      expect(restored, equals(envelope));
    });

    test('Rejects datagrams shorter than 59 bytes', () {
      expect(
        () => EncryptedPayloadEnvelope.fromWireBytes(Uint8List(58)),
        throwsA(isA<FormatException>()),
      );
    });

    test('Rejects invalid magic preamble', () {
      final wire = Uint8List(60);
      wire[0] = 0x00; // Corrupt magic
      expect(
        () => EncryptedPayloadEnvelope.fromWireBytes(wire),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PayloadEncryptionService XChaCha20-Poly1305 & Argon2id Specs', () {
    late PayloadEncryptionService service;

    setUp(() {
      service = PayloadEncryptionService(
        kdfMemory: 4 * 1024, // 4 MB for fast unit test execution
        kdfIterations: 1,
      );
    });

    test(
        'Passphrase encryption & decryption round-trip recovers original plaintext',
        () async {
      final plaintext =
          Uint8List.fromList('ZeroSync Top-Secret Air-Gap Payload'.codeUnits);
      const passphrase = 'SuperSecurePassphrase!2026';

      final envelope = await service.encryptWithPassphrase(
        plaintext: plaintext,
        passphrase: passphrase,
      );

      expect(envelope.ciphertext, isNot(equals(plaintext)));
      expect(envelope.salt.length, equals(16));
      expect(envelope.nonce.length, equals(24));
      expect(envelope.mac.length, equals(16));

      final decrypted = await service.decryptWithPassphrase(
        envelope: envelope,
        passphrase: passphrase,
      );

      expect(decrypted, equals(plaintext));
    });

    test('Wrong passphrase fails authentication and throws error', () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final envelope = await service.encryptWithPassphrase(
        plaintext: plaintext,
        passphrase: 'CorrectPassword',
      );

      expect(
        () => service.decryptWithPassphrase(
          envelope: envelope,
          passphrase: 'WrongPassword',
        ),
        throwsA(anything),
      );
    });

    test('Tampered ciphertext is rejected by Poly1305 AEAD authentication',
        () async {
      final plaintext = Uint8List.fromList([10, 20, 30, 40]);
      final envelope = await service.encryptWithPassphrase(
        plaintext: plaintext,
        passphrase: 'Key',
      );

      // Flip single bit in ciphertext
      final tamperedCiphertext = Uint8List.fromList(envelope.ciphertext);
      tamperedCiphertext[0] ^= 0x01;

      final corruptedEnvelope = EncryptedPayloadEnvelope(
        salt: envelope.salt,
        nonce: envelope.nonce,
        mac: envelope.mac,
        ciphertext: tamperedCiphertext,
      );

      expect(
        () => service.decryptWithPassphrase(
          envelope: corruptedEnvelope,
          passphrase: 'Key',
        ),
        throwsA(anything),
      );
    });

    test('Tampered MAC tag is rejected by Poly1305 AEAD authentication',
        () async {
      final plaintext = Uint8List.fromList([10, 20, 30, 40]);
      final envelope = await service.encryptWithPassphrase(
        plaintext: plaintext,
        passphrase: 'Key',
      );

      // Flip single bit in MAC tag
      final tamperedMac = Uint8List.fromList(envelope.mac);
      tamperedMac[0] ^= 0x01;

      final corruptedEnvelope = EncryptedPayloadEnvelope(
        salt: envelope.salt,
        nonce: envelope.nonce,
        mac: tamperedMac,
        ciphertext: envelope.ciphertext,
      );

      expect(
        () => service.decryptWithPassphrase(
          envelope: corruptedEnvelope,
          passphrase: 'Key',
        ),
        throwsA(anything),
      );
    });

    test(
        'Ephemeral X25519 ECDH optical handshake encrypts and decrypts between Alice and Bob',
        () async {
      final aliceKeyPair = await service.generateEphemeralKeyPair();
      final alicePublicKey = await aliceKeyPair.extractPublicKey();

      final bobKeyPair = await service.generateEphemeralKeyPair();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      final secretMessage =
          Uint8List.fromList('Peer-to-Peer Optical Air-Gap Secret'.codeUnits);

      // Alice encrypts for Bob using Bob's ephemeral public key
      final envelope = await service.encryptForPeer(
        plaintext: secretMessage,
        localEphemeralKeyPair: aliceKeyPair,
        peerEphemeralPublicKey: bobPublicKey,
      );

      // Bob decrypts from Alice using Alice's ephemeral public key
      final decrypted = await service.decryptFromPeer(
        envelope: envelope,
        localEphemeralKeyPair: bobKeyPair,
        peerEphemeralPublicKey: alicePublicKey,
      );

      expect(decrypted, equals(secretMessage));
    });
  });
}
