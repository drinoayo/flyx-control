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
  String? _loginUsername;
  String? _loginPassword;
  Future<void>? _reauthFuture;

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
    Map<String, dynamic> fields = const {},
  }) {
    return _command(
      cmd,
      authenticated: authenticated,
      fields: fields,
      allowReauth: true,
    );
  }

  Future<Map<String, dynamic>> _command(
    int cmd, {
    required bool authenticated,
    required Map<String, dynamic> fields,
    required bool allowReauth,
  }) async {
    if (authenticated && !isAuthenticated) {
      if (allowReauth && _canReauthenticate) {
        await _reauthenticate();
      } else {
        throw ZltLoginException('Command $cmd requires a router login.');
      }
    }

    final body = await _request({
      'cmd': cmd,
      'method': 'GET',
      'sessionId': authenticated ? _sessionId! : '',
      ...fields,
    });

    if (authenticated && _isNoAuth(body)) {
      _sessionId = null;
      if (allowReauth && _canReauthenticate) {
        await _reauthenticate();
        return _command(
          cmd,
          authenticated: authenticated,
          fields: fields,
          allowReauth: false,
        );
      }
    }

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
    _loginUsername = username;
    _loginPassword = password;
  }

  bool get _canReauthenticate =>
      (_loginUsername?.isNotEmpty ?? false) &&
      (_loginPassword?.isNotEmpty ?? false);

  Future<void> _reauthenticate() async {
    if (!_canReauthenticate) {
      throw ZltLoginException('The router session expired. Reconnect to FlyX.');
    }

    final existing = _reauthFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final username = _loginUsername!;
    final password = _loginPassword!;
    final future = login(username: username, password: password);
    _reauthFuture = future;

    try {
      await future;
    } finally {
      if (identical(_reauthFuture, future)) {
        _reauthFuture = null;
      }
    }
  }

  Future<Map<String, dynamic>> write(
    int cmd,
    Map<String, dynamic> fields,
  ) {
    return writeExact(cmd, fields, includeSuccess: true);
  }

  /// Mirrors the stock UI's write transport while allowing commands that do
  /// not include a synthetic success=true field.
  Future<Map<String, dynamic>> writeExact(
    int cmd,
    Map<String, dynamic> fields, {
    bool includeSuccess = false,
  }) {
    return _writeExact(
      cmd,
      fields,
      includeSuccess: includeSuccess,
      allowReauth: true,
    );
  }

  Future<Map<String, dynamic>> _writeExact(
    int cmd,
    Map<String, dynamic> fields, {
    required bool includeSuccess,
    required bool allowReauth,
  }) async {
    if (!isAuthenticated) {
      if (allowReauth && _canReauthenticate) {
        await _reauthenticate();
      } else {
        throw ZltLoginException('This action requires a router login.');
      }
    }

    final tokenReply = await _command(
      233,
      authenticated: true,
      fields: const {},
      allowReauth: allowReauth,
    );
    final token = '${tokenReply['token'] ?? ''}';
    if (token.isEmpty) {
      throw ZltApiException(
        'Command $cmd could not start because the router returned no write token.',
      );
    }

    final answer = await _request({
      ...fields,
      'cmd': cmd,
      'method': 'POST',
      if (includeSuccess) 'success': true,
      'sessionId': _sessionId!,
      'token': token,
    });

    if (_isNoAuth(answer)) {
      _sessionId = null;
      if (allowReauth && _canReauthenticate) {
        await _reauthenticate();
        return _writeExact(
          cmd,
          fields,
          includeSuccess: includeSuccess,
          allowReauth: false,
        );
      }
    }

    _throwIfRefused(answer, cmd);
    final message = '${answer['message'] ?? ''}'.trim();
    if (message.isNotEmpty && message != '0') {
      throw ZltApiException('Command $cmd was refused: $message');
    }
    return answer;
  }

  Future<List<Map<String, dynamic>>> readParentControlRules() async {
    final response = await command(
      385,
      authenticated: true,
      fields: const {'getfun': true},
    );
    final rows = response['datas'];
    if (rows is! List) {
      throw ZltApiException(
        'The router did not return a readable Parent Control rule list.',
      );
    }
    if (rows.any((row) => row is! Map)) {
      throw ZltApiException(
        'The router returned an unexpected Parent Control rule shape.',
      );
    }
    return rows
        .cast<Map>()
        .map((row) => row.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  Future<void> saveParentControlRules(
    List<Map<String, dynamic>> rules, {
    bool deletion = false,
  }) async {
    await writeExact(
      385,
      {
        'datas': rules,
        if (deletion) 'success': true,
      },
    );
    await writeExact(20, const {});
  }

  /// Stock Wi-Fi Black/White List state.
  ///
  /// subcmd "0" targets 5 GHz and "1" targets 2.4 GHz.
  /// A null return means the firmware did not materialize a datas object;
  /// the stock UI treats that state as filter=close with an empty MAC list.
  Future<Map<String, dynamic>?> readWirelessMacFilter(String subcmd) async {
    if (subcmd != '0' && subcmd != '1') {
      throw ArgumentError.value(subcmd, 'subcmd', 'Expected "0" or "1".');
    }

    final response = await command(
      278,
      authenticated: true,
      fields: {'subcmd': subcmd},
    );
    final datas = response['datas'];
    if (datas == null) return null;
    if (datas is! Map) {
      throw ZltApiException(
        'The router returned an unexpected Wi-Fi MAC-filter state.',
      );
    }

    final result = datas.map(
      (key, value) => MapEntry('$key', value),
    );
    final mode = result['macfilter'];
    final rows = result['maclist'];
    if (mode is! String || rows is! List) {
      throw ZltApiException(
        'The router returned an invalid Wi-Fi MAC-filter structure.',
      );
    }
    if (rows.any((row) => row is! Map)) {
      throw ZltApiException(
        'The router returned an invalid Wi-Fi MAC-filter list.',
      );
    }
    return result;
  }

  Future<void> saveWirelessMacFilter(
    String subcmd,
    Map<String, dynamic> datas,
  ) async {
    if (subcmd != '0' && subcmd != '1') {
      throw ArgumentError.value(subcmd, 'subcmd', 'Expected "0" or "1".');
    }
    await writeExact(
      278,
      {
        'datas': datas,
        'subcmd': subcmd,
        'success': true,
      },
    );
  }

  /// Read-only capability discovery.
  ///
  /// The authenticated probes below are GET-style commands only. They do not
  /// change Wi-Fi, filters, radio settings or any other router configuration.
  Future<ZltDiscoveryReport> discover() async {
    final responses = <int, Map<String, dynamic>>{};
    final errors = <int, String>{};
    var wifi5MacFilterAvailable = false;
    var wifi24MacFilterAvailable = false;

    Future<void> probe(
      int cmd, {
      bool authenticated = false,
      Map<String, dynamic> fields = const {},
    }) async {
      try {
        responses[cmd] = await command(
          cmd,
          authenticated: authenticated,
          fields: fields,
        );
      } catch (e) {
        errors[cmd] = '$e';
      }
    }

    await probe(113);
    await probe(133);
    await probe(205);

    if (isAuthenticated) {
      await probe(
        2,
        authenticated: true,
        fields: const {'subcmd': 0},
      );
      await probe(
        211,
        authenticated: true,
        fields: const {'subcmd': 0},
      );
      await probe(
        230,
        authenticated: true,
        fields: const {'subcmd': '0'},
      );
      await probe(
        231,
        authenticated: true,
        fields: const {'subcmd': '0'},
      );
      await probe(
        410,
        authenticated: true,
        fields: const {'subcmd': '0'},
      );
      await probe(463, authenticated: true);
      await probe(11, authenticated: true);
      await probe(223, authenticated: true);
      await probe(224, authenticated: true);
      await probe(225, authenticated: true);
      await probe(402, authenticated: true);

      await probe(18, authenticated: true);
      await probe(337, authenticated: true);
      await probe(207, authenticated: true);

      await probe(
        23,
        authenticated: true,
        fields: const {'getfun': true},
      );
      await probe(28, authenticated: true);
      await probe(30, authenticated: true);
      await probe(278, authenticated: true);
      try {
        await readWirelessMacFilter('0');
        wifi5MacFilterAvailable = true;
      } catch (_) {}
      try {
        await readWirelessMacFilter('1');
        wifi24MacFilterAvailable = true;
      } catch (_) {}
      await probe(350, authenticated: true);
      await probe(355, authenticated: true);
      await probe(397, authenticated: true);
      await probe(
        385,
        authenticated: true,
        fields: const {'getfun': true},
      );
    }

    final stationRows =
        responses[223]?['dhcp_list_info'] ?? responses[402]?['dhcp_list_info'];
    final wifi24Rows = responses[224]?['wlan24g_wifi_info'];
    final wifi5Rows = responses[225]?['wlan5g_wifi_info'];
    final ruleRows = responses[23]?['datas'];
    final parentRows = responses[385]?['datas'];

    return ZltDiscoveryReport(
      responses: responses,
      errors: errors,
      verifiedCommands: responses.keys.toList()..sort(),
      hasStationList: stationRows is List,
      hasWifi24Clients: wifi24Rows is List,
      hasWifi5Clients: wifi5Rows is List,
      hasMonthlyUsage:
          responses[337]?.containsKey('mon_download_flow') == true ||
              responses[205]?.containsKey('mon_total_flow') == true,
      hasFilterRules: ruleRows is List,
      hasFilterModes:
          responses[28]?['datas'] is List || responses[30]?['datas'] is List,
      hasParentControlRules: parentRows is List,
      hasWifi5MacFilter: wifi5MacFilterAvailable,
      hasWifi24MacFilter: wifi24MacFilterAvailable,
    );
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> payload) async {
    final response = await _dio.post<dynamic>(
      endpoint,
      data: jsonEncode(payload),
      options: Options(headers: _headers),
    );

    final status = response.statusCode;
    if (status == 404) {
      throw ZltApiException(
        'The router does not expose the expected X17U API at /cgi-bin/http.cgi.',
      );
    }
    if (status == null || status < 200 || status >= 300) {
      throw ZltApiException(
        'The router returned HTTP ${status ?? 'unknown'} for /cgi-bin/http.cgi.',
      );
    }
    return _asMap(response.data);
  }

  bool _isNoAuth(Map<String, dynamic> body) {
    if (body['success'] != false) return false;
    return '${body['message'] ?? ''}'.trim().toUpperCase() == 'NO_AUTH';
  }

  void _throwIfRefused(Map<String, dynamic> body, int cmd) {
    if (body['success'] == false) {
      final message = '${body['message'] ?? 'unknown error'}';
      if (_isNoAuth(body)) {
        throw ZltLoginException(
          'The router session expired while running command $cmd.',
        );
      }
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
    required this.hasWifi24Clients,
    required this.hasWifi5Clients,
    required this.hasMonthlyUsage,
    required this.hasFilterRules,
    required this.hasFilterModes,
    required this.hasParentControlRules,
    required this.hasWifi5MacFilter,
    required this.hasWifi24MacFilter,
  });

  final Map<int, Map<String, dynamic>> responses;
  final Map<int, String> errors;
  final List<int> verifiedCommands;
  final bool hasStationList;
  final bool hasWifi24Clients;
  final bool hasWifi5Clients;
  final bool hasMonthlyUsage;
  final bool hasFilterRules;
  final bool hasFilterModes;
  final bool hasParentControlRules;
  final bool hasWifi5MacFilter;
  final bool hasWifi24MacFilter;

  bool get hasWifiClientDetails => hasWifi24Clients || hasWifi5Clients;

  /// Instant blocking uses the verified stock Wi-Fi deny-list path on both
  /// bands. A successful read may legitimately contain no datas object while
  /// the filter is closed; availability means the command itself succeeded.
  bool get canBlock => hasWifi5MacFilter && hasWifi24MacFilter;

  bool get hasReadableMacFilterState => hasFilterRules && hasFilterModes;

  /// Scheduling is safe to expose only when cmd 385 returns a real datas list,
  /// including an explicit empty list after the last rule is deleted.
  bool get canSchedule => hasParentControlRules;

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
