import 'dart:convert';

import 'package:airdrop_qr/domain/entities/infrastructure_payload.dart';
import 'package:airdrop_qr/domain/entities/vcard_payload.dart';
import 'package:airdrop_qr/domain/services/infrastructure_serializer_service.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/domain/services/tracker_stripper_service.dart';
import 'package:airdrop_qr/domain/services/vcard_serializer_service.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The 8 standard payload schema types supported by the universal QR generator.
enum StandardPayloadType {
  text('Text', 'Universal plain text / raw string'),
  url('URL', 'Web link with offline tracker stripping'),
  wifi('Wi-Fi', 'WPA/WPA2/WPA3 network configuration'),
  contact('Contact', 'RFC 6350 vCard 4.0 business card'),
  email('Email', 'Standard mailto: with subject & body'),
  sms('SMS', 'Direct SMS text message syntax'),
  geo('Geo', 'RFC 5870 GPS coordinates'),
  calendar('Calendar', 'RFC 5545 iCalendar VEVENT');

  final String label;
  final String description;
  const StandardPayloadType(this.label, this.description);
}

// ============================================================================
// EVENTS
// ============================================================================

abstract class QrGeneratorEvent extends Equatable {
  const QrGeneratorEvent();

  @override
  List<Object?> get props => [];
}

class QrGeneratorTypeChanged extends QrGeneratorEvent {
  final StandardPayloadType type;
  const QrGeneratorTypeChanged(this.type);

  @override
  List<Object?> get props => [type];
}

class QrGeneratorTextPayloadUpdated extends QrGeneratorEvent {
  final String text;
  const QrGeneratorTextPayloadUpdated(this.text);

  @override
  List<Object?> get props => [text];
}

class QrGeneratorUrlPayloadUpdated extends QrGeneratorEvent {
  final String url;
  final bool stripTrackers;
  const QrGeneratorUrlPayloadUpdated(this.url, {this.stripTrackers = true});

  @override
  List<Object?> get props => [url, stripTrackers];
}

class QrGeneratorWifiPayloadUpdated extends QrGeneratorEvent {
  final WifiConfigPayload wifi;
  const QrGeneratorWifiPayloadUpdated(this.wifi);

  @override
  List<Object?> get props => [wifi];
}

class QrGeneratorVCardPayloadUpdated extends QrGeneratorEvent {
  final VCardPayload vcard;
  const QrGeneratorVCardPayloadUpdated(this.vcard);

  @override
  List<Object?> get props => [vcard];
}

class QrGeneratorEmailPayloadUpdated extends QrGeneratorEvent {
  final String recipient;
  final String? subject;
  final String? body;

  const QrGeneratorEmailPayloadUpdated({
    required this.recipient,
    this.subject,
    this.body,
  });

  @override
  List<Object?> get props => [recipient, subject, body];
}

class QrGeneratorSmsPayloadUpdated extends QrGeneratorEvent {
  final String phoneNumber;
  final String? message;

  const QrGeneratorSmsPayloadUpdated({
    required this.phoneNumber,
    this.message,
  });

  @override
  List<Object?> get props => [phoneNumber, message];
}

class QrGeneratorGeoPayloadUpdated extends QrGeneratorEvent {
  final GeoLocationPayload geo;
  const QrGeneratorGeoPayloadUpdated(this.geo);

  @override
  List<Object?> get props => [geo];
}

class QrGeneratorCalendarPayloadUpdated extends QrGeneratorEvent {
  final CalendarEventPayload calendar;
  const QrGeneratorCalendarPayloadUpdated(this.calendar);

  @override
  List<Object?> get props => [calendar];
}

class QrGeneratorEccChanged extends QrGeneratorEvent {
  final QrErrorCorrectionLevel eccLevel;
  const QrGeneratorEccChanged(this.eccLevel);

  @override
  List<Object?> get props => [eccLevel];
}

class QrGeneratorReset extends QrGeneratorEvent {
  const QrGeneratorReset();
}

// ============================================================================
// STATE
// ============================================================================

class QrGeneratorState extends Equatable {
  final StandardPayloadType selectedType;
  final String payload;
  final int byteLength;
  final int optimalVersion;
  final QrErrorCorrectionLevel eccLevel;
  final SanitizedUrlResult? sanitizedUrlResult;
  final bool isValid;
  final String? validationError;

  const QrGeneratorState({
    required this.selectedType,
    required this.payload,
    required this.byteLength,
    required this.optimalVersion,
    required this.eccLevel,
    this.sanitizedUrlResult,
    required this.isValid,
    this.validationError,
  });

