/// Severity classification for detected security threats in parsed URLs.
enum ThreatSeverity {
  /// No detectable threats; standard well-formed URL.
  none,

  /// Minor informational observation (e.g. plain HTTP, non-standard port).
  low,

  /// Potentially risky characteristic (e.g. open redirect query parameter, suspicious TLD).
  medium,

  /// High-confidence risk (e.g. direct IP address host, multi-level deceptive subdomains).
  high,

  /// Critical exploit or spoofing threat (e.g. homograph/punycode attack, `javascript:` or `data:` execution scheme).
  critical,
}

/// Category of security threats identified during heuristic domain analysis.
enum ThreatCategory {
  /// Internationalized domain spoofing using Punycode (`xn--`) or confusable Cyrillic/Greek homoglyphs.
  punycodeHomograph,

  /// Destination host is a raw IPv4 or IPv6 numeric address rather than a registered domain name.
  directIpHost,

  /// Dangerous or script-executable URI schemes (`javascript:`, `data:`, `file:`, `blob:`, `vbscript:`).
  highRiskScheme,

  /// High-privilege action schemes that trigger native dialing, SMS, or app actions (`tel:`, `sms:`, `intent:`).
  privilegedNativeScheme,

  /// User credentials embedded in authority component (`https://trusted.com@evil.com`), masking real host.
  embeddedCredentials,

  /// Excessive or deceptive subdomain hierarchy attempting to disguise the registrable root domain.
  excessiveSubdomains,

  /// Known high-abuse or commonly weaponized top-level domain (`.zip`, `.mov`, `.tk`, `.top`, etc.).
  suspiciousTld,

  /// Open redirect parameter in query string targeting external destinations (`?url=`, `?next=`, etc.).
  openRedirectPattern,

  /// Unencrypted transport (`http:`) exposing plaintext metadata across transit networks.
  unencryptedTransport,

  /// Malformed URI syntax or control character injection.
  malformedSyntax,
}

/// A specific threat detection finding produced by [DomainInspectorService].
class SecurityThreat {
  /// High-level classification of the threat.
  final ThreatCategory category;

  /// Risk severity rating.
  final ThreatSeverity severity;

  /// Clear, human-readable description of the security implication.
  final String description;

  /// Specific token, domain segment, or parameter that triggered the threat.
  final String evidence;

  const SecurityThreat({
    required this.category,
    required this.severity,
    required this.description,
    required this.evidence,
  });

  @override
  String toString() =>
      'SecurityThreat(${severity.name.toUpperCase()} - ${category.name}: "$evidence" => $description)';
}

/// Formatted pre-flight display information for user verification before opening a URL.
class PreflightInterstitialData {
  /// Protocol classification descriptor (e.g. 'Encrypted HTTPS', 'Insecure HTTP', 'Executable Script').
  final String protocolDescriptor;

  /// Primary registered destination authority (e.g. `bank.com` from `login.secure.bank.com`).
  final String registrableRootDomain;

  /// Full destination host hierarchy.
  final String fullHost;

  /// Full path and query string.
  final String pathAndQuery;

  /// List of human-readable warnings to highlight in the pre-flight dialog.
  final List<String> warningList;

  /// Whether user must provide explicit affirmative confirmation before dispatching.
  final bool requiresExplicitConfirmation;

  const PreflightInterstitialData({
    required this.protocolDescriptor,
    required this.registrableRootDomain,
    required this.fullHost,
    required this.pathAndQuery,
    required this.warningList,
    required this.requiresExplicitConfirmation,
  });
}

/// Comprehensive inspection report returned by [DomainInspectorService].
class DomainInspectionReport {
  /// Original raw string provided for inspection.
  final String rawInput;

  /// Successfully parsed [Uri] instance, or `null` if the input is malformed.
  final Uri? parsedUri;

  /// Whether the input represents a syntactically valid URL.
  final bool isValidUrl;

  /// URI scheme (e.g. `https`, `http`, `javascript`).
  final String scheme;

