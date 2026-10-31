import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../value_objects/transport_header.dart';
import 'luby_transform_fec_service.dart';

/// Request message types dispatched across isolate ports.
sealed class _CodecMessage {}

class _EncodeRequest extends _CodecMessage {
  final int requestId;
  final TransferableTypedData transferablePayload;
  final int symbolSize;
  final double redundancyFactor;
  final bool isEncrypted;
  final RgbColorMode rgbMode;
  final int startSeed;

  _EncodeRequest({
    required this.requestId,
    required this.transferablePayload,
    required this.symbolSize,
    required this.redundancyFactor,
    required this.isEncrypted,
    required this.rgbMode,
    required this.startSeed,
  });
}

class _DecodeFrameRequest extends _CodecMessage {
  final int requestId;
  final TransportHeader header;
  final TransferableTypedData transferablePayload;

  _DecodeFrameRequest({
    required this.requestId,
    required this.header,
    required this.transferablePayload,
  });
}

class _BatchDecodeRequest extends _CodecMessage {
  final int requestId;
  final List<TransportHeader> headers;
  final List<TransferableTypedData> transferablePayloads;

  _BatchDecodeRequest({
    required this.requestId,
    required this.headers,
    required this.transferablePayloads,
  });
}

class _ResetRequest extends _CodecMessage {
  final int requestId;
  _ResetRequest({required this.requestId});
}

class _ShutdownRequest extends _CodecMessage {}

/// Telemetry status received from the background fountain isolate.
class FountainCodecTelemetry extends Equatable {
  final int solvedBlocks;
  final int totalBlocks;
  final bool isDecoded;
  final double progress;

  const FountainCodecTelemetry({
    required this.solvedBlocks,
    required this.totalBlocks,
    required this.isDecoded,
    required this.progress,
  });

  @override
  List<Object?> get props => [solvedBlocks, totalBlocks, isDecoded, progress];
}

/// Zero-copy background isolate worker executing Luby Transform (LT) rateless
/// fountain encoding and graph peeling decoding off the main UI thread.
///
/// Uses [TransferableTypedData] to pass byte buffers across isolate boundaries
/// with zero GC pressure or main-thread frame drops.
class FountainCodecIsolate {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  int _nextRequestId = 1;
  final Map<int, Completer<dynamic>> _pendingCompleters = {};

  bool get isRunning => _isolate != null && _sendPort != null;

  /// Spawns the dedicated background fountain codec worker isolate.
  Future<void> start() async {
    if (isRunning) return;

    _receivePort = ReceivePort();
    final initCompleter = Completer<SendPort>();

    _receivePort!.listen((message) {
      if (message is SendPort) {
        initCompleter.complete(message);
      } else if (message is Map<String, dynamic>) {
        final id = message['id'] as int?;
        if (id != null && _pendingCompleters.containsKey(id)) {
          final completer = _pendingCompleters.remove(id)!;
          if (message.containsKey('error')) {
            completer.completeError(Exception(message['error']));
          } else {
            completer.complete(message['result']);
          }
        }
      }
    });

    _isolate = await Isolate.spawn(
      _isolateWorkerEntryPoint,
      _receivePort!.sendPort,
      debugName: 'ZeroSyncFountainCodecIsolate',
    );

    _sendPort = await initCompleter.future;
  }

