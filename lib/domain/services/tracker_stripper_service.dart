/// Immutable result produced after sanitizing tracking identifiers from a URL.
class SanitizedUrlResult {
  /// The unmodified input URL prior to sanitization.
  final String originalUrl;

  /// The cleaned URL with tracking parameters stripped and canonical structure preserved.
  final String sanitizedUrl;

  /// Whether any tracking identifiers or telemetric query parameters were stripped.
  final bool wasModified;

  /// List of parameter names that were identified as tracking telemetry and removed.
  final List<String> strippedParameters;

  /// Clean query parameters retained in the sanitized URL.
  final Map<String, String> preservedParameters;

  /// Whether the host is an anonymizing or URL-masking shortlink service.
  final bool isShortlink;

  /// The identified shortlink service provider (e.g. `bit.ly`, `tinyurl.com`), if applicable.
  final String? shortlinkProvider;

  /// Warning advisory explaining the risk of navigating through an unexpanded shortlink.
  final String? shortlinkWarning;

  /// Total number of characters/bytes stripped from the URL by cleaning telemetric clutter.
  final int bytesSaved;

  const SanitizedUrlResult({
    required this.originalUrl,
    required this.sanitizedUrl,
    required this.wasModified,
    required this.strippedParameters,
    required this.preservedParameters,
    required this.isShortlink,
    this.shortlinkProvider,
    this.shortlinkWarning,
    required this.bytesSaved,
  });

  @override
  String toString() =>
      'SanitizedUrlResult(modified: $wasModified, stripped: ${strippedParameters.length}, '
      'isShortlink: $isShortlink, saved: ${bytesSaved}B, clean: "$sanitizedUrl")';
}

/// Offline privacy preservation service that strips commercial tracking telemetry and
/// detects masked shortlink redirects without making outbound network requests.
class TrackerStripperService {
  /// Well-known tracking query parameter names commonly used in surveillance advertising.
  static const Set<String> _knownTrackingParameters = <String>{
    // Meta / Facebook
    'fbclid',
    'fbadid',
    'fb_action_ids',
    'fb_action_types',
    'fb_source',

    // Google / Alphabet
    'gclid',
    'gbraid',
    'wbraid',
    'dclid',
    'gad_source',
    'gclsrc',

    // Microsoft / Bing
    'msclkid',

    // Twitter / X
    'twclid',

    // TikTok / ByteDance
    'ttclid',

    // Intuit Mailchimp
    'mc_eid',
    'mc_cid',

    // Adobe / Marketo
    'mkt_tok',

    // HubSpot
    '_hsenc',
    '_hsmi',
    'hscpp',

    // Yandex
    'yclid',
    'ymclid',

    // Instagram
    'igshid',

    // General Referral / Affiliates
    'ref',
    'ref_src',
    'ref_url',
    'aff_id',
    'affiliate_id',
    'partner_id',
  };

  /// Common shortlink and URL redirect providers that obscure real destination authorities.
  static const Set<String> _shortlinkHosts = <String>{
    'bit.ly',
    'tinyurl.com',
    't.co',
    'goo.gl',
    'ow.ly',
    'buff.ly',
    'is.gd',
    'cutt.ly',
    'rebrand.ly',
    'shorturl.at',
    'tiny.cc',
    'bl.ink',
    'linktr.ee',
    'qr.ae',
    's.id',
    'trib.al',
    'v.gd',
    'lnkd.in',
    'rb.gy',
  };