  /// Hostname or IP address component.
  final String host;

  /// Port number if explicitly specified.
  final int? port;

  /// Destination path component.
  final String path;

  /// Query parameters map.
  final Map<String, String> queryParameters;

  /// Fragment identifier without `#`.
  final String fragment;

  /// Extracted top-level domain (e.g. `com`, `org`, `zip`), if applicable.
  final String? topLevelDomain;

  /// Registrable root domain (e.g. `example.com`), if resolvable.
  final String? rootDomain;

  /// Extracted subdomain segments in order (e.g. `['login', 'secure']`).
  final List<String> subdomains;

  /// Whether the host is an IPv4 or IPv6 address.
  final bool isDirectIp;

  /// Whether the host contains Punycode labels (`xn--`).
  final bool isPunycode;

  /// All security threats detected by heuristic inspection.
  final List<SecurityThreat> detectedThreats;

  /// Peak threat severity across all detected findings.
  final ThreatSeverity overallSeverity;

  /// Pre-flight security interstitial display metadata.
  final PreflightInterstitialData preflightData;

  const DomainInspectionReport({
    required this.rawInput,
    this.parsedUri,
    required this.isValidUrl,
    required this.scheme,
    required this.host,
    this.port,
    required this.path,
    required this.queryParameters,
    required this.fragment,
    this.topLevelDomain,
    this.rootDomain,
    required this.subdomains,
    required this.isDirectIp,
    required this.isPunycode,
    required this.detectedThreats,
    required this.overallSeverity,
    required this.preflightData,
  });

  /// Whether the inspected URL is considered safe for normal navigation.
  bool get isSafe =>
      overallSeverity == ThreatSeverity.none ||
      overallSeverity == ThreatSeverity.low;

  /// Whether the URL contains critical or high severity security vulnerabilities.
  bool get isHighRisk =>
      overallSeverity == ThreatSeverity.high ||
      overallSeverity == ThreatSeverity.critical;
}

/// Heuristic offline security analyzer inspecting URLs for phishing, homographs, and exploits.
///
/// Complies with Zero-Trust air-gap policies: runs 100% locally with zero external network queries.
class DomainInspectorService {
  /// Dangerous schemes capable of direct code execution or local privilege escalation.
  static const Set<String> _executableSchemes = <String>{
    'javascript',
    'data',
    'file',
    'blob',
    'vbscript',
  };

  /// Privileged native device schemes requiring explicit user confirmation.
  static const Set<String> _privilegedSchemes = <String>{
    'tel',
    'sms',
    'intent',
    'facetime',
    'callto',
  };

  /// High-risk TLDs frequently abused in phishing and malware campaigns.
  static const Set<String> _suspiciousTlds = <String>{
    'zip',
    'mov',
    'tk',
    'ml',
    'ga',
    'cf',
    'gq',
    'top',
    'work',
    'click',
    'surf',
    'cam',
  };

  /// Query parameter keys commonly used in open-redirect vulnerabilities.
  static const Set<String> _redirectParamKeys = <String>{
    'url',
    'next',
    'redirect',
    'redirect_url',
    'redirect_uri',
    'dest',
    'destination',
    'target',
    'return',
    'return_url',
    'r',
    'u',
  };

  /// Confusable Cyrillic/Greek Unicode codepoint ranges that mimic Latin glyphs.
  ///
  /// Examples: Cyrillic 'а' (U+0430) vs Latin 'a' (U+0061), Cyrillic 'о' (U+043E) vs Latin 'o'.
  static final RegExp _confusableUnicodeRegExp = RegExp(
    r'[\u0400-\u04FF\u0370-\u03FF\u0500-\u052F\u2DE0-\u2DFF\uA640-\uA69F]',
  );

  /// IPv4 dotted-decimal pattern (e.g. 192.168.1.1).
  static final RegExp _ipv4RegExp = RegExp(
    r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
  );

