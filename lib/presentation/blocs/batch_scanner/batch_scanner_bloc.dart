import 'dart:async';

import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:airdrop_qr/data/datasources/optical_scanner_datasource.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

/// Pluggable interface for haptic and audio feedback triggers during batch scanning.
abstract class BatchScannerFeedbackService {
  /// Triggers a subtle tactile impact upon a novel barcode detection.
  Future<void> triggerSuccessHaptic();

  /// Triggers an audible feedback chime upon a novel barcode detection.
  Future<void> triggerSuccessChime();

  /// Triggers a warning vibration when a duplicate code is scanned and ignored.
  Future<void> triggerDuplicateWarning();
}

/// System-default implementation of [BatchScannerFeedbackService] using Flutter's native services.
class DefaultBatchScannerFeedbackService implements BatchScannerFeedbackService {
  const DefaultBatchScannerFeedbackService();

  @override
  Future<void> triggerSuccessHaptic() async {
    await HapticFeedback.mediumImpact();
  }

  @override
  Future<void> triggerSuccessChime() async {
    await SystemSound.play(SystemSoundType.click);
  }

  @override
  Future<void> triggerDuplicateWarning() async {
    await HapticFeedback.selectionClick();
  }
}

/// Represents an individual scanned optical item in an active batch session.
class BatchScanItem extends Equatable {
  /// Unique item identifier (UUIDv4).
  final String id;

  /// Decoded UTF-8 content string.
  final String rawValue;

  /// Barcode symbology format name (e.g. `qrCode`).
  final String format;

  /// Timestamp when the item was first registered in the batch.
  final DateTime scannedAt;

  /// Inferred payload content category (e.g. `url`, `vcard`, `wifi`, `text`).
  final String contentType;

  /// Number of times this exact code was scanned during the session.
  final int scanCount;

  const BatchScanItem({
    required this.id,
    required this.rawValue,
    required this.format,
    required this.scannedAt,
    required this.contentType,
    this.scanCount = 1,
  });

  /// Factory creating a fresh batch scan item.
  factory BatchScanItem.create({
    required String rawValue,
    required String format,
    String? contentType,
  }) {
    return BatchScanItem(
      id: const Uuid().v4(),
      rawValue: rawValue,
      format: format,
      scannedAt: DateTime.now(),
      contentType: contentType ?? _inferContentType(rawValue),
      scanCount: 1,
    );
  }

  /// Copies this item with an incremented scan count and updated timestamp.
  BatchScanItem copyWithIncrement() {
    return BatchScanItem(
      id: id,
      rawValue: rawValue,
      format: format,
      scannedAt: DateTime.now(),
      contentType: contentType,
      scanCount: scanCount + 1,
    );
  }

  static String _inferContentType(String value) {
    final String trimmed = value.trim().toLowerCase();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return 'url';
    if (trimmed.startsWith('wifi:')) return 'wifi';
    if (trimmed.startsWith('begin:vcard')) return 'vcard';
    if (trimmed.startsWith('begin:vcalendar') || trimmed.startsWith('begin:vevent')) return 'calendar';
    if (trimmed.startsWith('geo:')) return 'geo';
    if (trimmed.startsWith('otpauth://')) return 'totp';
    if (trimmed.startsWith('bitcoin:') || trimmed.startsWith('ethereum:') || trimmed.startsWith('solana:')) {
      return 'crypto';
    }
    return 'text';
  }

  @override
  List<Object?> get props => [id, rawValue, format, scannedAt, contentType, scanCount];
}

// ============================================================================
// EVENTS
// ============================================================================

/// Base class for all batch scanner events.
abstract class BatchScannerEvent extends Equatable {
  const BatchScannerEvent();

  @override
  List<Object?> get props => [];
}

/// Initializes a new batch scanning session.
class BatchScannerStarted extends BatchScannerEvent {
  /// Whether unique scanned items should be automatically committed to the encrypted vault.
  final bool autoSaveToVault;

  /// Sliding debounce duration for duplicate suppression (default: 1.5 seconds).
  final Duration debounceWindow;

  /// Optional custom tag applied to auto-saved items in the encrypted vault.
  final String? batchTag;

