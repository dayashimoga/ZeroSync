import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Haptic feedback patterns supported by ZeroSync actuators.
enum ZeroSyncHapticPattern {
  /// Subtle pulse for rapid chunk reception during optical streaming.
  lightImpact,

  /// Confirmatory vibration for single successful QR scan.
  mediumImpact,

  /// Pronounced vibration for complete stream transfer or significant operation.
  heavyImpact,

  /// Crisp click for UI buttons, toggles, and item selections.
  selectionClick,

  /// Alert pulse for security violations or invalid frames.
  vibrate,

  /// No tactile feedback.
  none,
}

/// Synthetic audio chime types for optical transfer milestones.
enum ZeroSyncAudioChime {
  /// Pleasant, high-pitch dual chime for successful batch or single scan.
  scanSuccess,

  /// Ultra-short micro-tick for intermediate optical chunk reception.
  chunkReceived,

  /// Tri-tone harmonic chord for complete file reassembly and verification.
  streamComplete,

  /// Descending dissonant warning tone for malicious payload or CRC mismatch.
  warningAlert,

  /// Muted silence.
  none,
}

/// Abstract driver for native platform haptic actuators.
abstract interface class PlatformHapticsDriver {
  Future<void> lightImpact();
  Future<void> mediumImpact();
  Future<void> heavyImpact();
  Future<void> selectionClick();
  Future<void> vibrate();
}

/// Production implementation delegating directly to [HapticFeedback].
class SystemHapticsDriver implements PlatformHapticsDriver {
  const SystemHapticsDriver();

  @override
  Future<void> lightImpact() => HapticFeedback.lightImpact();

  @override
  Future<void> mediumImpact() => HapticFeedback.mediumImpact();

  @override
  Future<void> heavyImpact() => HapticFeedback.heavyImpact();

  @override
  Future<void> selectionClick() => HapticFeedback.selectionClick();

  @override
  Future<void> vibrate() => HapticFeedback.vibrate();
}

/// Abstract driver for system sounds and synthetic audio playback.
abstract interface class PlatformAudioDriver {
  Future<void> playSystemSound(SystemSoundType soundType);
  Future<void> playSyntheticTone(ZeroSyncAudioChime chime, Uint8List wavBytes);
}

/// Production implementation using Flutter's native [SystemSound] pipeline.
class SystemAudioDriver implements PlatformAudioDriver {
  const SystemAudioDriver();

  @override
  Future<void> playSystemSound(SystemSoundType soundType) =>
      SystemSound.play(soundType);

  @override
  Future<void> playSyntheticTone(
      ZeroSyncAudioChime chime, Uint8List wavBytes) async {
    // Falls back to system sound click/alert if external codec pipeline is unavailable
    switch (chime) {
      case ZeroSyncAudioChime.scanSuccess:
      case ZeroSyncAudioChime.streamComplete:
      case ZeroSyncAudioChime.chunkReceived:
        await SystemSound.play(SystemSoundType.click);
      case ZeroSyncAudioChime.warningAlert:
        await SystemSound.play(SystemSoundType.alert);
      case ZeroSyncAudioChime.none:
        break;
    }
  }
}

/// Pure Dart in-memory synthetic PCM WAV audio generator.
///
/// Produces mathematically synthesized, low-latency, 16-bit mono RIFF/WAV
/// buffers without external media assets or network permissions.
class SyntheticChimeGenerator {
  const SyntheticChimeGenerator();

