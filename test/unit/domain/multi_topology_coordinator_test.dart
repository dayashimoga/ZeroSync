import 'package:airdrop_qr/domain/services/multi_topology_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MultiTopologyCoordinator Specs', () {
    late MultiTopologyCoordinator coordinator;

    setUp(() {
      coordinator = MultiTopologyCoordinator();
    });

    test('Defaults to 1:1 point-to-point topology without multicast support',
        () {
      expect(coordinator.activeTopology, equals(TransferTopology.oneToOne));
      expect(coordinator.supportsSimultaneousReceivers, isFalse);
      expect(coordinator.participantCount, equals(0));
    });

    test(
        'Transitions to 1:N Optical Multicast and enables simultaneous receivers',
        () {
      coordinator.setTopology(TransferTopology.oneToMany);
      expect(coordinator.activeTopology, equals(TransferTopology.oneToMany));
      expect(coordinator.supportsSimultaneousReceivers, isTrue);

      coordinator.registerParticipant(TopologyParticipant(
        deviceId: 'dev-001',
        displayName: 'Command Display',
        isTransmitter: true,
        joinedAt: DateTime.now(),
      ));

      coordinator.registerParticipant(TopologyParticipant(
        deviceId: 'dev-002',
        displayName: 'Observer Tablet 1',
        isTransmitter: false,
        joinedAt: DateTime.now(),
      ));

      expect(coordinator.participantCount, equals(2));
      expect(coordinator.participants.first.displayName,
          equals('Command Display'));

      coordinator.removeParticipant('dev-002');
      expect(coordinator.participantCount, equals(1));
    });

    test('Transitions to M:N Mesh Broadcast and resets cleanly', () {
      coordinator.setTopology(TransferTopology.manyToMany);
      expect(coordinator.activeTopology, equals(TransferTopology.manyToMany));
      expect(coordinator.supportsSimultaneousReceivers, isTrue);

      coordinator.registerParticipant(TopologyParticipant(
        deviceId: 'node-A',
        displayName: 'Node Alpha',
        isTransmitter: true,
        joinedAt: DateTime.now(),
      ));

      coordinator.reset();
      expect(coordinator.participantCount, equals(0));
      expect(coordinator.activeTopology, equals(TransferTopology.oneToOne));
    });
  });
}