  const BatchScannerStarted({
    this.autoSaveToVault = true,
    this.debounceWindow = const Duration(milliseconds: 1500),
    this.batchTag = 'Batch Scan',
  });

  @override
  List<Object?> get props => [autoSaveToVault, debounceWindow, batchTag];
}

/// Ingests a scanned optical result into the active batch.
class BatchScannerCodeScanned extends BatchScannerEvent {
  final OpticalScanResult scanResult;

  const BatchScannerCodeScanned(this.scanResult);

  @override
  List<Object?> get props => [scanResult];
}

/// Removes an item from the current batch session by its [itemId].
class BatchScannerItemRemoved extends BatchScannerEvent {
  final String itemId;

  const BatchScannerItemRemoved(this.itemId);

  @override
  List<Object?> get props => [itemId];
}

/// Clears all items and resets duplicate counters in the current session.
class BatchScannerCleared extends BatchScannerEvent {
  const BatchScannerCleared();
}

/// Explicitly commits all items in the batch session into the encrypted vault.
class BatchScannerSavedToVault extends BatchScannerEvent {
  final String? customTag;

  const BatchScannerSavedToVault({this.customTag});

  @override
  List<Object?> get props => [customTag];
}

/// Pauses batch scanning ingestion without ending the session.
class BatchScannerPaused extends BatchScannerEvent {
  const BatchScannerPaused();
}

/// Resumes batch scanning ingestion.
class BatchScannerResumed extends BatchScannerEvent {
  const BatchScannerResumed();
}

/// Stops the batch session and cleans up resources.
class BatchScannerStopped extends BatchScannerEvent {
  const BatchScannerStopped();
}

// ============================================================================
// STATES
// ============================================================================

/// Base class for all batch scanner states.
abstract class BatchScannerState extends Equatable {
  const BatchScannerState();

  @override
  List<Object?> get props => [];
}

/// Initial inactive state before session startup.
class BatchScannerInitial extends BatchScannerState {
  const BatchScannerInitial();
}

/// Active batch scanning session state.
class BatchScannerActive extends BatchScannerState {
  /// List of unique scanned items in reverse chronological order (newest first).
  final List<BatchScanItem> items;

  /// Total count of duplicate frame captures suppressed during the session.
  final int duplicateCount;

  /// Whether scanning ingestion is temporarily paused.
  final bool isPaused;

  /// Whether items are automatically persisted to the encrypted vault upon capture.
  final bool autoSaveToVault;

  /// Most recently added or updated item.
  final BatchScanItem? latestItem;

  /// Transient feedback message describing the latest scan outcome.
  final String? feedbackMessage;

  const BatchScannerActive({
    required this.items,
    this.duplicateCount = 0,
    this.isPaused = false,
    this.autoSaveToVault = true,
    this.latestItem,
    this.feedbackMessage,
  });

  /// Total number of distinct items captured in this session.
  int get itemCount => items.length;

  BatchScannerActive copyWith({
    List<BatchScanItem>? items,
    int? duplicateCount,
    bool? isPaused,
    bool? autoSaveToVault,
    BatchScanItem? latestItem,
    String? feedbackMessage,
  }) {
    return BatchScannerActive(
      items: items ?? this.items,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      isPaused: isPaused ?? this.isPaused,
      autoSaveToVault: autoSaveToVault ?? this.autoSaveToVault,
      latestItem: latestItem ?? this.latestItem,
      feedbackMessage: feedbackMessage ?? this.feedbackMessage,
    );
  }

  @override
  List<Object?> get props => [
        items,
        duplicateCount,
        isPaused,
        autoSaveToVault,
        latestItem,
        feedbackMessage,
      ];
}

/// Transient state while persisting batch items to the encrypted database.
class BatchScannerSaving extends BatchScannerState {
  final int totalCount;

  const BatchScannerSaving(this.totalCount);

  @override
  List<Object?> get props => [totalCount];
}

/// State emitted after successfully saving batch records to the encrypted vault.
class BatchScannerSaveSuccess extends BatchScannerState {
  final int savedCount;
  final String? appliedTag;

  const BatchScannerSaveSuccess({required this.savedCount, this.appliedTag});

  @override
  List<Object?> get props => [savedCount, appliedTag];
}

/// State emitted when an unrecoverable batch scanner error occurs.
class BatchScannerError extends BatchScannerState {
  final String errorMessage;

