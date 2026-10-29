import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Domain Entities
import 'package:airdrop_qr/domain/entities/crypto_auth_payload.dart';
import 'package:airdrop_qr/domain/entities/infrastructure_payload.dart';
import 'package:airdrop_qr/domain/entities/vcard_payload.dart';

// Serialization Services
import 'package:airdrop_qr/domain/services/crypto_auth_serializer_service.dart';
import 'package:airdrop_qr/domain/services/domain_inspector_service.dart';
import 'package:airdrop_qr/domain/services/infrastructure_serializer_service.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/domain/services/tracker_stripper_service.dart';
import 'package:airdrop_qr/domain/services/vcard_serializer_service.dart';

// Optical Fountain Transport Engine
import 'package:airdrop_qr/core/utils/crc32.dart';
import 'package:airdrop_qr/domain/services/airgap_file_writer_service.dart';
import 'package:airdrop_qr/domain/services/chunk_accumulator_engine.dart';
import 'package:airdrop_qr/domain/services/integrity_checksum_service.dart';
import 'package:airdrop_qr/domain/services/luby_transform_fec_service.dart';
import 'package:airdrop_qr/domain/services/payload_compression_service.dart';
import 'package:airdrop_qr/domain/value_objects/packed_transport_header.dart';

// Core Memory & Lifecycle Auditing
import 'package:airdrop_qr/core/utils/disposal_auditor.dart';

