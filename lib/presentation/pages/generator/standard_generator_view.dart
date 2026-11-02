import 'package:airdrop_qr/domain/entities/infrastructure_payload.dart';
import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/entities/vcard_payload.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/presentation/blocs/qr_generator/qr_generator_bloc.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Workspace for creating validated QR codes across 8 standard schemas:
/// Text, URL, Wi-Fi, vCard 4.0 Contact, Email, SMS, Geolocation, and iCalendar Event.
class StandardGeneratorView extends StatefulWidget {
  final QrGeneratorBloc? generatorBlocOverride;
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;

  const StandardGeneratorView({
    super.key,
    this.generatorBlocOverride,
    this.onSaveToVault,
    this.onActionDispatched,
  });

  @override
  State<StandardGeneratorView> createState() => _StandardGeneratorViewState();
}

class _StandardGeneratorViewState extends State<StandardGeneratorView> {
  late final QrGeneratorBloc _bloc;
  bool _internalBlocCreated = false;

  // Controllers for all 8 standard schema forms
  final TextEditingController _textController =
      TextEditingController(text: 'ZeroSync: Air-Gapped Optical Data Transfer');
  final TextEditingController _urlController =
      TextEditingController(text: 'https://zerosync.security');
  bool _stripTrackers = true;

  // Wi-Fi
  final TextEditingController _wifiSsidController =
      TextEditingController(text: 'ZeroSync-AirGap');
  final TextEditingController _wifiPasswordController =
      TextEditingController(text: 'HardenedPass2026');
  WifiSecurityType _wifiSecurity = WifiSecurityType.wpa2;
  bool _wifiHidden = false;

  // Contact (vCard)
  final TextEditingController _contactNameController =
      TextEditingController(text: 'Security Director');
  final TextEditingController _contactOrgController =
      TextEditingController(text: 'ZeroSync Security');
  final TextEditingController _contactPhoneController =
      TextEditingController(text: '+1-555-0199');
  final TextEditingController _contactEmailController =
      TextEditingController(text: 'director@zerosync.security');

  // Email
  final TextEditingController _emailToController =
      TextEditingController(text: 'security@zerosync.security');
  final TextEditingController _emailSubjectController =
      TextEditingController(text: 'ZeroSync Audit Report');
  final TextEditingController _emailBodyController =
      TextEditingController(text: 'Air-gap transfer request attached.');

  // SMS
  final TextEditingController _smsPhoneController =
      TextEditingController(text: '+15550199');
  final TextEditingController _smsMessageController =
      TextEditingController(text: 'ZeroSync transfer verification token: 8291');

  // Geo
  final TextEditingController _geoLatController =
      TextEditingController(text: '37.7749');
  final TextEditingController _geoLonController =
      TextEditingController(text: '-122.4194');
  final TextEditingController _geoAltController =
      TextEditingController(text: '15.0');

  // Calendar
  final TextEditingController _calSummaryController =
      TextEditingController(text: 'ZeroSync Key Ceremony');
  final TextEditingController _calLocationController =
      TextEditingController(text: 'Secure Room 4B');
  final TextEditingController _calDescController =
      TextEditingController(text: 'Optical private key generation.');