  const BatchScannerError(this.errorMessage);

  @override
  List<Object?> get props => [errorMessage];
}

// ============================================================================
// BLOC IMPLEMENTATION
// ============================================================================

/// State management Bloc orchestrating high-volume continuous batch scanning.
///
/// Features:
/// - Continuous scanning without dismissing the camera viewfinder.
/// - Sliding-window deduplication (default 1.5-second debounce) preventing duplicate frame spam.
/// - Haptic and acoustic feedback on each unique code detection.
/// - Optional direct streaming to the encrypted SQLCipher vault with custom tags.
class BatchScannerBloc extends Bloc<BatchScannerEvent, BatchScannerState> {
  final EncryptedVaultDataSource? _vaultDataSource;
  final BatchScannerFeedbackService _feedbackService;

  // Deduplication sliding window map: rawValue -> timestamp
  final Map<String, DateTime> _recentDetections = <String, DateTime>{};
  Duration _debounceWindow = const Duration(milliseconds: 1500);
  bool _autoSave = true;
  String? _batchTag = 'Batch Scan';

  BatchScannerBloc({
    EncryptedVaultDataSource? vaultDataSource,
    BatchScannerFeedbackService? feedbackService,
  })  : _vaultDataSource = vaultDataSource,
        _feedbackService = feedbackService ?? const DefaultBatchScannerFeedbackService(),
        super(const BatchScannerInitial()) {
    on<BatchScannerStarted>(_onStarted);
    on<BatchScannerCodeScanned>(_onCodeScanned);
    on<BatchScannerItemRemoved>(_onItemRemoved);
    on<BatchScannerCleared>(_onCleared);
    on<BatchScannerSavedToVault>(_onSavedToVault);
    on<BatchScannerPaused>(_onPaused);
    on<BatchScannerResumed>(_onResumed);
    on<BatchScannerStopped>(_onStopped);
  }

  void _onStarted(BatchScannerStarted event, Emitter<BatchScannerState> emit) {
    _recentDetections.clear();
    _debounceWindow = event.debounceWindow;
    _autoSave = event.autoSaveToVault;
    _batchTag = event.batchTag;

    emit(BatchScannerActive(
      items: const <BatchScanItem>[],
      duplicateCount: 0,
      isPaused: false,
      autoSaveToVault: _autoSave,
      feedbackMessage: 'Batch session active. Ready to scan.',
    ));
  }

  Future<void> _onCodeScanned(
    BatchScannerCodeScanned event,
    Emitter<BatchScannerState> emit,
  ) async {
    final BatchScannerState currentState = state;
    if (currentState is! BatchScannerActive || currentState.isPaused) return;

    final OpticalScanResult scan = event.scanResult;
    final String rawValue = scan.rawValue.trim();
    if (rawValue.isEmpty) return;

    final DateTime now = DateTime.now();

    // 1. Sliding Window Deduplication Check
    final DateTime? lastSeen = _recentDetections[rawValue];
    if (lastSeen != null) {
      final Duration elapsed = now.difference(lastSeen);
      if (elapsed < _debounceWindow) {
        // Redundant detection within 1.5s sliding window -> suppress with warning haptic
        unawaited(_feedbackService.triggerDuplicateWarning());
        emit(currentState.copyWith(
          duplicateCount: currentState.duplicateCount + 1,
          feedbackMessage: 'Duplicate suppressed (${elapsed.inMilliseconds}ms)',
        ));
        return;
      }
    }

    // Update sliding window timestamp
    _recentDetections[rawValue] = now;

    // 2. Trigger Successful Feedback Chime and Haptic
    unawaited(_feedbackService.triggerSuccessHaptic());
    unawaited(_feedbackService.triggerSuccessChime());

    // 3. Update or Add Item to Session
    final List<BatchScanItem> updatedItems = List<BatchScanItem>.from(currentState.items);
    final int existingIndex = updatedItems.indexWhere((item) => item.rawValue == rawValue);

    BatchScanItem currentItem;
    if (existingIndex >= 0) {
      currentItem = updatedItems[existingIndex].copyWithIncrement();
      updatedItems.removeAt(existingIndex);
      updatedItems.insert(0, currentItem); // Move to top of stack
    } else {
      currentItem = BatchScanItem.create(
        rawValue: rawValue,
        format: scan.format.name,
      );
      updatedItems.insert(0, currentItem);
    }

    // 4. Auto-save to Vault if Enabled
    final EncryptedVaultDataSource? vault = _vaultDataSource;
    if (_autoSave && vault != null) {
      try {
        final ScanRecord record = ScanRecord.create(
          rawValue: currentItem.rawValue,
          rawBytes: scan.rawBytes,
          format: currentItem.format,
          contentType: currentItem.contentType,
          title: 'Batch: ${currentItem.contentType.toUpperCase()}',
          tags: _batchTag != null ? <String>[_batchTag!] : const <String>[],
        );
        await vault.insertScan(record);
      } catch (e) {
        // Log vault save error non-fatally to avoid interrupting the continuous scanning loop
      }
    }

    emit(currentState.copyWith(
      items: List<BatchScanItem>.unmodifiable(updatedItems),
      latestItem: currentItem,
      feedbackMessage: 'Scanned: ${currentItem.contentType} (${updatedItems.length} items)',
    ));
  }

