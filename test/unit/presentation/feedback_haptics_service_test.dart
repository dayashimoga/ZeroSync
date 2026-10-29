import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/services/feedback_haptics_service.dart';

class MockPlatformHapticsDriver implements PlatformHapticsDriver {
  int lightCount = 0;
  int mediumCount = 0;
  int heavyCount = 0;
  int selectionCount = 0;
  int vibrateCount = 0;

  @override
  Future<void> lightImpact() async => lightCount++;

  @override
  Future<void> mediumImpact() async => mediumCount++;

  @override
  Future<void> heavyImpact() async => heavyCount++;

  @override
  Future<void> selectionClick() async => selectionCount++;

  @override
  Future<void> vibrate() async => vibrateCount++;

  void reset() {
    lightCount = 0;
    mediumCount = 0;
    heavyCount = 0;
    selectionCount = 0;
    vibrateCount = 0;
  }
}

class MockPlatformAudioDriver implements PlatformAudioDriver {
  final List<SystemSoundType> playedSystemSounds = <SystemSoundType>[];
  final List<ZeroSyncAudioChime> playedSyntheticChimes = <ZeroSyncAudioChime>[];
  final List<Uint8List> playedBuffers = <Uint8List>[];

  @override
  Future<void> playSystemSound(SystemSoundType soundType) async {
    playedSystemSounds.add(soundType);
  }

  @override
  Future<void> playSyntheticTone(ZeroSyncAudioChime chime, Uint8List wavBytes) async {
    playedSyntheticChimes.add(chime);
    playedBuffers.add(wavBytes);
  }

  void reset() {
    playedSystemSounds.clear();
    playedSyntheticChimes.clear();
    playedBuffers.clear();
  }
}