  factory QrGeneratorState.initial() {
    const initialText = 'ZeroSync: Air-Gapped Optical Data Transfer';
    final bytes = utf8.encode(initialText);
    return QrGeneratorState(
      selectedType: StandardPayloadType.text,
      payload: initialText,
      byteLength: bytes.length,
      optimalVersion: 2,
      eccLevel: QrErrorCorrectionLevel.medium,
      isValid: true,
    );
  }

  QrGeneratorState copyWith({
    StandardPayloadType? selectedType,
    String? payload,
    int? byteLength,
    int? optimalVersion,
    QrErrorCorrectionLevel? eccLevel,
    SanitizedUrlResult? sanitizedUrlResult,
    bool? isValid,
    String? validationError,
  }) {
    return QrGeneratorState(
      selectedType: selectedType ?? this.selectedType,
      payload: payload ?? this.payload,
      byteLength: byteLength ?? this.byteLength,
      optimalVersion: optimalVersion ?? this.optimalVersion,
      eccLevel: eccLevel ?? this.eccLevel,
      sanitizedUrlResult: sanitizedUrlResult ?? this.sanitizedUrlResult,
      isValid: isValid ?? this.isValid,
      validationError: validationError,
    );
  }

  @override
  List<Object?> get props => [
        selectedType,
        payload,
        byteLength,
        optimalVersion,
        eccLevel,
        sanitizedUrlResult,
        isValid,
        validationError,
      ];
}

// ============================================================================
// BLOC
// ============================================================================

class QrGeneratorBloc extends Bloc<QrGeneratorEvent, QrGeneratorState> {
  final VCardSerializerService _vcardSerializer = VCardSerializerService();
  final InfrastructureSerializerService _infraSerializer =
      InfrastructureSerializerService();
  final TrackerStripperService _trackerStripper = TrackerStripperService();
  final QrMatrixGeneratorService _matrixGenerator = QrMatrixGeneratorService();

  QrGeneratorBloc() : super(QrGeneratorState.initial()) {
    on<QrGeneratorTypeChanged>(_onTypeChanged);
    on<QrGeneratorTextPayloadUpdated>(_onTextUpdated);
    on<QrGeneratorUrlPayloadUpdated>(_onUrlUpdated);
    on<QrGeneratorWifiPayloadUpdated>(_onWifiUpdated);
    on<QrGeneratorVCardPayloadUpdated>(_onVCardUpdated);
    on<QrGeneratorEmailPayloadUpdated>(_onEmailUpdated);
    on<QrGeneratorSmsPayloadUpdated>(_onSmsUpdated);
    on<QrGeneratorGeoPayloadUpdated>(_onGeoUpdated);
    on<QrGeneratorCalendarPayloadUpdated>(_onCalendarUpdated);
    on<QrGeneratorEccChanged>(_onEccChanged);
    on<QrGeneratorReset>(_onReset);
  }

  int _computeOptimalVersion(int byteLen, QrErrorCorrectionLevel ecc) {
    try {
      return _matrixGenerator.selectOptimalVersion(byteLen, ecc);
    } catch (_) {
      return 40;
    }
  }

  void _onTypeChanged(
    QrGeneratorTypeChanged event,
    Emitter<QrGeneratorState> emit,
  ) {
    switch (event.type) {
      case StandardPayloadType.text:
        _updatePayload(emit, event.type, 'ZeroSync Air-Gap Secure Payload');
        break;
      case StandardPayloadType.url:
        _updatePayload(emit, event.type, 'https://zerosync.security');
        break;
      case StandardPayloadType.wifi:
        const wifi = WifiConfigPayload(
          ssid: 'ZeroSync-AirGap',
          password: 'HardenedPassword2026',
          securityType: WifiSecurityType.wpa2,
        );
        _updatePayload(emit, event.type, _infraSerializer.serializeWifi(wifi));
        break;
      case StandardPayloadType.contact:
        const vcard = VCardPayload(
          formattedName: 'Security Officer',
          organization: 'ZeroSync Technologies',
          phones: [
            ContactPhone(number: '+1-555-0199', types: ['WORK'])
          ],
          emails: [
            ContactEmail(address: 'officer@zerosync.security', types: ['WORK'])
          ],
        );
        _updatePayload(
            emit, event.type, _vcardSerializer.serializeVCard4(vcard));
        break;
      case StandardPayloadType.email:
        _updatePayload(
          emit,
          event.type,
          'mailto:security@zerosync.security?subject=Incident%20Report&body=Encrypted%20Transfer',
        );
        break;
      case StandardPayloadType.sms:
        _updatePayload(
            emit, event.type, 'smsto:+15550199:Secure airgap code 4921');
        break;
      case StandardPayloadType.geo:
        const geo = GeoLocationPayload(
          latitude: 37.7749,
          longitude: -122.4194,
          altitude: 12.0,
        );
        _updatePayload(emit, event.type, _infraSerializer.serializeGeo(geo));
        break;
      case StandardPayloadType.calendar:
        final now = DateTime.now();
        final eventPayload = CalendarEventPayload(
          summary: 'ZeroSync Optical Key Exchange',
          start: now.add(const Duration(hours: 1)),
          end: now.add(const Duration(hours: 2)),
          location: 'Air-Gapped Facility Room 402',
        );
        _updatePayload(
            emit, event.type, _infraSerializer.serializeCalendar(eventPayload));
        break;
    }
  }