  void _onItemRemoved(
    BatchScannerItemRemoved event,
    Emitter<BatchScannerState> emit,
  ) {
    final BatchScannerState currentState = state;
    if (currentState is! BatchScannerActive) return;

    final List<BatchScanItem> updated =
        currentState.items.where((item) => item.id != event.itemId).toList();

    emit(currentState.copyWith(
      items: List<BatchScanItem>.unmodifiable(updated),
      feedbackMessage: 'Item removed from batch',
    ));
  }

  void _onCleared(
    BatchScannerCleared event,
    Emitter<BatchScannerState> emit,
  ) {
    final BatchScannerState currentState = state;
    if (currentState is! BatchScannerActive) return;

    _recentDetections.clear();
    emit(currentState.copyWith(
      items: const <BatchScanItem>[],
      duplicateCount: 0,
      latestItem: null,
      feedbackMessage: 'Batch cleared',
    ));
  }

  Future<void> _onSavedToVault(
    BatchScannerSavedToVault event,
    Emitter<BatchScannerState> emit,
  ) async {
    final BatchScannerState currentState = state;
    if (currentState is! BatchScannerActive) return;

    if (currentState.items.isEmpty) {
      emit(const BatchScannerSaveSuccess(savedCount: 0));
      return;
    }

    final EncryptedVaultDataSource? vault = _vaultDataSource;
    if (vault == null) {
      emit(const BatchScannerError('No encrypted vault datasource configured'));
      return;
    }

    emit(BatchScannerSaving(currentState.items.length));

    final String tagToApply = event.customTag ?? _batchTag ?? 'Batch Scan';
    int savedCount = 0;

    try {
      for (final BatchScanItem item in currentState.items) {
        final ScanRecord record = ScanRecord.create(
          rawValue: item.rawValue,
          format: item.format,
          contentType: item.contentType,
          title: 'Batch item ${item.scannedAt.toIso8601String()}',
          tags: <String>[tagToApply],
        );
        await vault.insertScan(record);
        savedCount++;
      }

      emit(BatchScannerSaveSuccess(
        savedCount: savedCount,
        appliedTag: tagToApply,
      ));
    } catch (e) {
      emit(BatchScannerError('Failed to persist batch to encrypted vault: $e'));
    }
  }

  void _onPaused(
    BatchScannerPaused event,
    Emitter<BatchScannerState> emit,
  ) {
    final BatchScannerState currentState = state;
    if (currentState is! BatchScannerActive) return;

    emit(currentState.copyWith(
      isPaused: true,
      feedbackMessage: 'Scanning paused',
    ));
  }

  void _onResumed(
    BatchScannerResumed event,
    Emitter<BatchScannerState> emit,
  ) {
    final BatchScannerState currentState = state;
    if (currentState is! BatchScannerActive) return;

    emit(currentState.copyWith(
      isPaused: false,
      feedbackMessage: 'Scanning resumed',
    ));
  }

  void _onStopped(
    BatchScannerStopped event,
    Emitter<BatchScannerState> emit,
  ) {
    _recentDetections.clear();
    emit(const BatchScannerInitial());
  }
}