  /// Encodes [payload] into a stream of rateless [TransportFrame] packets on the background isolate.
  Future<List<TransportFrame>> encode({
    required Uint8List payload,
    int symbolSize = LubyTransformFecService.defaultSymbolSize,
    double redundancyFactor = 1.3,
    bool isEncrypted = false,
    RgbColorMode rgbMode = RgbColorMode.mono,
    int startSeed = 1000,
  }) async {
    await _ensureStarted();

    final reqId = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingCompleters[reqId] = completer;

    final transferable = TransferableTypedData.fromList([payload]);
    final request = _EncodeRequest(
      requestId: reqId,
      transferablePayload: transferable,
      symbolSize: symbolSize,
      redundancyFactor: redundancyFactor,
      isEncrypted: isEncrypted,
      rgbMode: rgbMode,
      startSeed: startSeed,
    );

    _sendPort!.send(request);

    final rawResult = await completer.future;
    final framesData = rawResult as List<dynamic>;

    final result = <TransportFrame>[];
    for (final item in framesData) {
      final map = item as Map<String, dynamic>;
      final headerBytes = map['header'] as Uint8List;
      final payloadData =
          (map['payload'] as TransferableTypedData).materialize().asUint8List();
      final header = TransportHeader.fromBytes(headerBytes);
      result.add(TransportFrame(header: header, payload: payloadData));
    }

    return result;
  }

  /// Decodes a batch of [TransportFrame] droplets into the contiguous original binary payload.
  Future<Uint8List> decodeBatch(List<TransportFrame> frames) async {
    await _ensureStarted();

    if (frames.isEmpty) {
      throw ArgumentError('Frames collection cannot be empty');
    }

    final reqId = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingCompleters[reqId] = completer;

    final headers = frames.map((f) => f.header).toList();
    final payloads =
        frames.map((f) => TransferableTypedData.fromList([f.payload])).toList();

    final request = _BatchDecodeRequest(
      requestId: reqId,
      headers: headers,
      transferablePayloads: payloads,
    );

    _sendPort!.send(request);

    final rawResult = await completer.future;
    final transferableResult = rawResult as TransferableTypedData;
    return transferableResult.materialize().asUint8List();
  }

  /// Resets the background decoder graph session.
  Future<void> resetDecoder() async {
    if (!isRunning) return;

    final reqId = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingCompleters[reqId] = completer;

    _sendPort!.send(_ResetRequest(requestId: reqId));
    await completer.future;
  }

  /// Ingests a single [TransportFrame] into the background isolate's persistent decoder graph.
  Future<FountainCodecTelemetry> ingestFrame(TransportFrame frame) async {
    await _ensureStarted();

    final reqId = _nextRequestId++;
    final completer = Completer<dynamic>();
    _pendingCompleters[reqId] = completer;

    final transferable = TransferableTypedData.fromList([frame.payload]);
    final request = _DecodeFrameRequest(
      requestId: reqId,
      header: frame.header,
      transferablePayload: transferable,
    );

    _sendPort!.send(request);

    final rawResult = await completer.future;
    final map = rawResult as Map<String, dynamic>;

    return FountainCodecTelemetry(
      solvedBlocks: map['solvedBlocks'] as int,
      totalBlocks: map['totalBlocks'] as int,
      isDecoded: map['isDecoded'] as bool,
      progress: (map['progress'] as num).toDouble(),
    );
  }

  /// Static convenience method to encode a payload using an ephemeral isolate via [Isolate.run].
  static Future<List<TransportFrame>> encodeFast({
    required Uint8List payload,
    int symbolSize = LubyTransformFecService.defaultSymbolSize,
    double redundancyFactor = 1.3,
    bool isEncrypted = false,
    RgbColorMode rgbMode = RgbColorMode.mono,
    int startSeed = 1000,
  }) {
    final transferable = TransferableTypedData.fromList([payload]);
    return Isolate.run<List<TransportFrame>>(() {
      const fecService = LubyTransformFecService();
      final localPayload = transferable.materialize().asUint8List();
      final sourceBlocks = fecService.partitionSourceBlocks(
        localPayload,
        symbolSize: symbolSize,
      );
      final k = sourceBlocks.length;
      final totalDroplets = (k * redundancyFactor).ceil();

      final frames = <TransportFrame>[];
      for (var i = 0; i < totalDroplets; i++) {
        final seed = startSeed + i;
        final droplet = fecService.generateDroplet(
          sourceBlocks: sourceBlocks,
          seed: seed,
          originalPayloadLength: localPayload.length,
        );

        final header = TransportHeader.createForPayload(
          payload: droplet.data,
          k: k,
          seed: seed,
          originalPayloadLength: localPayload.length,
          isEncrypted: isEncrypted,
          rgbMode: rgbMode,
        );

        frames.add(TransportFrame(header: header, payload: droplet.data));
      }

      return frames;
    });
  }