  @override
  void initState() {
    super.initState();
    if (widget.generatorBlocOverride != null) {
      _bloc = widget.generatorBlocOverride!;
    } else {
      _bloc = QrGeneratorBloc();
      _internalBlocCreated = true;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _contactNameController.dispose();
    _contactOrgController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _emailToController.dispose();
    _emailSubjectController.dispose();
    _emailBodyController.dispose();
    _smsPhoneController.dispose();
    _smsMessageController.dispose();
    _geoLatController.dispose();
    _geoLonController.dispose();
    _geoAltController.dispose();
    _calSummaryController.dispose();
    _calLocationController.dispose();
    _calDescController.dispose();

    if (_internalBlocCreated) {
      _bloc.close();
    }
    super.dispose();
  }

  void _saveToVault(QrGeneratorState state) {
    final record = ScanRecord.create(
      rawValue: state.payload,
      format: 'QR_CODE',
      contentType: state.selectedType.name,
      title:
          '${state.selectedType.label} QR: ${state.selectedType.description}',
      tags: ['Generator', state.selectedType.name],
    );
    widget.onSaveToVault?.call(record);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "${record.title}" to SQLCipher vault.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<QrGeneratorBloc>.value(
      value: _bloc,
      child: BlocBuilder<QrGeneratorBloc, QrGeneratorState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: ZeroSyncColors.trueBlack,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Column: Schema Selector & Form Inputs
                      Expanded(
                        flex: 6,
                        child: _buildFormPane(state),
                      ),
                      const VerticalDivider(
                        width: 1,
                        color: ZeroSyncColors.darkBorder,
                      ),
                      // Right Column: Live QR Preview & Actions
                      Expanded(
                        flex: 4,
                        child: _buildPreviewPane(state),
                      ),
                    ],
                  );
                } else {
                  return ListView(
                    padding: const EdgeInsets.all(ZeroSyncSpacing.md),
                    children: [
                      _buildTypeSelector(state),
                      const SizedBox(height: ZeroSyncSpacing.md),
                      _buildActiveForm(state),
                      const SizedBox(height: ZeroSyncSpacing.lg),
                      _buildPreviewCard(state),
                    ],
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormPane(QrGeneratorState state) {
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      children: [
        _buildTypeSelector(state),
        const SizedBox(height: ZeroSyncSpacing.md),
        _buildActiveForm(state),
      ],
    );
  }

  Widget _buildTypeSelector(QrGeneratorState state) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Standard Payload Schema',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: StandardPayloadType.values.map((type) {
              final isSelected = state.selectedType == type;
              return ChoiceChip(
                label: Text(type.label, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    _bloc.add(QrGeneratorTypeChanged(type));
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveForm(QrGeneratorState state) {
    Widget formContent;

    switch (state.selectedType) {
      case StandardPayloadType.text:
        formContent = _buildTextForm();
        break;
      case StandardPayloadType.url:
        formContent = _buildUrlForm(state);
        break;
      case StandardPayloadType.wifi:
        formContent = _buildWifiForm();
        break;
      case StandardPayloadType.contact:
        formContent = _buildContactForm();
        break;
      case StandardPayloadType.email:
        formContent = _buildEmailForm();
        break;
      case StandardPayloadType.sms:
        formContent = _buildSmsForm();
        break;
      case StandardPayloadType.geo:
        formContent = _buildGeoForm();
        break;
      case StandardPayloadType.calendar:
        formContent = _buildCalendarForm();
        break;
    }

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${state.selectedType.label} Configuration',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.selectedType.description,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: ZeroSyncColors.lightTextSecondary),
                ),
              ),
            ],
          ),
          const Divider(color: ZeroSyncColors.darkBorder, height: 16),
          formContent,
        ],
      ),
    );
  }

  Widget _buildTextForm() {
    return Column(
      children: [
        TextField(
          controller: _textController,
          maxLines: 4,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            hintText: 'Enter plain text or arbitrary payload string...',
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => _bloc.add(QrGeneratorTextPayloadUpdated(val)),
        ),
      ],
    );
  }

  Widget _buildUrlForm(QrGeneratorState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _urlController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Destination URL',
            hintText: 'https://example.com/login?utm_source=fb',
            border: OutlineInputBorder(),
          ),
          onChanged: (val) => _bloc.add(
            QrGeneratorUrlPayloadUpdated(val, stripTrackers: _stripTrackers),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Strip surveillance tracking telemetry (UTM, fbclid, gclid)',
            style: TextStyle(fontSize: 11, color: ZeroSyncColors.trueWhite),
          ),
          value: _stripTrackers,
          activeColor: ZeroSyncColors.emerald,
          onChanged: (val) {
            setState(() => _stripTrackers = val ?? true);
            _bloc.add(
              QrGeneratorUrlPayloadUpdated(_urlController.text,
                  stripTrackers: _stripTrackers),
            );
          },
        ),
        if (state.sanitizedUrlResult != null &&
            state.sanitizedUrlResult!.wasModified) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ZeroSyncColors.emerald.withAlpha(120)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cleaning_services,
                    size: 14, color: ZeroSyncColors.emerald),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Stripped Trackers: ${state.sanitizedUrlResult!.strippedParameters.join(', ')} (${state.sanitizedUrlResult!.bytesSaved}B saved)',
                    style: const TextStyle(
                        fontSize: 10, color: ZeroSyncColors.emerald),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWifiForm() {
    void dispatchWifi() {
      final wifi = WifiConfigPayload(
        ssid: _wifiSsidController.text.trim(),
        password: _wifiPasswordController.text.trim(),
        securityType: _wifiSecurity,
        isHidden: _wifiHidden,
      );
      _bloc.add(QrGeneratorWifiPayloadUpdated(wifi));
    }

    return Column(
      children: [
        TextField(
          controller: _wifiSsidController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Network SSID',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchWifi(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _wifiPasswordController,
          obscureText: true,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Pre-Shared Key / Password',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchWifi(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<WifiSecurityType>(
                initialValue: _wifiSecurity,
                dropdownColor: ZeroSyncColors.darkGraphite,
                style: const TextStyle(
                    fontSize: 12, color: ZeroSyncColors.trueWhite),
                decoration: const InputDecoration(
                  labelText: 'Security Protocol',
                  border: OutlineInputBorder(),
                ),
                items: WifiSecurityType.values.map((sec) {
                  return DropdownMenuItem(
                    value: sec,
                    child: Text(sec.wireValue),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _wifiSecurity = val);
                    dispatchWifi();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Checkbox(
                  value: _wifiHidden,
                  activeColor: ZeroSyncColors.cyan,
                  onChanged: (val) {
                    setState(() => _wifiHidden = val ?? false);
                    dispatchWifi();
                  },
                ),
                const Text('Hidden SSID', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactForm() {
    void dispatchContact() {
      final vcard = VCardPayload(
        formattedName: _contactNameController.text.trim(),
        organization: _contactOrgController.text.trim().isNotEmpty
            ? _contactOrgController.text.trim()
            : null,
        phones: _contactPhoneController.text.trim().isNotEmpty
            ? [
                ContactPhone(
                    number: _contactPhoneController.text.trim(),
                    types: const ['WORK'])
              ]
            : const [],
        emails: _contactEmailController.text.trim().isNotEmpty
            ? [
                ContactEmail(
                    address: _contactEmailController.text.trim(),
                    types: const ['WORK'])
              ]
            : const [],
      );
      _bloc.add(QrGeneratorVCardPayloadUpdated(vcard));
    }

    return Column(
      children: [
        TextField(
          controller: _contactNameController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Full Formatted Name *',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchContact(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _contactOrgController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Organization / Company',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchContact(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _contactPhoneController,
                style: const TextStyle(
                    fontSize: 12, color: ZeroSyncColors.trueWhite),
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => dispatchContact(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _contactEmailController,
                style: const TextStyle(
                    fontSize: 12, color: ZeroSyncColors.trueWhite),
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => dispatchContact(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    void dispatchEmail() {
      _bloc.add(
        QrGeneratorEmailPayloadUpdated(
          recipient: _emailToController.text.trim(),
          subject: _emailSubjectController.text.trim(),
          body: _emailBodyController.text.trim(),
        ),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _emailToController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Recipient Email *',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchEmail(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailSubjectController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Subject',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchEmail(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailBodyController,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Body Content',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchEmail(),
        ),
      ],
    );
  }

  Widget _buildSmsForm() {
    void dispatchSms() {
      _bloc.add(
        QrGeneratorSmsPayloadUpdated(
          phoneNumber: _smsPhoneController.text.trim(),
          message: _smsMessageController.text.trim(),
        ),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _smsPhoneController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Recipient Phone Number *',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchSms(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _smsMessageController,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'SMS Message Body',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchSms(),
        ),
      ],
    );
  }

  Widget _buildGeoForm() {
    void dispatchGeo() {
      final lat = double.tryParse(_geoLatController.text.trim()) ?? 0.0;
      final lon = double.tryParse(_geoLonController.text.trim()) ?? 0.0;
      final alt = double.tryParse(_geoAltController.text.trim());
      _bloc.add(
        QrGeneratorGeoPayloadUpdated(
          GeoLocationPayload(latitude: lat, longitude: lon, altitude: alt),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _geoLatController,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Latitude (-90..90)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => dispatchGeo(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _geoLonController,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Longitude (-180..180)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => dispatchGeo(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _geoAltController,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Altitude (m)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => dispatchGeo(),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarForm() {
    void dispatchCalendar() {
      final now = DateTime.now();
      final event = CalendarEventPayload(
        summary: _calSummaryController.text.trim(),
        location: _calLocationController.text.trim(),
        description: _calDescController.text.trim(),
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
      );
      _bloc.add(QrGeneratorCalendarPayloadUpdated(event));
    }

    return Column(
      children: [
        TextField(
          controller: _calSummaryController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Event Summary *',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchCalendar(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _calLocationController,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Location',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchCalendar(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _calDescController,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => dispatchCalendar(),
        ),
      ],
    );
  }

  Widget _buildPreviewPane(QrGeneratorState state) {
    return ListView(
      primary: false,
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      children: [
        _buildPreviewCard(state),
      ],
    );
  }

  Widget _buildPreviewCard(QrGeneratorState state) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        children: [
          // Header telemetry
          Row(
            children: [
              const Icon(Icons.qr_code_2, size: 20, color: ZeroSyncColors.cyan),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live QR Matrix Preview',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZeroSyncColors.trueBlack,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${state.byteLength} Bytes • V${state.optimalVersion}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: ZeroSyncColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // High-Contrast QR Viewport
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 10),
              ],
            ),
            child: state.isValid && state.payload.isNotEmpty
                ? QrImageView(
                    data: state.payload,
                    version: QrVersions.auto,
                    size: 220,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    padding: const EdgeInsets.all(8),
                  )
                : const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Text(
                        'Invalid Payload',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Error Correction Level Selector
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              const Text('ECC Level: ', style: TextStyle(fontSize: 11)),
              ...QrErrorCorrectionLevel.values.map((ecc) {
                final isSelected = state.eccLevel == ecc;
                return ChoiceChip(
                  label: Text(
                    '${ecc.label} (${(ecc.recoveryPercentage * 100).round()}%)',
                    style: const TextStyle(fontSize: 10),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      _bloc.add(QrGeneratorEccChanged(ecc));
                    }
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Raw Payload Preview Box
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ZeroSyncColors.darkBorder),
            ),
            child: SelectableText(
              state.payload,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: ZeroSyncColors.cyan,
              ),
              maxLines: 4,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Action Buttons: Copy, Save to Vault, Inspect
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: state.payload));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Payload copied to clipboard.')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.shield_outlined, size: 14),
                  label: const Text('Inspect', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    ThreatInspectorSheet.show(
                      context: context,
                      rawPayload: state.payload,
                      onActionDispatched: widget.onActionDispatched,
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZeroSyncColors.emerald,
                    foregroundColor: ZeroSyncColors.trueBlack,
                  ),
                  icon: const Icon(Icons.save, size: 14),
                  label: const Text('Save',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: state.isValid && state.payload.isNotEmpty
                      ? () => _saveToVault(state)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
