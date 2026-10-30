import 'dart:typed_data';

import 'package:airdrop_qr/data/datasources/optical_scanner_datasource.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('OpticalFrameRingBuffer Zero-Allocation Buffer Specs', () {
    test('Initializes with empty state and zero utilization', () {
      final ring = OpticalFrameRingBuffer<String>(4);
      expect(ring.capacity, equals(4));
      expect(ring.size, equals(0));
      expect(ring.isEmpty, isTrue);
      expect(ring.isFull, isFalse);
      expect(ring.dropCount, equals(0));
      expect(ring.utilization, equals(0.0));
      expect(ring.pop(), isNull);
      expect(ring.peek(), isNull);
    });

    test('Pushes and pops items in FIFO order', () {
      final ring = OpticalFrameRingBuffer<String>(3);
      expect(ring.push('A'), isTrue);
      expect(ring.push('B'), isTrue);
      expect(ring.size, equals(2));
      expect(ring.utilization, closeTo(2 / 3, 0.001));
      expect(ring.peek(), equals('A'));

      expect(ring.pop(), equals('A'));
      expect(ring.size, equals(1));
      expect(ring.pop(), equals('B'));
      expect(ring.isEmpty, isTrue);
      expect(ring.pop(), isNull);
    });

    test('Evicts oldest item when buffer is full and increments dropCount', () {
      final ring = OpticalFrameRingBuffer<int>(3);
      expect(ring.push(1), isTrue);
      expect(ring.push(2), isTrue);
      expect(ring.push(3), isTrue);
      expect(ring.isFull, isTrue);
      expect(ring.dropCount, equals(0));

      // 4th push evicts 1
      expect(ring.push(4), isFalse);
      expect(ring.size, equals(3));
      expect(ring.dropCount, equals(1));
      expect(ring.peek(), equals(2));

      // 5th push evicts 2
      expect(ring.push(5), isFalse);
      expect(ring.dropCount, equals(2));
      expect(ring.peek(), equals(3));

      expect(ring.pop(), equals(3));
      expect(ring.pop(), equals(4));
      expect(ring.pop(), equals(5));
      expect(ring.isEmpty, isTrue);
    });

    test('Clears all items and resets pointers', () {
      final ring = OpticalFrameRingBuffer<String>(5);
      ring.push('X');
      ring.push('Y');
      ring.push('Z');
      expect(ring.size, equals(3));

      ring.clear();
      expect(ring.size, equals(0));
      expect(ring.isEmpty, isTrue);
      expect(ring.pop(), isNull);
    });
  });

  group('OpticalScannerConfig & Entities', () {
    test('Default constructor sets expected air-gapped stream values', () {
      const config = OpticalScannerConfig();
      expect(config.engine, equals(OpticalDetectionEngine.auto));
      expect(config.scanningMode, equals(OpticalScanningMode.continuousAirGap));
      expect(config.targetFps, equals(60));
      expect(config.frameBufferSize, equals(128));
      expect(config.supportedFormats, contains(BarcodeFormat.qrCode));
      expect(config.retainRawBytes, isTrue);
      expect(config.invertDetection, isFalse);
    });

    test('copyWith properly updates specific properties', () {
      const config = OpticalScannerConfig();
      final updated = config.copyWith(
        engine: OpticalDetectionEngine.appleVision,
        scanningMode: OpticalScanningMode.singleCode,
        targetFps: 30,
        frameBufferSize: 64,
        invertDetection: true,
      );

      expect(updated.engine, equals(OpticalDetectionEngine.appleVision));
      expect(updated.scanningMode, equals(OpticalScanningMode.singleCode));
      expect(updated.targetFps, equals(30));
      expect(updated.frameBufferSize, equals(64));
      expect(updated.invertDetection, isTrue);
      expect(updated.retainRawBytes, isTrue);
    });

    test('Throws assertion on invalid zero or negative parameters', () {
      expect(
        () => OpticalScannerConfig(frameBufferSize: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => OpticalScannerConfig(targetFps: -5),
        throwsA(isA<AssertionError>()),
      );
    });

    test('OpticalScanResult string formatting and properties', () {
      final result = OpticalScanResult(
        rawValue: 'https://zerosync.internal/airgap',
        rawBytes: Uint8List.fromList([1, 2, 3]),
        format: BarcodeFormat.qrCode,
        timestamp: DateTime(2026, 10, 29, 12, 0, 0),
        engineUsed: OpticalDetectionEngine.googleMlKit,
        cornerPoints: const [Offset(0, 0), Offset(100, 100)],
        instantaneousFps: 59.8,
        frameSequence: 42,
        processingLatency: const Duration(milliseconds: 12),
      );

      expect(result.rawValue, equals('https://zerosync.internal/airgap'));
      expect(result.rawBytes, equals(Uint8List.fromList([1, 2, 3])));
      expect(result.format, equals(BarcodeFormat.qrCode));
      expect(result.engineUsed, equals(OpticalDetectionEngine.googleMlKit));
      expect(result.cornerPoints.length, equals(2));
      expect(result.instantaneousFps, closeTo(59.8, 0.01));
      expect(result.frameSequence, equals(42));
      expect(result.processingLatency.inMilliseconds, equals(12));
      expect(result.toString(), contains('seq: 42'));
    });

    test('ScannerMetrics zero factory and string representation', () {
      final metrics = ScannerMetrics.zero();
      expect(metrics.totalFramesReceived, equals(0));
      expect(metrics.totalFramesProcessed, equals(0));
      expect(metrics.droppedFrames, equals(0));
      expect(metrics.currentFps, equals(0.0));
      expect(metrics.averageLatency, equals(Duration.zero));
      expect(metrics.bufferUtilization, equals(0.0));
      expect(metrics.toString(), contains('received: 0'));
    });

    test('OpticalScannerException preserves message and cause', () {
      const exWithoutCause = OpticalScannerException('Camera stream stalled');
      expect(exWithoutCause.message, equals('Camera stream stalled'));
      expect(exWithoutCause.cause, isNull);
      expect(exWithoutCause.toString(),
          equals('OpticalScannerException: Camera stream stalled'));

      final exWithCause = OpticalScannerException(
          'Sensor fault', StateError('Device detached'));
      expect(exWithCause.cause, isA<StateError>());
      expect(exWithCause.toString(),
          contains('(Cause: Bad state: Device detached)'));
    });
  });

  group('OpticalScannerDataSource Lifecycle & Operational Controls', () {
    late OpticalScannerDataSourceImpl dataSource;

    setUp(() {
      dataSource = OpticalScannerDataSourceImpl();
    });

    tearDown(() async {
      await dataSource.dispose();
    });

    test('Initializes with default config and resets state', () async {
      await dataSource.initialize();
      expect(dataSource.isScanning, isFalse);
      expect(dataSource.isPaused, isFalse);
      expect(dataSource.currentMetrics.totalFramesReceived, equals(0));
      expect(dataSource.currentMetrics.totalFramesProcessed, equals(0));
    });

    test('Starts, pauses, resumes and stops scanning lifecycle correctly',
        () async {
      await dataSource.initialize();
      expect(dataSource.isScanning, isFalse);

      await dataSource.startScanning();
      expect(dataSource.isScanning, isTrue);
      expect(dataSource.isPaused, isFalse);

      await dataSource.pauseScanning();
      expect(dataSource.isScanning, isTrue);
      expect(dataSource.isPaused, isTrue);

      await dataSource.resumeScanning();
      expect(dataSource.isScanning, isTrue);
      expect(dataSource.isPaused, isFalse);

      await dataSource.stopScanning();
      expect(dataSource.isScanning, isFalse);
      expect(dataSource.isPaused, isFalse);
    });

    test('Throws OpticalScannerException if operations called after disposal',
        () async {
      await dataSource.dispose();
      expect(() => dataSource.initialize(),
          throwsA(isA<OpticalScannerException>()));
      expect(() => dataSource.startScanning(),
          throwsA(isA<OpticalScannerException>()));
      expect(() => dataSource.pauseScanning(),
          throwsA(isA<OpticalScannerException>()));
      expect(() => dataSource.resumeScanning(),
          throwsA(isA<OpticalScannerException>()));
      expect(() => dataSource.stopScanning(),
          throwsA(isA<OpticalScannerException>()));
    });

    test('Ignores ingestion when not scanning or paused', () async {
      final results = <OpticalScanResult>[];
      final subscription = dataSource.scanStream.listen(results.add);

      // Inactive
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'TEST1', format: BarcodeFormat.qrCode),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(results, isEmpty);

      // Start and ingest
      await dataSource.startScanning();
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'TEST2', format: BarcodeFormat.qrCode),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(results.length, equals(1));
      expect(results.first.rawValue, equals('TEST2'));

      // Pause and ingest
      await dataSource.pauseScanning();
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'TEST3', format: BarcodeFormat.qrCode),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(results.length, equals(1)); // Still 1

      await subscription.cancel();
    });
  });

  group('Optical Ingestion & Scanning Modes', () {
    test('continuousAirGap mode emits all frames without duplicate suppression',
        () async {
      final dataSource = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
          scanningMode: OpticalScanningMode.continuousAirGap,
        ),
      );
      await dataSource.startScanning();

      final results = <OpticalScanResult>[];
      final subscription = dataSource.scanStream.listen(results.add);

      // Ingest 5 identical sequential codes
      for (int i = 0; i < 5; i++) {
        dataSource.ingestRawBarcode(
          Barcode(
            rawValue: 'ZS-CHUNK-001',
            format: BarcodeFormat.qrCode,
            rawBytes: Uint8List.fromList([0xAA, 0xBB]),
            corners: const [Offset(10, 10), Offset(50, 10)],
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(results.length, equals(5));
      expect(results.every((r) => r.rawValue == 'ZS-CHUNK-001'), isTrue);
      expect(results[0].frameSequence, equals(1));
      expect(results[4].frameSequence, equals(5));
      expect(results[0].cornerPoints.length, equals(2));

      await subscription.cancel();
      await dataSource.dispose();
    });

    test('singleCode mode debounces identical codes within cooldown window',
        () async {
      final dataSource = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
          scanningMode: OpticalScanningMode.singleCode,
          duplicateDebounceWindow: Duration(milliseconds: 100),
        ),
      );
      await dataSource.startScanning();

      final results = <OpticalScanResult>[];
      final subscription = dataSource.scanStream.listen(results.add);

      final now = DateTime.now();

      // First code
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'URL_1', format: BarcodeFormat.qrCode),
        captureTime: now,
      );

      // Duplicate within debounce window
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'URL_1', format: BarcodeFormat.qrCode),
        captureTime: now.add(const Duration(milliseconds: 30)),
      );

      // Distinct code within debounce window -> should be emitted
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'URL_2', format: BarcodeFormat.qrCode),
        captureTime: now.add(const Duration(milliseconds: 50)),
      );

      // URL_1 after debounce window has elapsed -> should be emitted
      dataSource.ingestRawBarcode(
        const Barcode(rawValue: 'URL_1', format: BarcodeFormat.qrCode),
        captureTime: now.add(const Duration(milliseconds: 150)),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results.length, equals(3));
      expect(results[0].rawValue, equals('URL_1'));
      expect(results[1].rawValue, equals('URL_2'));
      expect(results[2].rawValue, equals('URL_1'));

      await subscription.cancel();
      await dataSource.dispose();
    });

    test('batchMode records each unique code exactly once', () async {
      final dataSource = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
          scanningMode: OpticalScanningMode.batchMode,
        ),
      );
      await dataSource.startScanning();

      final results = <OpticalScanResult>[];
      final subscription = dataSource.scanStream.listen(results.add);

      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'ITEM-A', format: BarcodeFormat.qrCode));
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'ITEM-B', format: BarcodeFormat.qrCode));
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'ITEM-A', format: BarcodeFormat.qrCode));
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'ITEM-C', format: BarcodeFormat.qrCode));
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'ITEM-B', format: BarcodeFormat.qrCode));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(results.length, equals(3));
      expect(results.map((r) => r.rawValue).toList(),
          equals(['ITEM-A', 'ITEM-B', 'ITEM-C']));

      await subscription.cancel();
      await dataSource.dispose();
    });

    test('Filters unsupported formats and empty rawValues', () async {
      final dataSource = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
          supportedFormats: [BarcodeFormat.qrCode],
        ),
      );
      await dataSource.startScanning();

      final results = <OpticalScanResult>[];
      final subscription = dataSource.scanStream.listen(results.add);

      // Null or empty
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: null, format: BarcodeFormat.qrCode));
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: '', format: BarcodeFormat.qrCode));

      // Unsupported format (e.g. Code 128)
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'BARCODE128', format: BarcodeFormat.code128));

      // Supported QR Code
      dataSource.ingestRawBarcode(
          const Barcode(rawValue: 'VALID_QR', format: BarcodeFormat.qrCode));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(results.length, equals(1));
      expect(results.first.rawValue, equals('VALID_QR'));

      await subscription.cancel();
      await dataSource.dispose();
    });

    test('Respects retainRawBytes toggle', () async {
      final withBytes = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(retainRawBytes: true),
      );
      final withoutBytes = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(retainRawBytes: false),
      );

      await withBytes.startScanning();
      await withoutBytes.startScanning();

      final resultsWith = <OpticalScanResult>[];
      final resultsWithout = <OpticalScanResult>[];

      withBytes.scanStream.listen(resultsWith.add);
      withoutBytes.scanStream.listen(resultsWithout.add);

      final dummyBytes = Uint8List.fromList([1, 2, 3, 4]);
      withBytes.ingestRawBarcode(
        Barcode(
            rawValue: 'TEST',
            format: BarcodeFormat.qrCode,
            rawBytes: dummyBytes),
      );
      withoutBytes.ingestRawBarcode(
        Barcode(
            rawValue: 'TEST',
            format: BarcodeFormat.qrCode,
            rawBytes: dummyBytes),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resultsWith.first.rawBytes, isNotNull);
      expect(resultsWithout.first.rawBytes, isNull);

      await withBytes.dispose();
      await withoutBytes.dispose();
    });
  });

  group('Optical Engine Resolution & BarcodeCapture Ingestion', () {
    test('Resolves explicit and auto detection engines properly', () async {
      final dsMlKit = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
            engine: OpticalDetectionEngine.googleMlKit),
      );
      final dsVision = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
            engine: OpticalDetectionEngine.appleVision),
      );
      final dsAuto = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(engine: OpticalDetectionEngine.auto),
      );

      await dsMlKit.startScanning();
      await dsVision.startScanning();
      await dsAuto.startScanning();

      final resMlKit = <OpticalScanResult>[];
      final resVision = <OpticalScanResult>[];
      final resAuto = <OpticalScanResult>[];

      dsMlKit.scanStream.listen(resMlKit.add);
      dsVision.scanStream.listen(resVision.add);
      dsAuto.scanStream.listen(resAuto.add);

      dsMlKit.ingestRawBarcode(
          const Barcode(rawValue: 'M', format: BarcodeFormat.qrCode));
      dsVision.ingestRawBarcode(
          const Barcode(rawValue: 'V', format: BarcodeFormat.qrCode));
      dsAuto.ingestRawBarcode(
          const Barcode(rawValue: 'A', format: BarcodeFormat.qrCode));

      // Test engine override
      dsAuto.ingestRawBarcode(
        const Barcode(rawValue: 'OVERRIDE', format: BarcodeFormat.qrCode),
        engineOverride: OpticalDetectionEngine.appleVision,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(resMlKit.first.engineUsed,
          equals(OpticalDetectionEngine.googleMlKit));
      expect(resVision.first.engineUsed,
          equals(OpticalDetectionEngine.appleVision));
      expect(resAuto.first.engineUsed, isA<OpticalDetectionEngine>());
      expect(resAuto[1].engineUsed, equals(OpticalDetectionEngine.appleVision));

      await dsMlKit.dispose();
      await dsVision.dispose();
      await dsAuto.dispose();
    });

    test('Ingests multiple barcodes from BarcodeCapture', () async {
      final dataSource = OpticalScannerDataSourceImpl();
      await dataSource.startScanning();

      final results = <OpticalScanResult>[];
      final metricsList = <ScannerMetrics>[];

      dataSource.scanStream.listen(results.add);
      dataSource.metricsStream.listen(metricsList.add);

      const capture = BarcodeCapture(
        barcodes: [
          Barcode(rawValue: 'QR1', format: BarcodeFormat.qrCode),
          Barcode(rawValue: 'QR2', format: BarcodeFormat.qrCode),
        ],
        size: Size(1920, 1080),
      );

      dataSource.ingestCapture(capture);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results.length, equals(2));
      expect(results[0].rawValue, equals('QR1'));
      expect(results[1].rawValue, equals('QR2'));
      expect(dataSource.currentMetrics.totalFramesReceived, equals(1));
      expect(dataSource.currentMetrics.totalFramesProcessed, equals(2));
      expect(metricsList.isNotEmpty, isTrue);

      await dataSource.dispose();
    });
  });

  group('High-Throughput 60 FPS Emulation & Telemetry Gates', () {
    test(
        'Simulates rapid 60 FPS ingestion with ring-buffer saturation & metrics tracking',
        () async {
      // Configure small buffer of 16 to verify overflow and drop counting
      final dataSource = OpticalScannerDataSourceImpl(
        config: const OpticalScannerConfig(
          frameBufferSize: 16,
          targetFps: 60,
          scanningMode: OpticalScanningMode.continuousAirGap,
        ),
      );
      await dataSource.startScanning();

      final results = <OpticalScanResult>[];
      dataSource.scanStream.listen(results.add);

      final startTime =
          DateTime.now().subtract(const Duration(milliseconds: 700));

      // Feed 40 frames at simulated 60 FPS intervals (approx 16.6ms each)
      for (int i = 0; i < 40; i++) {
        final frameTime = startTime.add(Duration(microseconds: i * 16666));
        dataSource.ingestRawBarcode(
          Barcode(
            rawValue: 'AIRGAP-FRAME-${i.toString().padLeft(3, '0')}',
            format: BarcodeFormat.qrCode,
          ),
          captureTime: frameTime,
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(results.length, equals(40));
      final metrics = dataSource.currentMetrics;
      expect(metrics.totalFramesProcessed, equals(40));
      // Since buffer size is 16, 40 pushes will cause 24 drops
      expect(metrics.droppedFrames, equals(24));
      expect(metrics.currentFps, greaterThan(0.0));
      expect(metrics.averageLatency, greaterThanOrEqualTo(Duration.zero));
      expect(metrics.bufferUtilization, equals(1.0));

      // Reset metrics
      dataSource.resetMetrics();
      expect(dataSource.currentMetrics.totalFramesProcessed, equals(0));
      expect(dataSource.currentMetrics.droppedFrames, equals(0));
      expect(dataSource.currentMetrics.bufferUtilization, equals(0.0));

      await dataSource.dispose();
    });
  });
}
