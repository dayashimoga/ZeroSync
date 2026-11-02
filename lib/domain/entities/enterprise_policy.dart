import 'package:equatable/equatable.dart';
import 'license_certificate.dart';

/// Retention policy for encrypted audit logs and scan history.
enum AuditRetentionPolicy {
  retainForever(0, 'Retain indefinitely'),
  purge24Hours(1, 'Auto-purge after 24 hours'),
  purge7Days(7, 'Auto-purge after 7 days'),
  purge30Days(30, 'Auto-purge after 30 days');

  final int days;
  final String label;
  const AuditRetentionPolicy(this.days, this.label);
}

/// Feature availability descriptor for tier comparison matrix.
class FeatureTierGate extends Equatable {
  final String featureKey;
  final String title;
  final String description;
  final LicenseTier minimumTier;
  final bool isToggleable;

  const FeatureTierGate({
    required this.featureKey,
    required this.title,
    required this.description,
    required this.minimumTier,
    this.isToggleable = true,
  });

  @override
  List<Object?> get props =>
      [featureKey, title, description, minimumTier, isToggleable];
}

/// Complete enterprise policy snapshot.
class EnterprisePolicySnapshot extends Equatable {
  final LicenseTier activeTier;
  final LicenseCertificate? certificate;
  final bool isTrialActive;
  final DateTime? trialExpiresAt;
  final bool mandatoryEncryption;
  final bool strictAirgapLockdown;
  final AuditRetentionPolicy retentionPolicy;
  final int maxOpticalTransferMb;
  final Map<String, bool> featureToggles;
  final bool isDuressConfigured;
  final bool isDuressActive;

  const EnterprisePolicySnapshot({
    required this.activeTier,
    this.certificate,
    required this.isTrialActive,
    this.trialExpiresAt,
    required this.mandatoryEncryption,
    required this.strictAirgapLockdown,
    required this.retentionPolicy,
    required this.maxOpticalTransferMb,
    required this.featureToggles,
    required this.isDuressConfigured,
    required this.isDuressActive,
  });

  @override
  List<Object?> get props => [
        activeTier,
        certificate,
        isTrialActive,
        trialExpiresAt,
        mandatoryEncryption,
        strictAirgapLockdown,
        retentionPolicy,
        maxOpticalTransferMb,
        featureToggles,
        isDuressConfigured,
        isDuressActive,
      ];
}
