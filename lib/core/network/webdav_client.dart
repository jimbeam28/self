// lib/core/network/webdav_client.dart
// WebDAV client: validates connectivity by issuing a PROPFIND request.
// Uses the `http` package directly so we control the method/timeout.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ── Validation result ─────────────────────────────────────────────────────────

enum WebDavValidationStatus { success, authError, pathNotFound, networkError }

class WebDavValidationResult {
  final WebDavValidationStatus status;
  final String? message; // null when status == success

  const WebDavValidationResult._(this.status, this.message);

  factory WebDavValidationResult.success() =>
      const WebDavValidationResult._(WebDavValidationStatus.success, null);

  factory WebDavValidationResult.authError() => const WebDavValidationResult._(
      WebDavValidationStatus.authError, '用户名或密码错误');

  factory WebDavValidationResult.pathNotFound() =>
      const WebDavValidationResult._(WebDavValidationStatus.pathNotFound,
          '基础路径不存在，请检查路径设置');

  factory WebDavValidationResult.networkError() =>
      const WebDavValidationResult._(WebDavValidationStatus.networkError,
          '无法连接到服务器，请检查地址和网络');

  bool get isSuccess => status == WebDavValidationStatus.success;
}

// ── URL normalisation ─────────────────────────────────────────────────────────

/// Ensures the URL has an http/https scheme.
/// If the user typed a bare IP / hostname (no scheme) we prepend `http://`.
String normaliseWebDavUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return 'http://$trimmed';
}

/// Returns true when [url] is a syntactically valid http/https URL with a host.
bool isValidWebDavUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  } catch (_) {
    return false;
  }
}

// ── Abstract interface ────────────────────────────────────────────────────────

abstract class WebDavClientInterface {
  /// Validates the WebDAV endpoint by sending a PROPFIND request.
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  });
}

// ── Concrete implementation ───────────────────────────────────────────────────

class WebDavClient implements WebDavClientInterface {
  final http.Client _httpClient;
  final Duration _timeout;

  WebDavClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  @override
  Future<WebDavValidationResult> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    // 1. Normalise and validate URL format
    final normalisedUrl = normaliseWebDavUrl(url);
    if (!isValidWebDavUrl(normalisedUrl)) {
      return WebDavValidationResult.networkError();
    }

    // 2. Build the target URI (base path)
    Uri targetUri;
    try {
      final base = Uri.parse(normalisedUrl);
      final effectivePath =
          basePath.isEmpty ? '/' : (basePath.startsWith('/') ? basePath : '/$basePath');
      targetUri = base.replace(path: effectivePath);
    } catch (_) {
      return WebDavValidationResult.networkError();
    }

    // 3. Build Basic-Auth header using dart:convert base64
    final credentialBytes = utf8.encode('$username:$password');
    final encoded = base64.encode(credentialBytes);
    final authHeader = 'Basic $encoded';

    // 4. Send PROPFIND with timeout
    try {
      final request = http.Request('PROPFIND', targetUri)
        ..headers['Authorization'] = authHeader
        ..headers['Depth'] = '0'
        ..headers['Content-Type'] = 'application/xml';

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(_timeout);

      switch (streamedResponse.statusCode) {
        case 207:
          return WebDavValidationResult.success();
        case 401:
        case 403:
          return WebDavValidationResult.authError();
        case 404:
          return WebDavValidationResult.pathNotFound();
        default:
          // Any other 2xx-like from non-standard servers — treat as success
          if (streamedResponse.statusCode >= 200 &&
              streamedResponse.statusCode < 300) {
            return WebDavValidationResult.success();
          }
          return WebDavValidationResult.networkError();
      }
    } on TimeoutException {
      return WebDavValidationResult.networkError();
    } catch (_) {
      return WebDavValidationResult.networkError();
    }
  }
}
