import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Minimal, safety-first client for the ZLT/ZTE reqproc API family.
///
/// Reads are safe. Writes are only exposed through [post] and should only be
/// called when the action was observed in the router's own JavaScript.
class ZltClient {
  ZltClient({required String host})
      : host = host.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/$'), ''),
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
            responseType: ResponseType.json,
            validateStatus: (status) => status != null && status >= 200 && status < 500,
          ),
        );

  final String host;
  final Dio _dio;
  String? _randomCookie;

  String get baseUrl => 'http://$host';

  Map<String, dynamic> _headers({bool form = false}) => {
        'Referer': '$baseUrl/index.html',
        'X-Requested-With': 'XMLHttpRequest',
        if (form) 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        if (_randomCookie != null) 'Cookie': 'random=$_randomCookie',
      };

  Future<Map<String, dynamic>> read(List<String> commands) async {
    if (commands.isEmpty) return const {};
    final response = await _dio.get<dynamic>(
      '$baseUrl/reqproc/proc_get',
      queryParameters: {
        'isTest': 'false',
        if (commands.length > 1) 'multi_data': '1',
        'cmd': commands.join(','),
      },
      options: Options(headers: _headers()),
    );
    return _asMap(response.data);
  }

  Future<void> login({required String username, required String password}) async {
    final safety = await read(['psw_fail_num_str', 'login_lock_time']);
    final attempts = int.tryParse('${safety['psw_fail_num_str'] ?? ''}');
    final lockTime = int.tryParse('${safety['login_lock_time'] ?? ''}');
    if ((lockTime ?? -1) > 0 || (attempts != null && attempts < 2)) {
      throw ZltLoginException(
        'Router login is close to or currently in lockout. Open the router web UI and verify the password before trying again.',
      );
    }

    final nonceMap = await read(['get_random_login']);
    final nonce = '${nonceMap['random_login'] ?? nonceMap['get_random_login'] ?? ''}';
    if (nonce.isEmpty) {
      throw ZltLoginException('The router did not return a login nonce. This firmware may use a different authentication flow.');
    }

    final token = await _token();
    final digestHex = sha256.convert(utf8.encode('$nonce$password')).toString();
    final encodedUsername = base64Encode(utf8.encode(username));
    final encodedPassword = base64Encode(utf8.encode(digestHex));

    final response = await _dio.post<dynamic>(
      '$baseUrl/reqproc/proc_post',
      data: {
        'isTest': 'false',
        'goformId': 'LOGIN',
        'username': encodedUsername,
        'password': encodedPassword,
        'CSRFToken': token,
      },
      options: Options(
        headers: _headers(form: true),
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    _captureSessionCookie(response.headers);
    final body = _asMap(response.data);
    final result = '${body['result'] ?? ''}';
    if (result != '0' && result != '4' && result.toLowerCase() != 'success') {
      throw ZltLoginException('The router rejected the login. Result: ${result.isEmpty ? 'unknown' : result}');
    }
  }

  Future<Map<String, dynamic>> post(
    String goformId,
    Map<String, dynamic> fields,
  ) async {
    final token = await _token();
    final response = await _dio.post<dynamic>(
      '$baseUrl/reqproc/proc_post',
      data: {
        'isTest': 'false',
        'goformId': goformId,
        ...fields,
        'CSRFToken': token,
      },
      options: Options(
        headers: _headers(form: true),
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    _captureSessionCookie(response.headers);
    return _asMap(response.data);
  }

  /// Reads only the router's own JavaScript to discover feature names.
  Future<ZltDiscoveryReport> discover() async {
    final status = await read([
      'network_type',
      'rssi',
      'signalbar',
      'lte_rsrq',
      'lte_pci',
      'ppp_status',
      'station_list',
      'cr_version',
      'tz_customer_code',
    ]);

    final scripts = <String>[];
    for (final path in ['/js/service.js', '/js/config/ufi/config.js', '/js/util.js']) {
      try {
        final response = await _dio.get<String>(
          '$baseUrl$path',
          options: Options(
            headers: _headers(),
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status >= 200 && status < 400,
          ),
        );
        if (response.data case final String text when text.isNotEmpty) scripts.add(text);
      } catch (_) {
        // A missing script is not a discovery failure.
      }
    }

    final source = scripts.join('\n');
    final actions = <String>{};
    for (final match in RegExp(r'''goformId\s*[:=]\s*["']([A-Z0-9_]+)["']''').allMatches(source)) {
      actions.add(match.group(1)!);
    }
    // Minified firmware sometimes stores goformIds as plain string literals.
    for (final match in RegExp(r'''["']([A-Z][A-Z0-9_]{4,})["']''').allMatches(source)) {
      final value = match.group(1)!;
      if (value.contains('SMS') ||
          value.contains('USSD') ||
          value.contains('WIFI') ||
          value.contains('REBOOT') ||
          value.contains('TRAFFIC_BLOCK') ||
          value.contains('BEARER')) {
        actions.add(value);
      }
    }

    return ZltDiscoveryReport(
      status: status,
      actions: actions.toList()..sort(),
      hasStationList: status['station_list'] is List || '${status['station_list'] ?? ''}'.isNotEmpty,
    );
  }

  Future<String> _token() async {
    final response = await read(['get_token']);
    return '${response['token'] ?? response['get_token'] ?? ''}';
  }

  void _captureSessionCookie(Headers headers) {
    final values = headers.map['set-cookie'] ?? const <String>[];
    for (final value in values) {
      final match = RegExp(r'(?:^|;\s*)random=([^;]+)').firstMatch(value);
      if (match != null) {
        _randomCookie = match.group(1);
        return;
      }
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, val) => MapEntry('$key', val));
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.map((key, val) => MapEntry('$key', val));
    }
    return const {};
  }
}

class ZltDiscoveryReport {
  const ZltDiscoveryReport({
    required this.status,
    required this.actions,
    required this.hasStationList,
  });

  final Map<String, dynamic> status;
  final List<String> actions;
  final bool hasStationList;

  bool hasAction(String action) => actions.contains(action);
}

class ZltLoginException implements Exception {
  ZltLoginException(this.message);
  final String message;

  @override
  String toString() => message;
}
