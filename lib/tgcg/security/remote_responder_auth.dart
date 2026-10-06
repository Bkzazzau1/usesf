import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import '../offline/offline_payloads.dart';

enum RemoteResponderAuthenticationStatus {
  authenticated,
  rejected,
  locked,
  unavailable,
  serverError,
}

class RemoteResponderAuthenticationResult {
  const RemoteResponderAuthenticationResult({
    required this.status,
    this.responderId,
    this.agencyId,
    this.serviceNumber,
    this.displayName,
    this.authorizedScope,
    this.sessionToken,
    this.lockedUntil,
    this.message,
  });

  final RemoteResponderAuthenticationStatus status;
  final String? responderId;
  final String? agencyId;
  final String? serviceNumber;
  final String? displayName;
  final GeographicScope? authorizedScope;
  final String? sessionToken;
  final DateTime? lockedUntil;
  final String? message;
}

enum RemoteResponderSessionStatus {
  active,
  revoked,
  unavailable,
  serverError,
}

class RemoteResponderSessionResult {
  const RemoteResponderSessionResult({
    required this.status,
    this.message,
  });

  final RemoteResponderSessionStatus status;
  final String? message;
}

abstract interface class RemoteResponderAuthGateway {
  Future<RemoteResponderAuthenticationResult> authenticate({
    required String agencyId,
    required String serviceNumber,
    required String accessCode,
    required GeographicScope requestedScope,
  });

  Future<RemoteResponderSessionResult> validateSession({
    required String sessionToken,
  });

  Future<void> revokeSession({
    required String sessionToken,
  });
}

class HttpRemoteResponderAuthGateway implements RemoteResponderAuthGateway {
  HttpRemoteResponderAuthGateway({
    required String baseUrl,
    this.timeout = const Duration(seconds: 8),
  }) : baseUri = Uri.parse(baseUrl.trim()) {
    if (!baseUri.hasScheme || baseUri.host.isEmpty) {
      throw ArgumentError('USESF_API_BASE_URL must be an absolute URL.');
    }
    final loopback = baseUri.host == 'localhost' ||
        baseUri.host == '127.0.0.1' ||
        baseUri.host == '::1';
    if (baseUri.scheme != 'https' && !(loopback && baseUri.scheme == 'http')) {
      throw ArgumentError(
        'Responder authentication requires HTTPS except on loopback development hosts.',
      );
    }
  }

  static HttpRemoteResponderAuthGateway? fromEnvironmentOrNull() {
    const baseUrl = String.fromEnvironment('USESF_API_BASE_URL');
    if (baseUrl.trim().isEmpty) return null;
    return HttpRemoteResponderAuthGateway(baseUrl: baseUrl);
  }

  final Uri baseUri;
  final Duration timeout;

