import 'dart:async';
import '../entities/enterprise_policy.dart';
import '../entities/license_certificate.dart';
import 'duress_manager_service.dart';
import 'license_verifier_service.dart';

/// Offline Enterprise Licensing, Feature Flagging, and Policy Management Engine.
///
/// Operates entirely offline with zero network connectivity or remote telemetry.
/// Authenticates `.zslic` cryptographic licenses via pinned Ed25519 signatures,
/// coordinates hardware-locked offline trials, provides granular feature toggling,
/// and enforces zero-trust air-gapped security policies.
class EnterprisePolicyService {
  final LicenseVerifierService _verifierService;
  final DuressManagerService _duressManager;

  LicenseCertificate? _activeCertificate;
  bool _trialConsumed = false;
  DateTime? _trialStartedAt;
  DateTime? _trialExpiresAt;

  bool _mandatoryEncryption = false;
  bool _strictAirgapLockdown = true;
  AuditRetentionPolicy _retentionPolicy = AuditRetentionPolicy.retainForever;

  final Map<String, bool> _featureToggles = {
    'cameraScanner': true,
    'imageScanner': true,
    'standardGenerator': true,
    'batchScanner': true,
    'advancedStyler': true,
    'encryptedVault': true,
    'enterpriseStudio': true,
    'rgbMultiplexing': true,
    'forensicAudit': true,
    'duressPanicDecoy': true,
  };

  /// Predefined feature catalog with minimum tier requirements.
  static const List<FeatureTierGate> featureCatalog = [
    FeatureTierGate(
      featureKey: 'cameraScanner',
      title: 'Real-Time Camera Scanner',
      description:
          'Continuous offline optical viewfinder with live target tracking.',
      minimumTier: LicenseTier.community,
    ),
    FeatureTierGate(
      featureKey: 'imageScanner',
      title: 'Image & File Preprocessor',
      description:
          'Multi-pass image binarization, inverted QR, and desktop file paste.',
      minimumTier: LicenseTier.community,
    ),
    FeatureTierGate(
      featureKey: 'standardGenerator',
      title: 'Universal QR Generator',
      description:
          'Standard 8-type payloads (Text, URL, Wi-Fi, Contact, SMS, Geo, etc.).',
      minimumTier: LicenseTier.community,
    ),
    FeatureTierGate(
      featureKey: 'batchScanner',
      title: 'High-Throughput Batch Scanner',
      description:
          'Continuous scanning with deduplication, live feed, and CSV export.',
      minimumTier: LicenseTier.pro,
    ),
    FeatureTierGate(
      featureKey: 'advancedStyler',
      title: 'Advanced Styler & Vector Studio',
      description:
          'Custom module styles, gradients, logo embedding, and SVG/PDF export.',
      minimumTier: LicenseTier.pro,
    ),
    FeatureTierGate(
      featureKey: 'encryptedVault',
      title: 'SQLCipher AES-256 Vault',
      description:
          'Zero-trust encrypted on-device database with forensic integrity chain.',
      minimumTier: LicenseTier.pro,
    ),
    FeatureTierGate(
      featureKey: 'enterpriseStudio',
      title: 'Enterprise Cryptographic Studio',
      description:
          'RFC 6238 TOTP, Web3 URIs, SLIP-39 Shamir shares & encrypted envelopes.',
      minimumTier: LicenseTier.enterprise,
    ),
    FeatureTierGate(
      featureKey: 'rgbMultiplexing',
      title: '3x RGB Spectral Multiplexing',
      description:
          'Triple-throughput optical data transfer via RGB color matrix.',
      minimumTier: LicenseTier.enterprise,
    ),
    FeatureTierGate(
      featureKey: 'forensicAudit',
      title: 'Forensic Audit Chain & PDF Signer',
      description:
          'Immutable cryptographic audit export with SHA-256 chain of custody.',
      minimumTier: LicenseTier.enterprise,
    ),
    FeatureTierGate(
      featureKey: 'duressPanicDecoy',
      title: 'Duress Panic Decoy Database',
      description:
          'Plausible deniability secondary PIN with auto-scrubbing under coercion.',
      minimumTier: LicenseTier.enterprise,
    ),
  ];

  EnterprisePolicyService({
    LicenseVerifierService? verifierService,
    DuressManagerService? duressManager,
    LicenseCertificate? initialCertificate,
  })  : _verifierService = verifierService ?? LicenseVerifierService(),
        _duressManager = duressManager ?? DuressManagerService(),
        _activeCertificate = initialCertificate;

  /// Effective active tier taking into account installed license and active trial.
  LicenseTier get effectiveTier {
    if (_activeCertificate != null &&
        !_activeCertificate!.payload.isExpired()) {
      return _activeCertificate!.payload.tier;
    }
    if (isTrialActive) {
      return LicenseTier.enterprise;
    }
    return LicenseTier.community;
  }

  /// Whether an offline enterprise trial is currently running.
  bool get isTrialActive {
    if (!_trialConsumed || _trialExpiresAt == null) return false;
    return DateTime.now().isBefore(_trialExpiresAt!);
  }