  /// Analyzes the provided [rawUrl] and returns a detailed [DomainInspectionReport].
  DomainInspectionReport inspect(String rawUrl) {
    final String trimmed = rawUrl.trim();
    final List<SecurityThreat> threats = <SecurityThreat>[];

    // Check for control characters or null bytes
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) {
      threats.add(
        const SecurityThreat(
          category: ThreatCategory.malformedSyntax,
          severity: ThreatSeverity.critical,
          description: 'URL contains illegal control characters or null-byte injection',
          evidence: 'Control characters detected',
        ),
      );
    }

    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (e) {
      // Failed to parse
      return _buildMalformedReport(trimmed, threats, e.toString());
    }

    final String scheme = uri.scheme.toLowerCase();
    final String host = uri.host.toLowerCase();
    final int? port = uri.hasPort ? uri.port : null;
    final String path = uri.path;
    final String fragment = uri.fragment;
    final Map<String, String> queryParameters = uri.queryParameters;

    // 1. Inspect URI Scheme
    _evaluateScheme(scheme, threats);

    // 2. Inspect Embedded User Credentials (https://user:pass@evil.com)
    if (uri.userInfo.isNotEmpty) {
      threats.add(
        SecurityThreat(
          category: ThreatCategory.embeddedCredentials,
          severity: ThreatSeverity.high,
          description:
              'Authority contains embedded userinfo credentials ("${uri.userInfo}@"), '
              'a technique frequently used to spoof trusted domain prefixes.',
          evidence: uri.userInfo,
        ),
      );
    }

    // 3. Inspect IP-based Destinations
    final bool isDirectIp = _evaluateIpHost(host, threats);

    // 4. Inspect Homoglyph & Punycode Attacks
    final bool isPunycode = _evaluateHomoglyphsAndPunycode(host, threats);

    // 5. Inspect Subdomain Hierarchy & Registrable Domain
    final List<String> subdomains = <String>[];
    String? rootDomain;
    String? tld;

    if (!isDirectIp && host.contains('.')) {
      final List<String> parts = host.split('.');
      tld = parts.last;

      if (parts.length >= 2) {
        rootDomain = '${parts[parts.length - 2]}.${parts.last}';
        if (parts.length > 2) {
          subdomains.addAll(parts.sublist(0, parts.length - 2));
        }
      }

      // Check excessive subdomains
      if (subdomains.length >= 4) {
        threats.add(
          SecurityThreat(
            category: ThreatCategory.excessiveSubdomains,
            severity: ThreatSeverity.high,
            description:
                'Domain possesses an excessive subdomain hierarchy (${subdomains.length} levels), '
                'which is characteristic of phishing URLs designed to obscure the true host.',
            evidence: host,
          ),
        );
      }

      // Check suspicious TLDs
      if (_suspiciousTlds.contains(tld)) {
        threats.add(
          SecurityThreat(
            category: ThreatCategory.suspiciousTld,
            severity: ThreatSeverity.medium,
            description:
                'Top-level domain (.$tld) is classified as high-risk and frequently abused '
                'for disposable spam or drive-by payload distribution.',
            evidence: '.$tld',
          ),
        );
      }
    }

    // 6. Inspect Open Redirects in Query Parameters
    _evaluateOpenRedirects(queryParameters, threats);

    // 7. Calculate Peak Severity
    final ThreatSeverity overallSeverity = _calculatePeakSeverity(threats);

    // 8. Construct Preflight Display Data
    final PreflightInterstitialData preflightData = _buildPreflightData(
      scheme: scheme,
      host: host,
      path: path,
      query: uri.query,
      rootDomain: rootDomain ?? (isDirectIp ? host : host),
      threats: threats,
      overallSeverity: overallSeverity,
    );

