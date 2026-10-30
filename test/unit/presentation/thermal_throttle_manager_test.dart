import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/services/thermal_throttle_manager.dart';

void main() {
  group('ThermalThrottleManager Specs', () {
    late ThermalThrottleManager manager;
    bool suspendCalled = false;
    bool resumeCalled = false;

    setUp(() {
      suspendCalled = false;
      resumeCalled = false;
      manager = ThermalThrottleManager(
        inactivityTimeout: const Duration(minutes: 3),
        inactivityCheckInterval: const Duration(milliseconds: 50),
        onSuspend: () => suspendCalled = true,
        onResume: () => resumeCalled = true,
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test(
        'Initializes with nominal thermal state and 3-minute inactivity timeout',
        () {
      expect(manager.thermalState, equals(DeviceThermalState.nominal));
      expect(manager.inactivityTimeout, equals(const Duration(minutes: 3)));
      expect(manager.isSuspendedDueToInactivity, isFalse);
      expect(manager.isManuallyPaused, isFalse);
      expect(manager.isCameraStreamingActive, isTrue);
      expect(manager.activePolicy.targetFps, equals(60));
      expect(manager.activePolicy.downsampleFactor, equals(1));
    });

    test('Maps core temperatures to appropriate thermal states and policies',
        () {
      // 36°C -> Nominal
      manager.updateTemperature(36.0);
      expect(manager.thermalState, equals(DeviceThermalState.nominal));
      expect(manager.activePolicy.downsampleFactor, equals(1));
      expect(manager.activePolicy.targetFps, equals(60));

      // 40°C -> Fair
      manager.updateTemperature(40.0);
      expect(manager.thermalState, equals(DeviceThermalState.fair));
      expect(manager.activePolicy.downsampleFactor, equals(2));
      expect(manager.activePolicy.targetFps, equals(30));

      // 45°C -> Serious
      manager.updateTemperature(45.0);
      expect(manager.thermalState, equals(DeviceThermalState.serious));
      expect(manager.activePolicy.downsampleFactor, equals(4));
      expect(manager.activePolicy.targetFps, equals(15));

      // 49°C -> Critical
      manager.updateTemperature(49.0);
      expect(manager.thermalState, equals(DeviceThermalState.critical));
      expect(manager.activePolicy.downsampleFactor, equals(8));
      expect(manager.activePolicy.targetFps, equals(5));
    });

    test('Downsamples frames according to active thermal policy', () {
      final baseTime = DateTime(2026, 1, 1, 12, 0, 0);

      // In nominal state, frames at 20ms intervals all pass
      expect(manager.shouldProcessFrame(frameTimestamp: baseTime), isTrue);
      expect(
        manager.shouldProcessFrame(
            frameTimestamp: baseTime.add(const Duration(milliseconds: 20))),
        isTrue,
      );
      expect(manager.totalFramesProcessed, equals(2));
      expect(manager.totalFramesThermalDropped, equals(0));

      // Switch to fair: downsampleFactor = 2
      manager.setThermalState(DeviceThermalState.fair);
      manager.resetMetrics();

      var time = baseTime;
      // Frame 1: 1 % 2 != 0 -> drop
      time = time.add(const Duration(milliseconds: 40));
      expect(manager.shouldProcessFrame(frameTimestamp: time), isFalse);

      // Frame 2: 2 % 2 == 0 and dt >= 33ms -> accept
      time = time.add(const Duration(milliseconds: 40));
      expect(manager.shouldProcessFrame(frameTimestamp: time), isTrue);

      // Frame 3: 3 % 2 != 0 -> drop
      time = time.add(const Duration(milliseconds: 40));
      expect(manager.shouldProcessFrame(frameTimestamp: time), isFalse);

      expect(manager.totalFramesEvaluated, equals(3));
      expect(manager.totalFramesProcessed, equals(1));
      expect(manager.totalFramesThermalDropped, equals(2));
    });

    test(
        'Suppresses frames when frame arrival interval is below minFrameInterval',
        () {
      final baseTime = DateTime(2026, 1, 1, 12, 0, 0);
      manager.setThermalState(DeviceThermalState.nominal);
      manager.resetMetrics();

      // First frame
      expect(manager.shouldProcessFrame(frameTimestamp: baseTime), isTrue);

      // Second frame arrives after only 5ms (nominal minFrameInterval is 16ms)
      expect(
        manager.shouldProcessFrame(
            frameTimestamp: baseTime.add(const Duration(milliseconds: 5))),
        isFalse,
      );
      expect(manager.totalFramesThermalDropped, equals(1));
    });

    test(
        'Suspends camera stream after 3 minutes of inactivity and wakes on interaction',
        () {
      final startTime = manager.lastActivityTime;

      // At 2 minutes, stream remains active
      manager.checkInactivity(
          currentTime: startTime.add(const Duration(minutes: 2)));
      expect(manager.isSuspendedDueToInactivity, isFalse);
      expect(manager.isCameraStreamingActive, isTrue);
      expect(suspendCalled, isFalse);

      // At 3 minutes, stream suspends
      manager.checkInactivity(
          currentTime: startTime.add(const Duration(minutes: 3, seconds: 1)));
      expect(manager.isSuspendedDueToInactivity, isTrue);
      expect(manager.isCameraStreamingActive, isFalse);
      expect(suspendCalled, isTrue);

      // While suspended, frames are automatically dropped
      expect(manager.shouldProcessFrame(), isFalse);

      // User interacts or scans code -> resets inactivity and wakes stream
      manager.recordInteraction();
      expect(manager.isSuspendedDueToInactivity, isFalse);
      expect(manager.isCameraStreamingActive, isTrue);
      expect(resumeCalled, isTrue);
    });

    test('Periodic timer triggers sleep on idle timeout', () async {
      final fastManager = ThermalThrottleManager(
        inactivityTimeout: const Duration(milliseconds: 80),
        inactivityCheckInterval: const Duration(milliseconds: 20),
        onSuspend: () => suspendCalled = true,
      );

      expect(fastManager.isSuspendedDueToInactivity, isFalse);

      // Wait past timeout
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(fastManager.isSuspendedDueToInactivity, isTrue);
      expect(suspendCalled, isTrue);

      fastManager.dispose();
    });

    test('Manual pause stops camera streaming and resumes correctly', () {
      manager.setManuallyPaused(true);
      expect(manager.isCameraStreamingActive, isFalse);
      expect(manager.shouldProcessFrame(), isFalse);

      manager.setManuallyPaused(false);
      expect(manager.isCameraStreamingActive, isTrue);
    });
  });
}