  /// Static convenience method to decode a collection of frames using an ephemeral isolate via [Isolate.run].
  static Future<Uint8List> decodeFast(List<TransportFrame> frames) {
    if (frames.isEmpty) {
      throw ArgumentError('Frames collection cannot be empty');
    }

    final wireBuffers = frames.map((f) => f.toWireBytes()).toList();

    return Isolate.run<Uint8List>(() {
      LubyTransformDecoder? decoder;

      for (final wire in wireBuffers) {
        final frame = TransportFrame.fromWireBytes(wire, verifyChecksum: true);
        final header = frame.header;

        decoder ??= LubyTransformDecoder(
          totalSourceBlocks: header.k,
          symbolSize: frame.payload.length,
          originalPayloadLength: header.payloadLength,
        );

        final prng = DeterministicPrng(header.seed);
        final soliton = RobustSolitonDistribution(header.k);
        final degree = soliton.sampleDegree(prng);
        final indices = soliton.sampleIndices(degree, prng);

        final droplet = FountainDroplet(
          seed: header.seed,
          totalSourceBlocks: header.k,
          symbolSize: frame.payload.length,
          originalPayloadLength: header.payloadLength,
          sourceIndices: indices,
          data: frame.payload,
        );

        decoder.addDroplet(droplet);

        if (decoder.isDecoded) {
          final result = decoder.getDecodedPayload();
          if (result != null) return result;
        }
      }

      if (decoder != null && decoder.isDecoded) {
        final result = decoder.getDecodedPayload();
        if (result != null) return result;
      }

      throw StateError(
        'Insufficient fountain droplets: recovered ${decoder?.solvedBlocksCount ?? 0} / ${frames.first.header.k} source blocks',
      );
    });
  }

  Future<void> _ensureStarted() async {
    if (!isRunning) {
      await start();
    }
  }

  /// Terminates the background worker isolate and disposes all ports.
  Future<void> dispose() async {
    if (_sendPort != null) {
      _sendPort!.send(_ShutdownRequest());
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;

    for (final completer in _pendingCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('FountainCodecIsolate was disposed'));
      }
    }
    _pendingCompleters.clear();
  }
}