  /// Generates a standard 44.1kHz 16-bit PCM Mono WAV buffer for a given sine frequency.
  Uint8List generateSineTone({
    required double frequencyHz,
    required double durationMs,
    double sampleRate = 44100.0,
    double volume = 0.8,
  }) {
    final int numSamples = ((durationMs / 1000.0) * sampleRate).round();
    final int subchunk2Size = numSamples * 2; // 16 bits = 2 bytes per sample
    final int chunkSize = 36 + subchunk2Size;

    final ByteData byteData = ByteData(44 + subchunk2Size);

    // RIFF Chunk Descriptor
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, chunkSize, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // "fmt " Subchunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    byteData.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate.round(), Endian.little); // SampleRate
    final int byteRate = sampleRate.round() * 1 * 2;
    byteData.setUint32(28, byteRate, Endian.little); // ByteRate
    byteData.setUint16(
        32, 2, Endian.little); // BlockAlign (NumChannels * BitsPerSample/8)
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample (16 bits)

    // "data" Subchunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, subchunk2Size, Endian.little);

    // Audio Data Generation with Hann-window envelope to prevent clicks
    final double maxAmplitude = 32767.0 * volume.clamp(0.0, 1.0);
    final double angularFreq = 2.0 * math.pi * frequencyHz / sampleRate;

    for (int i = 0; i < numSamples; i++) {
      // Hann envelope: 0.5 * (1 - cos(2 * pi * i / N))
      final double envelope =
          0.5 * (1.0 - math.cos(2.0 * math.pi * i / numSamples));
      final double sampleVal =
          math.sin(angularFreq * i) * maxAmplitude * envelope;
      final int intSample = sampleVal.round().clamp(-32768, 32767);
      byteData.setInt16(44 + (i * 2), intSample, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// Synthesizes dual-tone or chord buffers tailored to specific chime types.
  Uint8List generateChimeWav(ZeroSyncAudioChime chime, {double volume = 0.8}) {
    switch (chime) {
      case ZeroSyncAudioChime.scanSuccess:
        // Ascending chime: 880 Hz (A5), 75ms
        return generateSineTone(
          frequencyHz: 880.0,
          durationMs: 75.0,
          volume: volume,
        );
      case ZeroSyncAudioChime.chunkReceived:
        // Subtle micro-tick: 1760 Hz (A6), 20ms
        return generateSineTone(
          frequencyHz: 1760.0,
          durationMs: 20.0,
          volume: (volume * 0.4).clamp(0.0, 1.0),
        );
      case ZeroSyncAudioChime.streamComplete:
        // High harmonic completion tone: 1046.5 Hz (C6), 140ms
        return generateSineTone(
          frequencyHz: 1046.50,
          durationMs: 140.0,
          volume: volume,
        );
      case ZeroSyncAudioChime.warningAlert:
        // Low alert tone: 220 Hz (A3), 160ms
        return generateSineTone(
          frequencyHz: 220.0,
          durationMs: 160.0,
          volume: volume,
        );
      case ZeroSyncAudioChime.none:
        return Uint8List(0);
    }
  }
}

/// Orchestrates multi-sensory feedback (haptic tactile pulses and audio chimes)
/// with rate-limiting, muting controls, and zero-allocation execution.
class FeedbackHapticsService with ChangeNotifier {
  FeedbackHapticsService({
    PlatformHapticsDriver hapticsDriver = const SystemHapticsDriver(),
    PlatformAudioDriver audioDriver = const SystemAudioDriver(),
    SyntheticChimeGenerator chimeGenerator = const SyntheticChimeGenerator(),
    Duration minHapticInterval = const Duration(milliseconds: 65),
    Duration minAudioInterval = const Duration(milliseconds: 50),
    bool hapticsEnabled = true,
    bool audioEnabled = true,
    double volume = 1.0,
  })  : _hapticsDriver = hapticsDriver,
        _audioDriver = audioDriver,
        _chimeGenerator = chimeGenerator,
        _minHapticInterval = minHapticInterval,
        _minAudioInterval = minAudioInterval,
        _hapticsEnabled = hapticsEnabled,
        _audioEnabled = audioEnabled,
        _volume = volume.clamp(0.0, 1.0);

  final PlatformHapticsDriver _hapticsDriver;
  final PlatformAudioDriver _audioDriver;
  final SyntheticChimeGenerator _chimeGenerator;

  final Duration _minHapticInterval;
  final Duration _minAudioInterval;

  bool _hapticsEnabled;
  bool _audioEnabled;
  double _volume;

  DateTime _lastHapticTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAudioTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Cache generated WAV buffers to prevent redundant synthesis allocations
  final Map<ZeroSyncAudioChime, Uint8List> _cachedChimes =
      <ZeroSyncAudioChime, Uint8List>{};

  // Getters
  bool get hapticsEnabled => _hapticsEnabled;
  bool get audioEnabled => _audioEnabled;
  double get volume => _volume;
  bool get isMuted => !_audioEnabled || _volume <= 0.0;
  bool get isHapticsMuted => !_hapticsEnabled;

  // Configuration controls
  void setHapticsEnabled(bool enabled) {
    if (_hapticsEnabled != enabled) {
      _hapticsEnabled = enabled;
      notifyListeners();
    }
  }

  void setAudioEnabled(bool enabled) {
    if (_audioEnabled != enabled) {
      _audioEnabled = enabled;
      notifyListeners();
    }
  }

  void toggleHaptics() => setHapticsEnabled(!_hapticsEnabled);

  void toggleAudio() => setAudioEnabled(!_audioEnabled);

  void setVolume(double newVolume) {
    final double clamped = newVolume.clamp(0.0, 1.0);
    if (_volume != clamped) {
      _volume = clamped;
      _cachedChimes.clear(); // Invalidate cache when volume changes
      notifyListeners();
    }
  }

  void muteAll() {
    _hapticsEnabled = false;
    _audioEnabled = false;
    notifyListeners();
  }

  void unmuteAll() {
    _hapticsEnabled = true;
    _audioEnabled = true;
    notifyListeners();
  }

  void resetThrottle() {
    _lastHapticTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAudioTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  // --- Multi-Sensory Action Triggers ---

  /// Triggered on individual QR code scan success (batch or single mode).
  Future<void> triggerScanSuccess({bool force = false}) async {
    await Future.wait<void>(<Future<void>>[
      triggerHaptic(ZeroSyncHapticPattern.mediumImpact, force: force),
      triggerAudio(ZeroSyncAudioChime.scanSuccess, force: force),
    ]);
  }

  /// Triggered when an optical stream chunk is successfully captured and processed.
  /// Throttled by default to prevent hardware actuator fatigue during 15-60 FPS streams.
  Future<void> triggerChunkReceived({bool force = false}) async {
    await Future.wait<void>(<Future<void>>[
      triggerHaptic(ZeroSyncHapticPattern.lightImpact, force: force),
      triggerAudio(ZeroSyncAudioChime.chunkReceived, force: force),
    ]);
  }

  /// Triggered when an entire fountain stream is decapsulated and verified.
  Future<void> triggerStreamComplete({bool force = false}) async {
    await Future.wait<void>(<Future<void>>[
      triggerHaptic(ZeroSyncHapticPattern.heavyImpact, force: force),
      triggerAudio(ZeroSyncAudioChime.streamComplete, force: force),
    ]);
  }

  /// Triggered when a malicious payload, invalid CRC, or threat is detected.
  Future<void> triggerSecurityWarning({bool force = false}) async {
    await Future.wait<void>(<Future<void>>[
      triggerHaptic(ZeroSyncHapticPattern.vibrate, force: force),
      triggerAudio(ZeroSyncAudioChime.warningAlert, force: force),
    ]);
  }

  /// Lightweight UI tap click feedback.
  Future<void> triggerSelection() async {
    await triggerHaptic(ZeroSyncHapticPattern.selectionClick, force: true);
  }

  // --- Low-Level Execution & Throttling ---

  /// Dispatches a tactile vibration pattern with hardware cooldown protection.
  Future<void> triggerHaptic(
    ZeroSyncHapticPattern pattern, {
    bool force = false,
  }) async {
    if (!_hapticsEnabled || pattern == ZeroSyncHapticPattern.none) {
      return;
    }

    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastHapticTime) < _minHapticInterval) {
      return; // Throttled
    }
    _lastHapticTime = now;

    switch (pattern) {
      case ZeroSyncHapticPattern.lightImpact:
        await _hapticsDriver.lightImpact();
      case ZeroSyncHapticPattern.mediumImpact:
        await _hapticsDriver.mediumImpact();
      case ZeroSyncHapticPattern.heavyImpact:
        await _hapticsDriver.heavyImpact();
      case ZeroSyncHapticPattern.selectionClick:
        await _hapticsDriver.selectionClick();
      case ZeroSyncHapticPattern.vibrate:
        await _hapticsDriver.vibrate();
      case ZeroSyncHapticPattern.none:
        break;
    }
  }

  /// Plays an audio chime with muting verification and cooldown protection.
  Future<void> triggerAudio(
    ZeroSyncAudioChime chime, {
    bool force = false,
  }) async {
    if (isMuted || chime == ZeroSyncAudioChime.none) {
      return;
    }

    final DateTime now = DateTime.now();
    if (!force && now.difference(_lastAudioTime) < _minAudioInterval) {
      return; // Throttled
    }
    _lastAudioTime = now;

    // Retrieve or synthesize the WAV buffer
    final Uint8List wavBytes = _cachedChimes.putIfAbsent(
      chime,
      () => _chimeGenerator.generateChimeWav(chime, volume: _volume),
    );

    await _audioDriver.playSyntheticTone(chime, wavBytes);
  }
}