    return DomainInspectionReport(
      rawInput: trimmed,
      parsedUri: uri,
      isValidUrl: true,
      scheme: scheme,
      host: host,
      port: port,
      path: path,
      queryParameters: queryParameters,
      fragment: fragment,
      topLevelDomain: tld,
      rootDomain: rootDomain,
      subdomains: List<String>.unmodifiable(subdomains),
      isDirectIp: isDirectIp,
      isPunycode: isPunycode,
      detectedThreats: List<SecurityThreat>.unmodifiable(threats),
      overallSeverity: overallSeverity,
      preflightData: preflightData,
    );
  }

  void _evaluateScheme(String scheme, List<SecurityThreat> threats) {
    if (_executableSchemes.contains(scheme)) {
      threats.add(
        SecurityThreat(
          category: ThreatCategory.highRiskScheme,
          severity: ThreatSeverity.critical,
          description:
              'Scheme "$scheme:" executes arbitrary scripts or local filesystem actions '
              'and represents an immediate execution hazard.',
          evidence: scheme,
        ),
      );
    } else if (_privilegedSchemes.contains(scheme)) {
      threats.add(
        SecurityThreat(
          category: ThreatCategory.privilegedNativeScheme,
          severity: ThreatSeverity.medium,
          description:
              'Scheme "$scheme:" initiates privileged native communication '
              '(such as phone calls or SMS) that may incur carrier charges.',
          evidence: scheme,
        ),
      );
    } else if (scheme == 'http') {
      threats.add(
        const SecurityThreat(
          category: ThreatCategory.unencryptedTransport,
          severity: ThreatSeverity.low,
          description:
              'Transport protocol is plaintext HTTP without TLS encryption; '
              'traffic is vulnerable to interception and modification.',
          evidence: 'http',
        ),
      );
    }
  }

  bool _evaluateIpHost(String host, List<SecurityThreat> threats) {
    if (host.isEmpty) return false;

    // Check IPv4
    if (_ipv4RegExp.hasMatch(host)) {
      threats.add(
        SecurityThreat(
          category: ThreatCategory.directIpHost,
          severity: ThreatSeverity.high,
          description:
              'Destination is a raw IPv4 numeric address ($host). Legitimate services '
              'consistently utilize registered domain names to preserve reputation and SSL integrity.',
          evidence: host,
        ),
      );
      return true;
    }

    // Check IPv6 (wrapped in brackets or raw hex colons)
    if (host.startsWith('[') && host.endsWith(']') || host.contains(':')) {
      threats.add(
        SecurityThreat(
          category: ThreatCategory.directIpHost,
          severity: ThreatSeverity.high,
          description:
              'Destination is a raw IPv6 numeric address ($host), frequently used '
              'to bypass DNS filtering gateways.',
          evidence: host,
        ),
      );
      return true;
    }

    return false;
  }

  bool _evaluateHomoglyphsAndPunycode(String host, List<SecurityThreat> threats) {
    bool isPunycode = false;
    final String decodedHost = Uri.decodeComponent(host);

    // Check Punycode prefix in any label
    if (host.contains('xn--') || decodedHost.contains('xn--')) {
      isPunycode = true;
      threats.add(
        SecurityThreat(
          category: ThreatCategory.punycodeHomograph,
          severity: ThreatSeverity.critical,
          description:
              'Host utilizes Internationalized Domain Name (Punycode "xn--") encoding. '
              'Punycode is frequently weaponized in homograph attacks to impersonate brand domains.',
          evidence: host,
        ),
      );
    }

    // Check mixed-script confusable Unicode characters (both raw and decoded)
    if (_confusableUnicodeRegExp.hasMatch(host) ||
        _confusableUnicodeRegExp.hasMatch(decodedHost)) {
      threats.add(
        SecurityThreat(
          category: ThreatCategory.punycodeHomograph,
          severity: ThreatSeverity.critical,
          description:
              'Host contains confusable Cyrillic, Greek, or non-Latin Unicode characters '
              'visually identical to Latin characters (IDN Homograph attack).',
          evidence: decodedHost,
        ),
      );
    }

    return isPunycode;
  }

  void _evaluateOpenRedirects(
    Map<String, String> queryParameters,
    List<SecurityThreat> threats,
  ) {
    for (final MapEntry<String, String> entry in queryParameters.entries) {
      final String key = entry.key.toLowerCase();
      final String val = entry.value.trim().toLowerCase();

      if (_redirectParamKeys.contains(key)) {
        if (val.startsWith('http://') ||
            val.startsWith('https://') ||
            val.startsWith('//')) {
          threats.add(
            SecurityThreat(
              category: ThreatCategory.openRedirectPattern,
              severity: ThreatSeverity.medium,
              description:
                  'Query parameter "$key" contains an external target URL ($val), '
                  'indicating a potential open-redirect vulnerability.',
              evidence: '${entry.key}=${entry.value}',
            ),
          );
        }
      }
    }
  }

  ThreatSeverity _calculatePeakSeverity(List<SecurityThreat> threats) {
    if (threats.isEmpty) return ThreatSeverity.none;

    ThreatSeverity maxSeverity = ThreatSeverity.none;
    for (final SecurityThreat threat in threats) {
      if (threat.severity.index > maxSeverity.index) {
        maxSeverity = threat.severity;
      }
    }
    return maxSeverity;
  }

  PreflightInterstitialData _buildPreflightData({
    required String scheme,
    required String host,
    required String path,
    required String query,
    required String rootDomain,
    required List<SecurityThreat> threats,
    required ThreatSeverity overallSeverity,
  }) {
    String protocolDescriptor;
    switch (scheme) {
      case 'https':
        protocolDescriptor = 'Secure TLS (HTTPS)';
      case 'http':
        protocolDescriptor = 'Insecure Plaintext (HTTP)';
      case 'javascript':
      case 'data':
      case 'file':
        protocolDescriptor = 'Executable Script / File URI ($scheme)';
      case 'tel':
      case 'sms':
        protocolDescriptor = 'Telephony / SMS Action ($scheme)';
      default:
        protocolDescriptor = 'Custom Protocol (${scheme.isEmpty ? "unknown" : scheme})';
    }

    final String pathAndQuery = query.isNotEmpty ? '$path?$query' : path;
    final List<String> warnings = threats.map((t) => t.description).toList();
    final bool requiresConsent = overallSeverity.index >= ThreatSeverity.medium.index;

    return PreflightInterstitialData(
      protocolDescriptor: protocolDescriptor,
      registrableRootDomain: rootDomain,
      fullHost: host,
      pathAndQuery: pathAndQuery,
      warningList: List<String>.unmodifiable(warnings),
      requiresExplicitConfirmation: requiresConsent,
    );
  }

  DomainInspectionReport _buildMalformedReport(
    String rawInput,
    List<SecurityThreat> existingThreats,
    String parseError,
  ) {
    final List<SecurityThreat> threats = List<SecurityThreat>.from(existingThreats)
      ..add(
        SecurityThreat(
          category: ThreatCategory.malformedSyntax,
          severity: ThreatSeverity.critical,
          description: 'Failed to parse URI: $parseError',
          evidence: rawInput,
        ),
      );

    return DomainInspectionReport(
      rawInput: rawInput,
      parsedUri: null,
      isValidUrl: false,
      scheme: '',
      host: '',
      port: null,
      path: '',
      queryParameters: const <String, String>{},
      fragment: '',
      topLevelDomain: null,
      rootDomain: null,
      subdomains: const <String>[],
      isDirectIp: false,
      isPunycode: false,
      detectedThreats: List<SecurityThreat>.unmodifiable(threats),
      overallSeverity: ThreatSeverity.critical,
      preflightData: const PreflightInterstitialData(
        protocolDescriptor: 'Malformed URI',
        registrableRootDomain: 'Invalid',
        fullHost: 'Invalid',
        pathAndQuery: '',
        warningList: <String>['Syntax is unparseable and may attempt parser differential attacks.'],
        requiresExplicitConfirmation: true,
      ),
    );
  }
}
