import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'secure_memory_arena.dart';

/// Self-describing wire envelope for AEAD encrypted optical payloads.
class EncryptedPayloadEnvelope extends Equatable {
  /// Wire magic preamble: 0x5A, 0x45 ('Z', 'E' for ZeroSync Encrypted).
  static const int magicConstant = 0x5A45;

  /// Current envelope version.
  static const int currentVersion = 1;

  /// Header prefix size: Magic(2B) + Version(1B) + Salt(16B) + Nonce(24B) + MAC(16B) = 59 Bytes.
  static const int headerSize = 59;
  static const int saltLength = 16;
  static const int nonceLength = 24;
  static const int macLength = 16;

  final int version;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List mac;
  final Uint8List ciphertext;

  const EncryptedPayloadEnvelope({
    this.version = currentVersion,
    required this.salt,
    required this.nonce,
    required this.mac,
    required this.ciphertext,
  });

  /// Serializes envelope into a contiguous binary datagram.
  Uint8List toWireBytes() {
    final totalLength = headerSize + ciphertext.length;
    final bytes = Uint8List(totalLength);
    final view = ByteData.sublistView(bytes);

    // [0..1] Magic
    view.setUint16(0, magicConstant, Endian.big);
    // [2] Version
    view.setUint8(2, version);

    // [3..18] Salt (16B)
    bytes.setRange(3, 19, salt);
    // [19..42] Nonce (24B)
    bytes.setRange(19, 43, nonce);
    // [43..58] MAC Tag (16B)
    bytes.setRange(43, 59, mac);
    // [59..N] Ciphertext
    bytes.setRange(59, totalLength, ciphertext);

    return bytes;
  }

  /// Deserializes a raw binary datagram into an [EncryptedPayloadEnvelope].
  factory EncryptedPayloadEnvelope.fromWireBytes(Uint8List wireBytes) {
    if (wireBytes.length < headerSize) {
      throw FormatException(
        'Encrypted envelope datagram too short: ${wireBytes.length} bytes (minimum $headerSize)',
      );
    }

    final view = ByteData.sublistView(wireBytes, 0, headerSize);
    final magic = view.getUint16(0, Endian.big);
    if (magic != magicConstant) {
      throw FormatException(
        'Invalid encryption preamble: expected 0x5A45, received 0x${magic.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      );
    }

    final version = view.getUint8(2);
    if (version != currentVersion) {
      throw FormatException(
        'Unsupported envelope version: expected $currentVersion, received $version',
      );
    }

    final salt = Uint8List.sublistView(wireBytes, 3, 19);
    final nonce = Uint8List.sublistView(wireBytes, 19, 43);
    final mac = Uint8List.sublistView(wireBytes, 43, 59);
    final ciphertext = Uint8List.sublistView(wireBytes, 59);

    return EncryptedPayloadEnvelope(
      version: version,
      salt: salt,
      nonce: nonce,
      mac: mac,
      ciphertext: ciphertext,
    );
  }

  @override
  List<Object?> get props => [version, salt, nonce, mac, ciphertext];
}

/// Zero-trust payload encryption service combining XChaCha20-Poly1305 AEAD,
/// Argon2id key derivation, and ephemeral X25519 ECDH optical key agreement.
class PayloadEncryptionService {
  final Cipher _cipher;
  final X25519 _ecdh;
  final Argon2id _kdf;
  final Random _secureRandom;

  PayloadEncryptionService({
    Cipher? cipher,
    X25519? ecdh,
    int kdfMemory = 8 * 1024,
    int kdfIterations = 2,
    int kdfParallelism = 1,
    Random? secureRandom,
  })  : _cipher = cipher ?? Xchacha20.poly1305Aead(),
        _ecdh = ecdh ?? X25519(),
        _kdf = Argon2id(
          memory: kdfMemory,
          iterations: kdfIterations,
          parallelism: kdfParallelism,
          hashLength: 32,
        ),
        _secureRandom = secureRandom ?? Random.secure();

  /// Generates a cryptographically secure random salt of [length] bytes.
  Uint8List generateRandomSalt(
      [int length = EncryptedPayloadEnvelope.saltLength]) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Generates a cryptographically secure random 24-byte nonce for XChaCha20.
  Uint8List generateNonce([int length = EncryptedPayloadEnvelope.nonceLength]) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Derives a 256-bit [SecretKey] from a user passphrase using memory-hard Argon2id.
  Future<SecretKey> deriveKeyFromPassphrase({
    required String passphrase,
    required Uint8List salt,
  }) async {
    return _kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
  }