  /// Sanitizes [rawUrl] by stripping commercial tracking parameters and evaluating shortlink risks.
  SanitizedUrlResult sanitize(String rawUrl) {
    final String trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return SanitizedUrlResult(
        originalUrl: rawUrl,
        sanitizedUrl: rawUrl,
        wasModified: false,
        strippedParameters: const <String>[],
        preservedParameters: const <String, String>{},
        isShortlink: false,
        bytesSaved: 0,
      );
    }

    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      // In unparseable URLs, return unmodified
      return SanitizedUrlResult(
        originalUrl: rawUrl,
        sanitizedUrl: rawUrl,
        wasModified: false,
        strippedParameters: const <String>[],
        preservedParameters: const <String, String>{},
        isShortlink: false,
        bytesSaved: 0,
      );
    }

    // 1. Evaluate Shortlink Masking
    final String host = uri.host.toLowerCase();
    final bool isShortlink = isShortlinkHost(host);
    final String? shortlinkProvider = isShortlink ? host : null;
    final String? shortlinkWarning = isShortlink
        ? 'Destination host is an obscured shortlink redirect provider ($host). '
            'The ultimate destination domain is hidden and could route through unverified relays.'
        : null;

    // If URL has no query parameters, no query-based stripping is needed
    if (!uri.hasQuery) {
      return SanitizedUrlResult(
        originalUrl: rawUrl,
        sanitizedUrl: trimmed,
        wasModified: false,
        strippedParameters: const <String>[],
        preservedParameters: const <String, String>{},
        isShortlink: isShortlink,
        shortlinkProvider: shortlinkProvider,
        shortlinkWarning: shortlinkWarning,
        bytesSaved: 0,
      );
    }

    // 2. Filter Tracking Parameters
    final List<String> strippedParams = <String>[];
    final Map<String, String> preservedParams = <String, String>{};

    for (final MapEntry<String, String> entry in uri.queryParameters.entries) {
      if (isTrackingParameter(entry.key)) {
        strippedParams.add(entry.key);
      } else {
        preservedParams[entry.key] = entry.value;
      }
    }

    final bool wasModified = strippedParams.isNotEmpty;

    // Reconstruct cleaned Uri
    String sanitizedString;
    if (preservedParams.isEmpty) {
      final Uri noQueryUri = Uri(
        scheme: uri.scheme.isNotEmpty ? uri.scheme : null,
        userInfo: uri.userInfo.isNotEmpty ? uri.userInfo : null,
        host: uri.host.isNotEmpty ? uri.host : null,
        port: uri.hasPort ? uri.port : null,
        path: uri.path.isNotEmpty ? uri.path : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      );
      sanitizedString = noQueryUri.toString();
    } else {
      sanitizedString =
          uri.replace(queryParameters: preservedParams).toString();
    }

    final int bytesSaved = trimmed.length - sanitizedString.length;

    return SanitizedUrlResult(
      originalUrl: rawUrl,
      sanitizedUrl: sanitizedString,
      wasModified: wasModified,
      strippedParameters: List<String>.unmodifiable(strippedParams),
      preservedParameters: Map<String, String>.unmodifiable(preservedParams),
      isShortlink: isShortlink,
      shortlinkProvider: shortlinkProvider,
      shortlinkWarning: shortlinkWarning,
      bytesSaved: bytesSaved > 0 ? bytesSaved : 0,
    );
  }

  /// Determines whether the given query parameter [key] is a recognized tracking identifier.
  bool isTrackingParameter(String key) {
    final String lowerKey = key.toLowerCase();

    // 1. Check UTM prefix (e.g. utm_source, utm_medium, utm_campaign, utm_content, utm_id)
    if (lowerKey.startsWith('utm_')) {
      return true;
    }

    // 2. Check referral prefixes (ref_, affiliate_)
    if (lowerKey.startsWith('ref_') || lowerKey.startsWith('aff_')) {
      return true;
    }

    // 3. Check exact known tracking parameter keys
    if (_knownTrackingParameters.contains(lowerKey)) {
      return true;
    }

    return false;
  }

  /// Determines whether [host] is a known shortlink or redirect-masking domain.
  bool isShortlinkHost(String host) {
    if (host.isEmpty) return false;
    final String lowerHost = host.toLowerCase();

    if (_shortlinkHosts.contains(lowerHost)) {
      return true;
    }

    // Check if host is a subdomain of a shortlink domain (e.g. lnk.bio, custom bitly)
    for (final String shortlink in _shortlinkHosts) {
      if (lowerHost.endsWith('.$shortlink')) {
        return true;
      }
    }

    return false;
  }
}