/// Persistent entry point running inside the dedicated background isolate.
void _isolateWorkerEntryPoint(SendPort mainSendPort) {
  final isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  LubyTransformDecoder? persistentDecoder;
  const fecService = LubyTransformFecService();

  isolateReceivePort.listen((message) {
    if (message is _ShutdownRequest) {
      isolateReceivePort.close();
      return;
    }

    if (message is _ResetRequest) {
      persistentDecoder = null;
      mainSendPort.send({'id': message.requestId, 'result': true});
      return;
    }

    if (message is _EncodeRequest) {
      try {
        final payload = message.transferablePayload.materialize().asUint8List();
        final sourceBlocks = fecService.partitionSourceBlocks(
          payload,
          symbolSize: message.symbolSize,
        );
        final k = sourceBlocks.length;
        final totalDroplets = (k * message.redundancyFactor).ceil();

        final encodedFrames = <Map<String, dynamic>>[];
        for (var i = 0; i < totalDroplets; i++) {
          final seed = message.startSeed + i;
          final droplet = fecService.generateDroplet(
            sourceBlocks: sourceBlocks,
            seed: seed,
            originalPayloadLength: payload.length,
          );

          final header = TransportHeader.createForPayload(
            payload: droplet.data,
            k: k,
            seed: seed,
            originalPayloadLength: payload.length,
            isEncrypted: message.isEncrypted,
            rgbMode: message.rgbMode,
          );

          encodedFrames.add({
            'header': header.toBytes(),
            'payload': TransferableTypedData.fromList([droplet.data]),
          });
        }

        mainSendPort.send({'id': message.requestId, 'result': encodedFrames});
      } catch (e) {
        mainSendPort.send({'id': message.requestId, 'error': e.toString()});
      }
      return;
    }

    if (message is _BatchDecodeRequest) {
      try {
        LubyTransformDecoder? decoder;

        for (var i = 0; i < message.headers.length; i++) {
          final header = message.headers[i];
          final payload =
              message.transferablePayloads[i].materialize().asUint8List();

          decoder ??= LubyTransformDecoder(
            totalSourceBlocks: header.k,
            symbolSize: payload.length,
            originalPayloadLength: header.payloadLength,
          );

          final prng = DeterministicPrng(header.seed);
          final soliton = RobustSolitonDistribution(header.k);
          final degree = soliton.sampleDegree(prng);
          final indices = soliton.sampleIndices(degree, prng);

          final droplet = FountainDroplet(
            seed: header.seed,
            totalSourceBlocks: header.k,
            symbolSize: payload.length,
            originalPayloadLength: header.payloadLength,
            sourceIndices: indices,
            data: payload,
          );

          decoder.addDroplet(droplet);

          if (decoder.isDecoded) {
            final assembled = decoder.getDecodedPayload();
            if (assembled != null) {
              final transferable = TransferableTypedData.fromList([assembled]);
              mainSendPort
                  .send({'id': message.requestId, 'result': transferable});
              return;
            }
          }
        }

        if (decoder != null && decoder.isDecoded) {
          final assembled = decoder.getDecodedPayload();
          if (assembled != null) {
            final transferable = TransferableTypedData.fromList([assembled]);
            mainSendPort
                .send({'id': message.requestId, 'result': transferable});
            return;
          }
        }

        mainSendPort.send({
          'id': message.requestId,
          'error':
              'Decoding incomplete: solved ${decoder?.solvedBlocksCount ?? 0} / ${message.headers.first.k} blocks',
        });
      } catch (e) {
        mainSendPort.send({'id': message.requestId, 'error': e.toString()});
      }
      return;
    }

    if (message is _DecodeFrameRequest) {
      try {
        final header = message.header;
        final payload = message.transferablePayload.materialize().asUint8List();

        persistentDecoder ??= LubyTransformDecoder(
          totalSourceBlocks: header.k,
          symbolSize: payload.length,
          originalPayloadLength: header.payloadLength,
        );

        final prng = DeterministicPrng(header.seed);
        final soliton = RobustSolitonDistribution(header.k);
        final degree = soliton.sampleDegree(prng);
        final indices = soliton.sampleIndices(degree, prng);

        final droplet = FountainDroplet(
          seed: header.seed,
          totalSourceBlocks: header.k,
          symbolSize: payload.length,
          originalPayloadLength: header.payloadLength,
          sourceIndices: indices,
          data: payload,
        );

        persistentDecoder!.addDroplet(droplet);

        TransferableTypedData? decodedTransferable;
        if (persistentDecoder!.isDecoded) {
          final assembled = persistentDecoder!.getDecodedPayload();
          if (assembled != null) {
            decodedTransferable = TransferableTypedData.fromList([assembled]);
          }
        }

        mainSendPort.send({
          'id': message.requestId,
          'result': {
            'solvedBlocks': persistentDecoder!.solvedBlocksCount,
            'totalBlocks': header.k,
            'isDecoded': persistentDecoder!.isDecoded,
            'progress': persistentDecoder!.progress,
            'decodedPayload': decodedTransferable,
          },
        });
      } catch (e) {
        mainSendPort.send({'id': message.requestId, 'error': e.toString()});
      }
      return;
    }
  });
}
