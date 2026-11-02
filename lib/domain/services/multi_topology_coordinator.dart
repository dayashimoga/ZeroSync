import 'package:equatable/equatable.dart';

/// Supported optical transfer topologies.
enum TransferTopology {
  /// Unidirectional 1:1 point-to-point link.
  oneToOne('1:1 Point-to-Point',
      'Unidirectional optical link between 1 transmitter and 1 receiver.'),

  /// Rateless fountain broadcast to unlimited simultaneous camera receivers.
  oneToMany('1:N Optical Multicast',
      'Single screen streams fountain droplets simultaneously to unlimited camera receivers.'),

  /// Distributed bidirectional or multi-party optical exchange.
  manyToMany('M:N Mesh Broadcast',
      'Time-multiplexed optical broadcast between multiple participating devices.');

  final String label;
  final String description;
  const TransferTopology(this.label, this.description);
}

/// Participant device descriptor in a multi-device optical session.
class TopologyParticipant extends Equatable {
  final String deviceId;
  final String displayName;
  final bool isTransmitter;
  final DateTime joinedAt;

  const TopologyParticipant({
    required this.deviceId,
    required this.displayName,
    required this.isTransmitter,
    required this.joinedAt,
  });

  @override
  List<Object?> get props => [deviceId, displayName, isTransmitter, joinedAt];
}

/// Service governing multi-device optical transfer topologies.
class MultiTopologyCoordinator {
  TransferTopology _activeTopology = TransferTopology.oneToOne;
  final Map<String, TopologyParticipant> _participants = {};

  TransferTopology get activeTopology => _activeTopology;
  List<TopologyParticipant> get participants => _participants.values.toList();
  int get participantCount => _participants.length;

  /// Changes the active transfer topology.
  void setTopology(TransferTopology topology) {
    _activeTopology = topology;
  }

  /// Registers a participant device into the active session topology.
  void registerParticipant(TopologyParticipant participant) {
    _participants[participant.deviceId] = participant;
  }

  /// Removes a participant device from the topology.
  void removeParticipant(String deviceId) {
    _participants.remove(deviceId);
  }

  /// Clears all participants.
  void reset() {
    _participants.clear();
    _activeTopology = TransferTopology.oneToOne;
  }

  /// Verifies whether the current topology supports rateless multicast broadcasting.
  bool get supportsSimultaneousReceivers =>
      _activeTopology == TransferTopology.oneToMany ||
      _activeTopology == TransferTopology.manyToMany;
}