  void _onTextUpdated(
    QrGeneratorTextPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    _updatePayload(emit, StandardPayloadType.text, event.text);
  }

  void _onUrlUpdated(
    QrGeneratorUrlPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    final sanitized =
        event.stripTrackers ? _trackerStripper.sanitize(event.url) : null;
    final effectivePayload = sanitized != null && sanitized.wasModified
        ? sanitized.sanitizedUrl
        : event.url;

    _updatePayload(
      emit,
      StandardPayloadType.url,
      effectivePayload,
      sanitizedResult: sanitized,
    );
  }

  void _onWifiUpdated(
    QrGeneratorWifiPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    try {
      final raw = _infraSerializer.serializeWifi(event.wifi);
      _updatePayload(emit, StandardPayloadType.wifi, raw);
    } catch (e) {
      emit(state.copyWith(
        isValid: false,
        validationError: e.toString(),
      ));
    }
  }

  void _onVCardUpdated(
    QrGeneratorVCardPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    try {
      final raw = _vcardSerializer.serializeVCard4(event.vcard);
      _updatePayload(emit, StandardPayloadType.contact, raw);
    } catch (e) {
      emit(state.copyWith(
        isValid: false,
        validationError: e.toString(),
      ));
    }
  }

  void _onEmailUpdated(
    QrGeneratorEmailPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    final buffer = StringBuffer('mailto:${event.recipient.trim()}');
    final queryParams = <String>[];
    if (event.subject != null && event.subject!.isNotEmpty) {
      queryParams.add('subject=${Uri.encodeComponent(event.subject!)}');
    }
    if (event.body != null && event.body!.isNotEmpty) {
      queryParams.add('body=${Uri.encodeComponent(event.body!)}');
    }
    if (queryParams.isNotEmpty) {
      buffer.write('?${queryParams.join('&')}');
    }
    _updatePayload(emit, StandardPayloadType.email, buffer.toString());
  }

  void _onSmsUpdated(
    QrGeneratorSmsPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    final buffer = StringBuffer('smsto:${event.phoneNumber.trim()}');
    if (event.message != null && event.message!.isNotEmpty) {
      buffer.write(':${event.message!}');
    }
    _updatePayload(emit, StandardPayloadType.sms, buffer.toString());
  }

  void _onGeoUpdated(
    QrGeneratorGeoPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    try {
      final raw = _infraSerializer.serializeGeo(event.geo);
      _updatePayload(emit, StandardPayloadType.geo, raw);
    } catch (e) {
      emit(state.copyWith(
        isValid: false,
        validationError: e.toString(),
      ));
    }
  }

  void _onCalendarUpdated(
    QrGeneratorCalendarPayloadUpdated event,
    Emitter<QrGeneratorState> emit,
  ) {
    try {
      final raw = _infraSerializer.serializeCalendar(event.calendar);
      _updatePayload(emit, StandardPayloadType.calendar, raw);
    } catch (e) {
      emit(state.copyWith(
        isValid: false,
        validationError: e.toString(),
      ));
    }
  }

  void _onEccChanged(
    QrGeneratorEccChanged event,
    Emitter<QrGeneratorState> emit,
  ) {
    final bytes = utf8.encode(state.payload);
    final version = _computeOptimalVersion(bytes.length, event.eccLevel);
    emit(state.copyWith(
      eccLevel: event.eccLevel,
      optimalVersion: version,
    ));
  }

  void _onReset(
    QrGeneratorReset event,
    Emitter<QrGeneratorState> emit,
  ) {
    emit(QrGeneratorState.initial());
  }

  void _updatePayload(
    Emitter<QrGeneratorState> emit,
    StandardPayloadType type,
    String payload, {
    SanitizedUrlResult? sanitizedResult,
  }) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(
        selectedType: type,
        payload: '',
        byteLength: 0,
        optimalVersion: 1,
        isValid: false,
        validationError: 'Payload cannot be empty',
        sanitizedUrlResult: sanitizedResult,
      ));
      return;
    }

    final bytes = utf8.encode(trimmed);
    final version = _computeOptimalVersion(bytes.length, state.eccLevel);

    emit(state.copyWith(
      selectedType: type,
      payload: trimmed,
      byteLength: bytes.length,
      optimalVersion: version,
      isValid: true,
      validationError: null,
      sanitizedUrlResult: sanitizedResult,
    ));
  }
}
