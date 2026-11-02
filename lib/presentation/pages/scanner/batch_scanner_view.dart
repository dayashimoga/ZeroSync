import 'package:airdrop_qr/data/datasources/optical_scanner_datasource.dart';
import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/blocs/batch_scanner/batch_scanner_bloc.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Workspace providing high-speed continuous batch barcode scanning,
/// sliding-window duplicate suppression, CSV export, and encrypted vault persistence.
class BatchScannerView extends StatefulWidget {
  final BatchScannerBloc? batchBlocOverride;
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;

  const BatchScannerView({
    super.key,
    this.batchBlocOverride,
    this.onSaveToVault,
    this.onActionDispatched,
  });

  @override
  State<BatchScannerView> createState() => _BatchScannerViewState();
}

class _BatchScannerViewState extends State<BatchScannerView> {
  late final BatchScannerBloc _batchBloc;
  bool _internalBlocCreated = false;

  final TextEditingController _tagController =
      TextEditingController(text: 'Batch-Inventory-01');
  final TextEditingController _manualInputController = TextEditingController();

  double _debounceMs = 1500;
  final bool _autoSave = true;

  @override
  void initState() {
    super.initState();
    if (widget.batchBlocOverride != null) {
      _batchBloc = widget.batchBlocOverride!;
    } else {
      _batchBloc = BatchScannerBloc();
      _internalBlocCreated = true;
    }

    _batchBloc.add(
      BatchScannerStarted(
        autoSaveToVault: _autoSave,
        debounceWindow: Duration(milliseconds: _debounceMs.round()),
        batchTag: _tagController.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    _manualInputController.dispose();
    if (_internalBlocCreated) {
      _batchBloc.close();
    }
    super.dispose();
  }

  void _ingestManualCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;

    final scanResult = OpticalScanResult(
      rawValue: trimmed,
      format: BarcodeFormat.qrCode,
      timestamp: DateTime.now(),
      engineUsed: OpticalDetectionEngine.windowsZxing,
      instantaneousFps: 60.0,
      frameSequence: 1,
      processingLatency: const Duration(milliseconds: 15),
    );

    _batchBloc.add(BatchScannerCodeScanned(scanResult));
    _manualInputController.clear();
  }

  void _exportCsv(List<BatchScanItem> items) {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in batch to export.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Index,ID,Format,Category,ScanCount,Timestamp,RawPayload');

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      // Escape payload quotes for CSV safety
      final escapedPayload = '"${item.rawValue.replaceAll('"', '""')}"';
      buffer.writeln(
        '${i + 1},${item.id},${item.format},${item.contentType},${item.scanCount},${item.scannedAt.toIso8601String()},$escapedPayload',
      );
    }

    final csvContent = buffer.toString();
    Clipboard.setData(ClipboardData(text: csvContent));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Exported ${items.length} batch items as CSV (copied to clipboard).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BatchScannerBloc>.value(
      value: _batchBloc,
      child: BlocConsumer<BatchScannerBloc, BatchScannerState>(
        listener: (context, state) {
          if (state is BatchScannerSaveSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Committed ${state.savedCount} records to encrypted vault under tag "${state.appliedTag}".',
                ),
              ),
            );
          } else if (state is BatchScannerError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.red.shade900,
                content: Text('Batch scanner error: ${state.errorMessage}'),
              ),
            );
          }
        },
        builder: (context, state) {
          final activeState = state is BatchScannerActive ? state : null;
          final items = activeState?.items ?? const <BatchScanItem>[];
          final duplicates = activeState?.duplicateCount ?? 0;
          final isPaused = activeState?.isPaused ?? false;

          return Scaffold(
            backgroundColor: ZeroSyncColors.trueBlack,
            body: Column(
              children: [
                // 1. Session Telemetry & Quick Action Bar
                _buildTelemetryHeader(
                    items.length, duplicates, isPaused, items),

                // 2. Ingestion Controls & Debounce Config
                _buildIngestionControls(isPaused),

                // 3. Live Continuous Feed
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState()
                      : _buildItemFeed(items),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTelemetryHeader(
    int itemCount,
    int duplicateCount,
    bool isPaused,
    List<BatchScanItem> items,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZeroSyncSpacing.md,
        vertical: ZeroSyncSpacing.sm,
      ),
      color: ZeroSyncColors.darkGraphite,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                // Ingestion Status Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPaused
                        ? Colors.amber.shade900.withAlpha(80)
                        : Colors.green.shade900.withAlpha(80),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isPaused
                          ? Colors.amberAccent
                          : ZeroSyncColors.emerald,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaused
                            ? Icons.pause_circle_filled
                            : Icons.fiber_manual_record,
                        color: isPaused
                            ? Colors.amberAccent
                            : ZeroSyncColors.emerald,
                        size: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isPaused ? 'PAUSED' : 'STREAMING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isPaused
                              ? Colors.amberAccent
                              : ZeroSyncColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Unique Items Pill
                Text(
                  'Items: $itemCount',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
                const SizedBox(width: 12),

                // Suppressed Duplicates Pill
                Text(
                  'Suppressed: $duplicateCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZeroSyncColors.lightTextSecondary,
                  ),
                ),
                const Spacer(),

                // Play / Pause Toggle
                IconButton(
                  icon: Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                    color: isPaused ? ZeroSyncColors.emerald : Colors.amber,
                    size: 20,
                  ),
                  tooltip: isPaused ? 'Resume Ingestion' : 'Pause Ingestion',
                  onPressed: () {
                    if (isPaused) {
                      _batchBloc.add(const BatchScannerResumed());
                    } else {
                      _batchBloc.add(const BatchScannerPaused());
                    }
                  },
                ),

                // Clear Session Button
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined,
                      color: Colors.white70, size: 20),
                  tooltip: 'Clear Batch',
                  onPressed: () => _batchBloc.add(const BatchScannerCleared()),
                ),

                // Export CSV Button
                IconButton(
                  icon: const Icon(Icons.file_download_outlined,
                      color: ZeroSyncColors.cyan, size: 20),
                  tooltip: 'Export CSV to Clipboard',
                  onPressed: () => _exportCsv(items),
                ),

                // Commit to Vault Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZeroSyncColors.emerald,
                    foregroundColor: ZeroSyncColors.trueBlack,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  icon: const Icon(Icons.save, size: 14),
                  label: const Text('Commit',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: items.isEmpty
                      ? null
                      : () {
                          _batchBloc.add(
                            BatchScannerSavedToVault(
                              customTag: _tagController.text.trim(),
                            ),
                          );
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIngestionControls(bool isPaused) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: const BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        border: Border(bottom: BorderSide(color: ZeroSyncColors.darkBorder)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Batch Tag Input
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _tagController,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'Batch Tag',
                      labelStyle:
                          TextStyle(fontSize: 10, color: Colors.white60),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onSubmitted: (newTag) {
                      _batchBloc.add(
                        BatchScannerStarted(
                          autoSaveToVault: _autoSave,
                          debounceWindow:
                              Duration(milliseconds: _debounceMs.round()),
                          batchTag: newTag.trim(),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Debounce Window Indicator & Slider
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Text(
                      'Debounce ${_debounceMs.round()}ms',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                    Expanded(
                      child: Slider(
                        value: _debounceMs,
                        min: 500,
                        max: 3000,
                        divisions: 10,
                        activeColor: ZeroSyncColors.cyan,
                        onChanged: (val) {
                          setState(() => _debounceMs = val);
                          _batchBloc.add(
                            BatchScannerStarted(
                              autoSaveToVault: _autoSave,
                              debounceWindow:
                                  Duration(milliseconds: val.round()),
                              batchTag: _tagController.text.trim(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Manual Barcode Ingestion Bar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _manualInputController,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      hintText: 'Scan or type barcode to ingest...',
                      hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onSubmitted: _ingestManualCode,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.cyan,
                  foregroundColor: ZeroSyncColors.trueBlack,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Ingest',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => _ingestManualCode(_manualInputController.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(ZeroSyncSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dynamic_feed_outlined, size: 48, color: Colors.white24),
            SizedBox(height: ZeroSyncSpacing.md),
            Text(
              'Continuous Batch Ingestion Ready',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite,
              ),
            ),
            SizedBox(height: ZeroSyncSpacing.xs),
            Text(
              'Aim optical camera at barcodes or type identifiers above.\n'
              'Duplicate barcodes within the debounce window are automatically suppressed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, color: ZeroSyncColors.lightTextSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemFeed(List<BatchScanItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemCard(item);
      },
    );
  }

  Widget _buildItemCard(BatchScanItem item) {
    IconData categoryIcon;
    Color categoryColor;

    switch (item.contentType) {
      case 'url':
        categoryIcon = Icons.link;
        categoryColor = ZeroSyncColors.cyan;
        break;
      case 'wifi':
        categoryIcon = Icons.wifi;
        categoryColor = ZeroSyncColors.emerald;
        break;
      case 'vcard':
        categoryIcon = Icons.contact_page;
        categoryColor = Colors.purpleAccent;
        break;
      case 'calendar':
        categoryIcon = Icons.event;
        categoryColor = Colors.orangeAccent;
        break;
      case 'totp':
        categoryIcon = Icons.lock_clock;
        categoryColor = Colors.yellowAccent;
        break;
      case 'crypto':
        categoryIcon = Icons.currency_bitcoin;
        categoryColor = Colors.amber;
        break;
      default:
        categoryIcon = Icons.text_snippet;
        categoryColor = Colors.blueGrey;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: ZeroSyncColors.darkGraphite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: ZeroSyncColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Icon
            Icon(categoryIcon, color: categoryColor, size: 20),
            const SizedBox(width: 8),

            // Content Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: categoryColor.withAlpha(40),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          item.contentType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: categoryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.format.toUpperCase(),
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white54),
                      ),
                      if (item.scanCount > 1) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'x${item.scanCount}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '${item.scannedAt.hour.toString().padLeft(2, '0')}:${item.scannedAt.minute.toString().padLeft(2, '0')}:${item.scannedAt.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    item.rawValue,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: ZeroSyncColors.trueWhite,
                    ),
                  ),
                ],
              ),
            ),

            // Quick Actions: Inspect Threat & Delete
            IconButton(
              icon: const Icon(Icons.shield_outlined,
                  size: 16, color: ZeroSyncColors.cyan),
              tooltip: 'Inspect Threat',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              onPressed: () {
                ThreatInspectorSheet.show(
                  context: context,
                  rawPayload: item.rawValue,
                  onSaveToVault: widget.onSaveToVault,
                  onActionDispatched: widget.onActionDispatched,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white38),
              tooltip: 'Remove from Batch',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              onPressed: () {
                _batchBloc.add(BatchScannerItemRemoved(item.id));
              },
            ),
          ],
        ),
      ),
    );
  }
}
