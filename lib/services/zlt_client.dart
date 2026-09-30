import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Local client for the Tozed/ZLT X17U JSON API.
///
/// The MTN X17U web UI talks to a single endpoint:
/// POST /cgi-bin/http.cgi
///
/// Reads use {"cmd": N, "method": "GET", "sessionId": "..."}.
/// Writes use the same endpoint with method POST and a fresh CSRF token.
class ZltClient {
  ZltClient({required String host})
      : host = host
            .replaceAll(RegExp(r'^https?://'), '')
            .split('#')
            .first
            .replaceAll(RegExp(r'/$'), ''),
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            responseType: ResponseType.json,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 500,
          ),
        );

  final String host;
  final Dio _dio;
  String? _sessionId;

  String get baseUrl => 'http://$host';
  String get endpoint => '$baseUrl/cgi-bin/http.cgi';
  bool get isAuthenticated => _sessionId != null && _sessionId!.isNotEmpty;

  Map<String, dynamic> get _headers => {
        'Content-Type': 'application/json;charset=UTF-8',
        'Accept': 'application/json, text/plain, */*',
        'Referer': '$baseUrl/',
      };

  Future<Map<String, dynamic>> command(
    int cmd, {
    bool authenticated = false,
  }) async {
    if (authenticated && !isAuthenticated) {
      throw ZltLoginException('Command $cmd requires a router login.');
    }

    final body = await _request({
      'cmd': cmd,
      'method': 'GET',
      'sessionId': authenticated ? _sessionId! : '',
    });

    _throwIfRefused(body, cmd);
    return body;
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw ZltLoginException('Enter the FlyX admin password.');
    }

    final challenge = await command(232);
    final token = '${challenge['token'] ?? ''}';
    if (token.isEmpty) {
      throw ZltLoginException(
        'The router did not return its login challenge token.',
      );
    }

    final requestedSession = _randomHex(32);
    final digest = sha256.convert(utf8.encode('$token$password')).toString();

    final answer = await _request({
      'cmd': 100,
      'method': 'POST',
      'username': username,
      'passwd': digest,
      'sessionId': requestedSession,
      'isAutoUpgrade': '1',
      'isCheckPasswd': '1',
    });

    if (answer['success'] != true) {
      throw ZltLoginException(
        'The router rejected the login. ${answer['message'] ?? ''}'.trim(),
      );
    }

    final returned = '${answer['sessionId'] ?? ''}';
    _sessionId = returned.isEmpty ? requestedSession : returned;
  }

  Future<Map<String, dynamic>> write(
    int cmd,
    Map<String, dynamic> fields,
  ) async {
    if (!isAuthenticated) {
      throw ZltLoginException('This action requires a router login.');
    }

    final tokenReply = await command(233, authenticated: true);
    final token = '${tokenReply['token'] ?? ''}';

    final answer = await _request({
      ...fields,
      'cmd': cmd,
      'method': 'POST',
      'success': true,
      'sessionId': _sessionId!,
      'token': token,
    });

    final message = '${answer['message'] ?? ''}'.trim();
    if (message.isNotEmpty) {
      throw ZltApiException('Command $cmd was refused: $message');
    }
    return answer;
  }

  /// Safe discovery. The three unauthenticated reads are always attempted.
  ///
  /// If the caller already logged in, additional GET-style reads are used to
  /// confirm the connected-device list and filter controls. No settings change.
  Future<ZltDiscoveryReport> discover() async {
    final responses = <int, Map<String, dynamic>>{};
    final errors = <int, String>{};

    Future<void> probe(int cmd, {bool authenticated = false}) async {
      try {
        responses[cmd] = await command(cmd, authenticated: authenticated);
      } catch (e) {
        errors[cmd] = '$e';
      }
    }

    await probe(113);
    await probe(133);
    await probe(205);

    if (isAuthenticated) {
      await probe(223, authenticated: true);
      await probe(23, authenticated: true);
      await probe(28, authenticated: true);
      await probe(30, authenticated: true);
    }

    final stationRows = responses[223]?['dhcp_list_info'];
    final ruleRows = responses[23]?['datas'];

    return ZltDiscoveryReport(
      responses: responses,
      errors: errors,
      verifiedCommands: responses.keys.toList()..sort(),
      hasStationList: stationRows is List,
      hasFilterRules: ruleRows is List,
      hasFilterModes: responses.containsKey(28) && responses.containsKey(30),
    );
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> payload) async {
    final response = await _dio.post<dynamic>(
      endpoint,
      data: jsonEncode(payload),
      options: Options(headers: _headers),
    );

    if (response.statusCode == 404) {
      throw ZltApiException(
        'The router does not expose the expected X17U API at /cgi-bin/http.cgi.',
      );
    }
    return _asMap(response.data);
  }

  void _throwIfRefused(Map<String, dynamic> body, int cmd) {
    if (body['success'] == false) {
      final message = '${body['message'] ?? 'unknown error'}';
      throw ZltApiException('Command $cmd was refused: $message');
    }
  }

  String _randomHex(int byteCount) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry('$key', val));
    }
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, val) => MapEntry('$key', val));
      }
    }
    return const {};
  }
}

class ZltDiscoveryReport {
  const ZltDiscoveryReport({
    required this.responses,
    required this.errors,
    required this.verifiedCommands,
    required this.hasStationList,
    required this.hasFilterRules,
    required this.hasFilterModes,
  });

  final Map<int, Map<String, dynamic>> responses;
  final Map<int, String> errors;
  final List<int> verifiedCommands;
  final bool hasStationList;
  final bool hasFilterRules;
  final bool hasFilterModes;

  bool get canBlock => hasFilterRules && hasFilterModes;
  bool supportsCommand(int cmd) => verifiedCommands.contains(cmd);
}

class ZltLoginException implements Exception {
  ZltLoginException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ZltApiException implements Exception {
  ZltApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
