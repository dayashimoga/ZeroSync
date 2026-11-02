import 'package:airdrop_qr/domain/services/transport_advisor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransportAdvisorService Specs', () {
    const advisor = TransportAdvisorService();

    test('Recommends Single Static QR for small payloads (< 800 bytes)', () {
      final advice = advisor.evaluate(payloadSizeBytes: 500);

      expect(advice.mode, OpticalTransferMode.staticQr);
      expect(advice.title, 'Single-Frame Optical QR');
      expect(advice.enableCompression, isTrue);
      expect(advice.recommendedFps, 0);
    });

    test(
        'Recommends Monochrome Fountain Stream for medium files (1 KB to 24 KB)',
        () {
      final advice = advisor.evaluate(payloadSizeBytes: 12 * 1024);

      expect(advice.mode, OpticalTransferMode.monochromeFountain);
      expect(advice.title, 'Monochrome LT Fountain Stream');
      expect(advice.enableCompression, isTrue);
      expect(advice.recommendedFps, 12);
      expect(advice.recommendedChunkSize, 180);
    });

    test('Recommends 3x RGB Spectral Multiplex Mode for large files (>= 25 KB)',
        () {
      final advice = advisor.evaluate(payloadSizeBytes: 50 * 1024);

      expect(advice.mode, OpticalTransferMode.rgbMultiplexBurst);
      expect(advice.title, '3x RGB Spectral Multiplex Mode');
      expect(advice.recommendedFps, 15);
      expect(advice.recommendedChunkSize, 320);
    });

    test('Recommends SLIP-39 Multi-Share Deck for cryptographic seeds', () {
      final advice = advisor.evaluate(
        payloadSizeBytes: 32,
        isCryptographicKeyOrSeed: true,
      );

      expect(advice.mode, OpticalTransferMode.slip39Deck);
      expect(advice.title, 'SLIP-39 Shamir Multi-Share Deck');
    });

    test('Throws ArgumentError on negative payload size', () {
      expect(
        () => advisor.evaluate(payloadSizeBytes: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