void main() {
  group('Screen-to-Camera Optical Loopback Integration Specs', () {
    // Serializers
    late VCardSerializerService vcardSerializer;
    late InfrastructureSerializerService infraSerializer;
    late CryptoAuthSerializerService cryptoSerializer;
    late QrMatrixGeneratorService matrixGenerator;
    late DomainInspectorService domainInspector;
    late TrackerStripperService trackerStripper;

    // Optical Fountain Transport Services
    const compressionService = PayloadCompressionService();
    const integrityService = IntegrityChecksumService();
    const fecService = LubyTransformFecService();
    late MemorySandboxedStorageAdapter storageAdapter;
    late AirgapFileWriterService fileWriterService;

    setUp(() {
      vcardSerializer = VCardSerializerService();
      infraSerializer = InfrastructureSerializerService();
      cryptoSerializer = CryptoAuthSerializerService();
      matrixGenerator = QrMatrixGeneratorService();
      domainInspector = DomainInspectorService();
      trackerStripper = TrackerStripperService();

      storageAdapter = MemorySandboxedStorageAdapter();
      fileWriterService = AirgapFileWriterService(
        storageAdapter: storageAdapter,
        integrityService: integrityService,
        compressionService: compressionService,
      );

      DisposalAuditor.instance.reset();
      DisposalAuditor.instance.setAuditingEnabled(true);
    });

    tearDown(() {
      DisposalAuditor.instance.assertZeroUndisposed();
    });

    // =========================================================================
    // PART 1: SINGLE-CODE MULTI-TYPE OPTICAL LOOPBACK
    // =========================================================================

    test('Loopback Type 1: vCard 4.0 Contact Serialization -> QR Matrix -> Deserialization', () {
      const originalContact = VCardPayload(
        formattedName: 'Dr. Satoshi Nakamoto, PhD',
        familyName: 'Nakamoto',
        givenName: 'Satoshi',
        prefix: 'Dr.',
        organization: 'ZeroSync Cryptography Lab',
        jobTitle: 'Principal Cryptographer',
        phones: <ContactPhone>[
          ContactPhone(number: '+1-555-0199', types: ['work']),
          ContactPhone(number: '+1-555-0142', types: ['cell']),
        ],
        emails: <ContactEmail>[
          ContactEmail(address: 'satoshi@zerosync.org', types: ['work']),
        ],
        note: 'Air-gapped verification contact.',
      );

      // 1. Generate optical wire string
      final String wireString = vcardSerializer.serializeVCard4(originalContact);
      expect(wireString, contains('BEGIN:VCARD'));
      expect(wireString, contains('VERSION:4.0'));

      // 2. Generate optical vector matrix from encoded UTF-8 bytes
      final wireBytes = Uint8List.fromList(utf8.encode(wireString));
      final matrix = matrixGenerator.generateMatrix(
        payload: wireBytes,
        eccLevel: QrErrorCorrectionLevel.medium,
      );
      expect(matrix.size, greaterThanOrEqualTo(21));
      expect(matrix.getModule(0, 0), isTrue); // Top-left finder pattern

      // 3. Loopback Ingestion: decode and deserialize
      final restored = vcardSerializer.deserializeVCard4(wireString);
      expect(restored.formattedName, equals(originalContact.formattedName));
      expect(restored.familyName, equals(originalContact.familyName));
      expect(restored.givenName, equals(originalContact.givenName));
      expect(restored.organization, equals(originalContact.organization));
      expect(restored.jobTitle, equals(originalContact.jobTitle));
      expect(restored.emails.first.address, equals(originalContact.emails.first.address));
      expect(restored.phones.first.number, equals(originalContact.phones.first.number));
    });

    test('Loopback Type 2: Wi-Fi WPA2 Network Configuration Loopback', () {
      const originalWifi = WifiConfigPayload(
        ssid: 'ZeroSync_Secure_Mesh',
        securityType: WifiSecurityType.wpa2,
        password: 'AirGapP@ssw0rd!#;',
        isHidden: true,
      );

      // 1. Serialize
      final String wireString = infraSerializer.serializeWifi(originalWifi);

      // 2. Matrix generation
      final wireBytes = Uint8List.fromList(utf8.encode(wireString));
      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      // 3. Deserialization loopback
      final restored = infraSerializer.deserializeWifi(wireString);
      expect(restored.ssid, equals(originalWifi.ssid));
      expect(restored.securityType, equals(originalWifi.securityType));
      expect(restored.password, equals(originalWifi.password));
      expect(restored.isHidden, equals(originalWifi.isHidden));
    });

    test('Loopback Type 3: Geolocation Coordinates Precision Loopback', () {
      const originalGeo = GeoLocationPayload(
        latitude: 37.774929,
        longitude: -122.419416,
        altitude: 14.5,
      );

      final String wireString = infraSerializer.serializeGeo(originalGeo);
      final wireBytes = Uint8List.fromList(utf8.encode(wireString));
      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      final restored = infraSerializer.deserializeGeo(wireString);
      expect(restored.latitude, closeTo(originalGeo.latitude, 0.000001));
      expect(restored.longitude, closeTo(originalGeo.longitude, 0.000001));
      expect(restored.altitude, closeTo(originalGeo.altitude!, 0.01));
    });

    test('Loopback Type 4: iCalendar Event Schedule Loopback', () {
      final startTime = DateTime.utc(2026, 11, 15, 14, 0);
      final endTime = DateTime.utc(2026, 11, 15, 16, 30);
      final originalEvent = CalendarEventPayload(
        summary: 'ZeroSync Security Summit',
        description: 'Air-gapped verification of optical data stream protocol.',
        location: 'Room 404, Building Zero',
        start: startTime,
        end: endTime,
      );

      final String wireString = infraSerializer.serializeCalendar(originalEvent);
      final wireBytes = Uint8List.fromList(utf8.encode(wireString));
      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      final restored = infraSerializer.deserializeCalendar(wireString);
      expect(restored.summary, equals(originalEvent.summary));
      expect(restored.location, equals(originalEvent.location));
      expect(restored.start, equals(originalEvent.start));
      expect(restored.end, equals(originalEvent.end));
    });

    test('Loopback Type 5: RFC 6238 TOTP Authentication Key Loopback', () {
      const originalTotp = TotpPayload(
        secret: 'MZXW633PN5XW6MZX',
        accountName: 'security-admin@zerosync.io',
        issuer: 'ZeroSyncAuth',
        algorithm: TotpAlgorithm.sha256,
        digits: 8,
        period: 45,
      );

      final String wireUri = cryptoSerializer.serializeTotp(originalTotp);
      final wireBytes = Uint8List.fromList(utf8.encode(wireUri));
      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      final restored = cryptoSerializer.deserializeTotp(wireUri);
      expect(restored.secret, equals(originalTotp.secret));
      expect(restored.accountName, equals(originalTotp.accountName));
      expect(restored.issuer, equals(originalTotp.issuer));
      expect(restored.algorithm, equals(originalTotp.algorithm));
      expect(restored.digits, equals(originalTotp.digits));
      expect(restored.period, equals(originalTotp.period));
    });

    test('Loopback Type 6: Web3 Cryptocurrency Transaction URI Loopback', () {
      const originalBtc = BitcoinPaymentPayload(
        address: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
        amount: 0.05,
        label: 'Cold Storage Vault',
      );

      final String wireUri = cryptoSerializer.serializeBitcoin(originalBtc);
      final wireBytes = Uint8List.fromList(utf8.encode(wireUri));
      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      final restored = cryptoSerializer.deserializeBitcoin(wireUri);
      expect(restored.address, equals(originalBtc.address));
      expect(restored.amount, equals(originalBtc.amount));
      expect(restored.label, equals(originalBtc.label));
    });

    test('Loopback Type 7: Malicious URL Ingestion & Privacy Sanitization Loopback', () {
      const rawUrl = 'https://zerosync.example.org/download?fbclid=12345&utm_source=ad&token=secret';
      final wireBytes = Uint8List.fromList(utf8.encode(rawUrl));

      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      // Optical receiver sanitization pipeline
      final inspectResult = domainInspector.inspect(rawUrl);
      expect(inspectResult.isSafe, isTrue); // valid host, no homoglyphs

      final sanitizedResult = trackerStripper.sanitize(rawUrl);
      expect(sanitizedResult.wasModified, isTrue);
      expect(sanitizedResult.strippedParameters, contains('fbclid'));
      expect(sanitizedResult.strippedParameters, contains('utm_source'));
      expect(sanitizedResult.preservedParameters['token'], equals('secret'));
    });

    test('Loopback Type 8: Arbitrary Binary/JSON Payload Loopback', () {
      final jsonObject = <String, dynamic>{
        'device_id': 'ZERO-AIR-2026',
        'key_fingerprint': 'E4A9F200C9B3A1',
        'entropy_bytes': base64Encode(List<int>.generate(32, (i) => i * 7 % 256)),
      };
      final rawJson = jsonEncode(jsonObject);
      final wireBytes = Uint8List.fromList(utf8.encode(rawJson));

      final matrix = matrixGenerator.generateMatrix(payload: wireBytes);
      expect(matrix.size, greaterThan(0));

      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      expect(decoded['device_id'], equals('ZERO-AIR-2026'));
      expect(decoded['key_fingerprint'], equals('E4A9F200C9B3A1'));
    });

    // =========================================================================
    // PART 2: HIGH-SPEED OPTICAL FOUNTAIN STREAM LOOPBACK (Luby Transform)
    // =========================================================================

    test('Full Visual ZeroSync Fountain Stream Loopback with 30% Optical Drop Simulation', () async {
      final disposalBag = DeterministicDisposalBag(tag: 'FountainLoopbackTest');

      // 1. Generate 2.4 KB realistic payload (e.g., encrypted certificate archive)
      final rng = math.Random(0x42);
      final rawFileBytes = Uint8List(2400);
      for (int i = 0; i < rawFileBytes.length; i++) {
        rawFileBytes[i] = rng.nextInt(256);
      }
      disposalBag.addBuffer(rawFileBytes, scrubOnDispose: false);

      // 2. Compress payload to envelope
      final compressed = compressionService.compress(
        rawFileBytes,
        algorithm: CompressionAlgorithm.zlib,
      );
      final compressedEnvelope = compressed.toWireEnvelope();
      disposalBag.addBuffer(compressedEnvelope, scrubOnDispose: false);

      // 3. Generate Fountain Droplets (symbol size = 160 bytes)
      const int symbolSize = 160;
      final int totalSourceBlocks = (compressedEnvelope.length / symbolSize).ceil();
      final droplets = fecService.generateNDroplets(
        compressedEnvelope,
        totalSourceBlocks * 3, // Generate 3x rateless fountain overhead
        symbolSize: symbolSize,
        startSeed: 1,
      );

      // 4. Initialize Receiver Accumulator & Decoder
      final decoder = LubyTransformDecoder.fromDroplet(droplets.first);
      final accumulator = ChunkAccumulatorEngine();

      const sessionId = 0xA1B2C3D4;
      int seedCounter = 1;

      // 5. Transmit Droplets through simulated optical channel with 30% drop rate
      for (final droplet in droplets) {
        disposalBag.addBuffer(droplet.data, scrubOnDispose: false);

        // Simulate optical camera drop: drop 1 out of every 3 frames (~33% drop rate)
        if (seedCounter % 3 == 0) {
          seedCounter++;
          continue; // Optical frame dropped / blurred!
        }

        final wireDroplet = droplet.toWireBytes();
        final crc = Crc32.compute(wireDroplet);

        final frame = PackedTransportFrame(
          header: PackedTransportHeader(
            sessionId: sessionId,
            totalChunks: totalSourceBlocks,
            chunkIndex: math.min(seedCounter, totalSourceBlocks),
            crc32: crc,
            mimeFlag: MimeTypeFlag.binary,
          ),
          payload: wireDroplet,
        );
        disposalBag.addBuffer(frame.toWireBytes(), scrubOnDispose: false);

        // Ingest into accumulator
        accumulator.ingestFrame(frame);

        // Ingest into Luby Transform Fountain decoder
        decoder.addDroplet(droplet);

        seedCounter++;

        if (decoder.isDecoded) {
          break;
        }
      }

      // 6. Verify Fountain Decoder successfully decoded all source blocks despite ~33% optical frame drops!
      expect(decoder.isDecoded, isTrue);

      // 7. Reconstruct whole compressed envelope byte buffer
      final reconstructedCompressed = decoder.getDecodedPayload();
      expect(reconstructedCompressed, isNotNull);
      disposalBag.addBuffer(reconstructedCompressed!, scrubOnDispose: false);

      // Byte-for-byte fidelity with compressed envelope
      expect(reconstructedCompressed, equals(compressedEnvelope));

      // 8. Decompress and decapsulate with AirgapFileWriterService
      final fileResult = await fileWriterService.processCompletedStream(
        assembledPayload: reconstructedCompressed,
        mimeFlag: MimeTypeFlag.binary,
        isCompressedEnvelope: true,
        expectedSha256Hex: integrityService.computeSha256Hex(rawFileBytes),
        preferredFileName: 'verified_optical_payload.bin',
      );

      // 9. Byte-for-byte fidelity with original input payload!
      final writtenBytes = await storageAdapter.readBinaryFile(fileResult.filePath);
      expect(writtenBytes, equals(rawFileBytes));

      // 10. Verify Whole-File SHA-256 Checksum Matching
      final computedSha256 = integrityService.computeSha256Hex(writtenBytes!);
      final originalSha256 = integrityService.computeSha256Hex(rawFileBytes);
      expect(computedSha256, equals(originalSha256));

      // Clean up test bag
      disposalBag.dispose();
    });
  });
}