void main() {
  group('SyntheticChimeGenerator PCM Specs', () {
    const generator = SyntheticChimeGenerator();

    test('Generates mathematically sound 16-bit PCM RIFF/WAV header', () {
      final wav = generator.generateSineTone(
        frequencyHz: 440.0,
        durationMs: 50.0,
        sampleRate: 44100.0,
        volume: 0.8,
      );

      // Verify minimum header size: 44 bytes
      expect(wav.length, greaterThan(44));

      final byteData = ByteData.sublistView(wav);

      // RIFF header
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      final chunkSize = byteData.getUint32(4, Endian.little);
      expect(chunkSize, equals(wav.length - 8));
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));

      // fmt subchunk
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));
      expect(byteData.getUint32(16, Endian.little), equals(16)); // PCM chunk size
      expect(byteData.getUint16(20, Endian.little), equals(1));  // AudioFormat = PCM
      expect(byteData.getUint16(22, Endian.little), equals(1));  // Mono = 1 channel
      expect(byteData.getUint32(24, Endian.little), equals(44100)); // SampleRate
      expect(byteData.getUint32(28, Endian.little), equals(88200)); // ByteRate (44100 * 1 * 2)
      expect(byteData.getUint16(32, Endian.little), equals(2));     // BlockAlign
      expect(byteData.getUint16(34, Endian.little), equals(16));    // BitsPerSample

      // data subchunk
      expect(String.fromCharCodes(wav.sublist(36, 40)), equals('data'));
      final subchunk2Size = byteData.getUint32(40, Endian.little);
      expect(subchunk2Size, equals(wav.length - 44));
    });

    test('Generates specialized WAV buffers for all chime types', () {
      final successWav = generator.generateChimeWav(ZeroSyncAudioChime.scanSuccess);
      final chunkWav = generator.generateChimeWav(ZeroSyncAudioChime.chunkReceived);
      final streamWav = generator.generateChimeWav(ZeroSyncAudioChime.streamComplete);
      final alertWav = generator.generateChimeWav(ZeroSyncAudioChime.warningAlert);
      final noneWav = generator.generateChimeWav(ZeroSyncAudioChime.none);

      expect(successWav.length, greaterThan(44));
      expect(chunkWav.length, greaterThan(44));
      expect(streamWav.length, greaterThan(44));
      expect(alertWav.length, greaterThan(44));
      expect(noneWav.isEmpty, isTrue);

      // Verify that shorter duration chime results in smaller byte buffer
      expect(chunkWav.length, lessThan(streamWav.length));
    });
  });

  group('FeedbackHapticsService Muting, Throttling & Triggers Specs', () {
    late MockPlatformHapticsDriver mockHaptics;
    late MockPlatformAudioDriver mockAudio;
    late FeedbackHapticsService service;

    setUp(() {
      mockHaptics = MockPlatformHapticsDriver();
      mockAudio = MockPlatformAudioDriver();
      service = FeedbackHapticsService(
        hapticsDriver: mockHaptics,
        audioDriver: mockAudio,
        minHapticInterval: const Duration(milliseconds: 100),
        minAudioInterval: const Duration(milliseconds: 100),
      );
    });

    test('Initializes with active haptics, active audio, and full volume', () {
      expect(service.hapticsEnabled, isTrue);
      expect(service.audioEnabled, isTrue);
      expect(service.volume, equals(1.0));
      expect(service.isMuted, isFalse);
      expect(service.isHapticsMuted, isFalse);
    });

    test('Dispatches scan success multi-sensory events', () async {
      await service.triggerScanSuccess();

      expect(mockHaptics.mediumCount, equals(1));
      expect(mockAudio.playedSyntheticChimes, equals(<ZeroSyncAudioChime>[ZeroSyncAudioChime.scanSuccess]));
    });

    test('Dispatches chunk received micro-tactile and tick events', () async {
      await service.triggerChunkReceived();

      expect(mockHaptics.lightCount, equals(1));
      expect(mockAudio.playedSyntheticChimes, equals(<ZeroSyncAudioChime>[ZeroSyncAudioChime.chunkReceived]));
    });

    test('Dispatches stream complete heavy impact and completion tone', () async {
      await service.triggerStreamComplete();

      expect(mockHaptics.heavyCount, equals(1));
      expect(mockAudio.playedSyntheticChimes, equals(<ZeroSyncAudioChime>[ZeroSyncAudioChime.streamComplete]));
    });

    test('Dispatches security warning vibration and warning alert chime', () async {
      await service.triggerSecurityWarning();

      expect(mockHaptics.vibrateCount, equals(1));
      expect(mockAudio.playedSyntheticChimes, equals(<ZeroSyncAudioChime>[ZeroSyncAudioChime.warningAlert]));
    });

    test('Dispatches selection click for UI interactions', () async {
      await service.triggerSelection();

      expect(mockHaptics.selectionCount, equals(1));
      expect(mockAudio.playedSyntheticChimes.isEmpty, isTrue);
    });

    test('Throttles rapid successive haptics and audio within cooldown window', () async {
      // Rapid fire 5 events without delay
      await service.triggerChunkReceived();
      await service.triggerChunkReceived();
      await service.triggerChunkReceived();
      await service.triggerChunkReceived();
      await service.triggerChunkReceived();

      // Only the first one passed due to 100ms throttle!
      expect(mockHaptics.lightCount, equals(1));
      expect(mockAudio.playedSyntheticChimes.length, equals(1));

      // Force bypasses throttle
      await service.triggerChunkReceived(force: true);
      expect(mockHaptics.lightCount, equals(2));
      expect(mockAudio.playedSyntheticChimes.length, equals(2));

      // resetThrottle clears timestamp
      service.resetThrottle();
      await service.triggerChunkReceived();
      expect(mockHaptics.lightCount, equals(3));
      expect(mockAudio.playedSyntheticChimes.length, equals(3));
    });

    test('Respects muting and audio disabling controls', () async {
      service.setAudioEnabled(false);
      expect(service.isMuted, isTrue);

      await service.triggerScanSuccess();
      // Haptics still fire
      expect(mockHaptics.mediumCount, equals(1));
      // Audio does NOT play
      expect(mockAudio.playedSyntheticChimes.isEmpty, isTrue);

      // Volume set to 0 also mutes audio
      service.setAudioEnabled(true);
      service.setVolume(0.0);
      expect(service.isMuted, isTrue);

      mockHaptics.reset();
      mockAudio.reset();
      service.resetThrottle();

      await service.triggerScanSuccess();
      expect(mockHaptics.mediumCount, equals(1));
      expect(mockAudio.playedSyntheticChimes.isEmpty, isTrue);
    });

    test('Respects haptic disabling controls', () async {
      service.setHapticsEnabled(false);
      expect(service.isHapticsMuted, isTrue);

      await service.triggerScanSuccess();
      expect(mockHaptics.mediumCount, equals(0));
      expect(mockAudio.playedSyntheticChimes.length, equals(1));
    });

    test('muteAll and unmuteAll controls toggle both sensations', () {
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      service.muteAll();
      expect(service.hapticsEnabled, isFalse);
      expect(service.audioEnabled, isFalse);
      expect(service.isMuted, isTrue);
      expect(service.isHapticsMuted, isTrue);
      expect(notifyCount, equals(1));

      service.unmuteAll();
      expect(service.hapticsEnabled, isTrue);
      expect(service.audioEnabled, isTrue);
      expect(service.isMuted, isFalse);
      expect(service.isHapticsMuted, isFalse);
      expect(notifyCount, equals(2));

      service.toggleAudio();
      expect(service.audioEnabled, isFalse);
      service.toggleHaptics();
      expect(service.hapticsEnabled, isFalse);
    });

    test('Production SystemAudioDriver delegates correctly', () async {
      const driver = SystemAudioDriver();
      // Verify no exception on system sounds
      await driver.playSyntheticTone(ZeroSyncAudioChime.none, Uint8List(0));
    });
  });
}