  @override
  Future<RemoteResponderAuthenticationResult> authenticate({
    required String agencyId,
    required String serviceNumber,
    required String accessCode,
    required GeographicScope requestedScope,
  }) async {
    try {
      final response = await _postJson(
        '/v1/security/responders/authenticate',
        {
          'agencyId': agencyId,
          'serviceNumber': serviceNumber,
          'accessCode': accessCode,
          'requestedScope': geographicScopeToJson(requestedScope),
        },
      );
      final payload = _decodeObject(response.body);

      if (response.statusCode == HttpStatus.ok) {
        final responderId = payload['responderId']?.toString();
        final remoteAgencyId = payload['agencyId']?.toString();
        final remoteService = payload['serviceNumber']?.toString();
        final displayName = payload['displayName']?.toString();
        final authorizedScope =
            geographicScopeFromJson(payload['authorizedScope']);
        final sessionToken = payload['sessionToken']?.toString();
        if (responderId == null ||
            remoteAgencyId == null ||
            remoteService == null ||
            displayName == null ||
            authorizedScope == null ||
            sessionToken == null) {
          return const RemoteResponderAuthenticationResult(
            status: RemoteResponderAuthenticationStatus.serverError,
            message: 'Malformed responder authentication response.',
          );
        }
        return RemoteResponderAuthenticationResult(
          status: RemoteResponderAuthenticationStatus.authenticated,
          responderId: responderId,
          agencyId: remoteAgencyId,
          serviceNumber: remoteService,
          displayName: displayName,
          authorizedScope: authorizedScope,
          sessionToken: sessionToken,
        );
      }

      if (response.statusCode == HttpStatus.locked) {
        final lockedUntil =
            DateTime.tryParse(payload['lockedUntil']?.toString() ?? '')
                ?.toUtc();
        return RemoteResponderAuthenticationResult(
          status: RemoteResponderAuthenticationStatus.locked,
          lockedUntil: lockedUntil,
          message: payload['message']?.toString(),
        );
      }

      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        return RemoteResponderAuthenticationResult(
          status: RemoteResponderAuthenticationStatus.rejected,
          message: payload['message']?.toString(),
        );
      }

      return RemoteResponderAuthenticationResult(
        status: RemoteResponderAuthenticationStatus.serverError,
        message: 'Responder authentication returned HTTP ${response.statusCode}.',
      );
    } on SocketException catch (error) {
      return RemoteResponderAuthenticationResult(
        status: RemoteResponderAuthenticationStatus.unavailable,
        message: error.message,
      );
    } on TimeoutException {
      return const RemoteResponderAuthenticationResult(
        status: RemoteResponderAuthenticationStatus.unavailable,
        message: 'Responder authentication request timed out.',
      );
    } on HandshakeException catch (error) {
      return RemoteResponderAuthenticationResult(
        status: RemoteResponderAuthenticationStatus.serverError,
        message: error.message,
      );
    } on HttpException catch (error) {
      return RemoteResponderAuthenticationResult(
        status: RemoteResponderAuthenticationStatus.serverError,
        message: error.message,
      );
    } on FormatException catch (error) {
      return RemoteResponderAuthenticationResult(
        status: RemoteResponderAuthenticationStatus.serverError,
        message: error.message,
      );
    }
  }

  @override
  Future<RemoteResponderSessionResult> validateSession({
    required String sessionToken,
  }) async {
    try {
      final response = await _postJson(
        '/v1/security/responders/session/validate',
        const <String, Object?>{},
        bearerToken: sessionToken,
      );
      final payload = _decodeObject(response.body);
      if (response.statusCode == HttpStatus.ok) {
        return const RemoteResponderSessionResult(
          status: RemoteResponderSessionStatus.active,
        );
      }
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        return const RemoteResponderSessionResult(
          status: RemoteResponderSessionStatus.revoked,
        );
      }
      return RemoteResponderSessionResult(
        status: RemoteResponderSessionStatus.serverError,
        message: 'Responder session validation returned HTTP ${response.statusCode}.',
      );
    } on SocketException catch (error) {
      return RemoteResponderSessionResult(
        status: RemoteResponderSessionStatus.unavailable,
        message: error.message,
      );
    } on TimeoutException {
      return const RemoteResponderSessionResult(
        status: RemoteResponderSessionStatus.unavailable,
        message: 'Responder session validation timed out.',
      );
    } on HandshakeException catch (error) {
      return RemoteResponderSessionResult(
        status: RemoteResponderSessionStatus.serverError,
        message: error.message,
      );
    } on HttpException catch (error) {
      return RemoteResponderSessionResult(
        status: RemoteResponderSessionStatus.serverError,
        message: error.message,
      );
    } on FormatException catch (error) {
      return RemoteResponderSessionResult(
        status: RemoteResponderSessionStatus.serverError,
        message: error.message,
      );
    }
  }

  @override
  Future<void> revokeSession({
    required String sessionToken,
  }) async {
    try {
      final response = await _postJson(
        '/v1/security/responders/session/revoke',
        const <String, Object?>{},
        bearerToken: sessionToken,
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.unauthorized) {
        throw HttpException(
          'Responder session revoke returned HTTP ${response.statusCode}.',
        );
      }
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    }
  }

  Future<_HttpJsonResponse> _postJson(
    String path,
    Map<String, Object?> payload, {
    String? bearerToken,
  }) async {
    final client = HttpClient();
    try {
      final target = baseUri.resolve(path);
      final request = await client.postUrl(target).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      }
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      return _HttpJsonResponse(
        statusCode: response.statusCode,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, Object?> _decodeObject(String body) {
    if (body.trim().isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object response.');
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
}

class _HttpJsonResponse {
  const _HttpJsonResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}