  /// Generates a fresh ephemeral X25519 keypair for optical peer-to-peer key agreement.
  Future<SimpleKeyPair> generateEphemeralKeyPair() {
    return _ecdh.newKeyPair();
  }

  /// Computes a shared secret key from local ephemeral private key and peer public key.
  Future<SecretKey> computeSharedSecret({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey peerPublicKey,
  }) {
    return _ecdh.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: peerPublicKey,
    );
  }

  /// Encrypts [plaintext] using a passphrase-derived key via Argon2id and XChaCha20-Poly1305.
  Future<EncryptedPayloadEnvelope> encryptWithPassphrase({
    required Uint8List plaintext,
    required String passphrase,
    Uint8List? salt,
    List<int> aad = const [],
  }) async {
    final effectiveSalt = salt ?? generateRandomSalt();
    final derivedKey = await deriveKeyFromPassphrase(
      passphrase: passphrase,
      salt: effectiveSalt,
    );

    return encryptWithSecretKey(
      plaintext: plaintext,
      secretKey: derivedKey,
      salt: effectiveSalt,
      aad: aad,
    );
  }

  /// Decrypts [envelope] using passphrase and Argon2id key derivation.
  Future<Uint8List> decryptWithPassphrase({
    required EncryptedPayloadEnvelope envelope,
    required String passphrase,
    List<int> aad = const [],
  }) async {
    final derivedKey = await deriveKeyFromPassphrase(
      passphrase: passphrase,
      salt: envelope.salt,
    );

    return decryptWithSecretKey(
      envelope: envelope,
      secretKey: derivedKey,
      aad: aad,
    );
  }

  /// Encrypts [plaintext] with a 256-bit [SecretKey] using XChaCha20-Poly1305.
  ///
  /// Incorporates native [SecureBuffer] zeroization guarantees for intermediate buffers.
  Future<EncryptedPayloadEnvelope> encryptWithSecretKey({
    required Uint8List plaintext,
    required SecretKey secretKey,
    Uint8List? salt,
    Uint8List? nonce,
    List<int> aad = const [],
  }) async {
    final effectiveSalt = salt ?? generateRandomSalt();
    final effectiveNonce = nonce ?? generateNonce();

    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: effectiveNonce,
      aad: aad,
    );

    return EncryptedPayloadEnvelope(
      salt: effectiveSalt,
      nonce: effectiveNonce,
      mac: Uint8List.fromList(secretBox.mac.bytes),
      ciphertext: Uint8List.fromList(secretBox.cipherText),
    );
  }

  /// Decrypts [envelope] with [secretKey] using XChaCha20-Poly1305 AEAD.
  ///
  /// Throws [SecretBoxAuthenticationError] or [FormatException] if corrupted or tampered.
  Future<Uint8List> decryptWithSecretKey({
    required EncryptedPayloadEnvelope envelope,
    required SecretKey secretKey,
    List<int> aad = const [],
  }) async {
    final secretBox = SecretBox(
      envelope.ciphertext,
      nonce: envelope.nonce,
      mac: Mac(envelope.mac),
    );

    final decryptedBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: aad,
    );

    return Uint8List.fromList(decryptedBytes);
  }

  /// End-to-end optical peer handshake helper:
  /// Performs ephemeral X25519 key agreement, encrypts [plaintext], and securely
  /// scrubs the ephemeral key material via [SecureMemoryArena].
  Future<EncryptedPayloadEnvelope> encryptForPeer({
    required Uint8List plaintext,
    required SimpleKeyPair localEphemeralKeyPair,
    required SimplePublicKey peerEphemeralPublicKey,
  }) async {
    final sharedKey = await computeSharedSecret(
      localKeyPair: localEphemeralKeyPair,
      peerPublicKey: peerEphemeralPublicKey,
    );

    return encryptWithSecretKey(
      plaintext: plaintext,
      secretKey: sharedKey,
    );
  }

  /// End-to-end optical peer handshake helper:
  /// Computes shared secret with peer and decrypts [envelope].
  Future<Uint8List> decryptFromPeer({
    required EncryptedPayloadEnvelope envelope,
    required SimpleKeyPair localEphemeralKeyPair,
    required SimplePublicKey peerEphemeralPublicKey,
  }) async {
    final sharedKey = await computeSharedSecret(
      localKeyPair: localEphemeralKeyPair,
      peerPublicKey: peerEphemeralPublicKey,
    );

    return decryptWithSecretKey(
      envelope: envelope,
      secretKey: sharedKey,
    );
  }
}