  /// Expiry time of active trial, if any.
  DateTime? get trialExpiresAt => _trialExpiresAt;

  /// Whether the one-time offline trial has already been activated.
  bool get isTrialConsumed => _trialConsumed;

  /// Active cryptographic license certificate, if any.
  LicenseCertificate? get activeCertificate => _activeCertificate;

  /// Mandatory encryption enforcement setting.
  bool get mandatoryEncryption => _mandatoryEncryption;

  /// Strict air-gap lockdown setting.
  bool get strictAirgapLockdown => _strictAirgapLockdown;

  /// Audit retention policy setting.
  AuditRetentionPolicy get retentionPolicy => _retentionPolicy;

  /// Duress manager service instance.
  DuressManagerService get duressManager => _duressManager;

  /// Calculates max optical transfer payload in Megabytes allowed for current tier.
  int get maxOpticalTransferMb {
    switch (effectiveTier) {
      case LicenseTier.community:
        return 10;
      case LicenseTier.pro:
        return 50;
      case LicenseTier.enterprise:
        return 500;
    }
  }

  /// Evaluates whether a feature is permitted under current tier and toggle status.
  bool isFeatureAllowed(String featureKey) {
    // 1. Check if user/admin explicitly toggled this feature off
    final isToggledOn = _featureToggles[featureKey] ?? true;
    if (!isToggledOn) return false;

    // 2. Look up feature gate in catalog
    final gate = featureCatalog.firstWhere(
      (g) => g.featureKey == featureKey,
      orElse: () => FeatureTierGate(
        featureKey: featureKey,
        title: featureKey,
        description: '',
        minimumTier: LicenseTier.community,
      ),
    );

    // 3. Evaluate tier hierarchy
    return _isTierSufficient(effectiveTier, gate.minimumTier);
  }

  bool _isTierSufficient(LicenseTier current, LicenseTier required) {
    const hierarchy = {
      LicenseTier.community: 1,
      LicenseTier.pro: 2,
      LicenseTier.enterprise: 3,
    };
    final currentLevel = hierarchy[current] ?? 1;
    final requiredLevel = hierarchy[required] ?? 1;
    return currentLevel >= requiredLevel;
  }

  /// Activates an offline 14-day enterprise trial.
  bool activateOfflineTrial({int durationDays = 14}) {
    if (_trialConsumed) return false;
    _trialConsumed = true;
    _trialStartedAt = DateTime.now();
    _trialExpiresAt = _trialStartedAt!.add(Duration(days: durationDays));
    return true;
  }

  /// Cryptographically verifies and installs a `.zslic` license certificate.
  Future<LicenseVerificationResult> installLicense(String encodedZSLic) async {
    final result = await _verifierService.verifyEncodedString(encodedZSLic);
    if (result.isValid && result.certificate != null) {
      _activeCertificate = result.certificate;
    }
    return result;
  }

  /// Revokes the current license and returns to Community Edition.
  void revokeLicense() {
    _activeCertificate = null;
  }

  /// Sets a granular feature toggle.
  void setFeatureToggle(String featureKey, bool enabled) {
    _featureToggles[featureKey] = enabled;
  }

  /// Gets the current state of a feature toggle.
  bool getFeatureToggle(String featureKey) {
    return _featureToggles[featureKey] ?? true;
  }

  /// Configures mandatory encryption for all optical transfers and payloads.
  void setMandatoryEncryption(bool enabled) {
    _mandatoryEncryption = enabled;
  }

  /// Configures strict air-gap lockdown.
  void setStrictAirgapLockdown(bool enabled) {
    _strictAirgapLockdown = enabled;
  }

  /// Configures audit log retention policy.
  void setRetentionPolicy(AuditRetentionPolicy policy) {
    _retentionPolicy = policy;
  }

  /// Configures primary and duress PIN credentials.
  void configureDuressPins({
    required String primaryPin,
    required String duressPin,
    bool autoScrubRealKeyOnDuress = false,
  }) {
    final config = DuressSecurityConfig.fromPlaintextPins(
      primaryPin: primaryPin,
      duressPin: duressPin,
      autoScrubRealKeyOnDuress: autoScrubRealKeyOnDuress,
    );
    _duressManager.configure(config);
  }

  /// Evaluates an authentication PIN against primary and duress credentials.
  PinAuthResult evaluateDuressPin(String pin) {
    return _duressManager.evaluatePin(pin);
  }

  /// Produces an immutable snapshot of all policy, license, and duress states.
  EnterprisePolicySnapshot get snapshot {
    return EnterprisePolicySnapshot(
      activeTier: effectiveTier,
      certificate: _activeCertificate,
      isTrialActive: isTrialActive,
      trialExpiresAt: _trialExpiresAt,
      mandatoryEncryption: _mandatoryEncryption,
      strictAirgapLockdown: _strictAirgapLockdown,
      retentionPolicy: _retentionPolicy,
      maxOpticalTransferMb: maxOpticalTransferMb,
      featureToggles: Map.unmodifiable(_featureToggles),
      isDuressConfigured: _duressManager.isConfigured,
      isDuressActive: _duressManager.isDuressActive,
    );
  }
}
