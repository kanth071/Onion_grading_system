import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the FastAPI backend (see backend/app/main.py). Base URL is
/// user-configurable at runtime (gear icon) since a phone on the same
/// Wi-Fi needs the PC's LAN IP, not localhost.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _prefKey = 'api_base_url';
  static const defaultBaseUrl = 'http://10.0.2.2:8000'; // Android emulator -> host loopback

  String _baseUrl = defaultBaseUrl;
  String get baseUrl => _baseUrl;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_prefKey) ?? defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _baseUrl);
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<dynamic> getJson(String path) async {
    final res = await http.get(_uri(path)).timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<dynamic> putJson(String path, Map<String, dynamic> body) async {
    final res = await http
        .put(_uri(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<Map<String, dynamic>> uploadInspection({
    required List<File> files,
    required String mode,
    String? batchLabel,
    double? pxPerCm,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/api/inspections'));
    request.fields['mode'] = mode;
    if (batchLabel != null && batchLabel.isNotEmpty) request.fields['batch_label'] = batchLabel;
    if (pxPerCm != null) request.fields['px_per_cm'] = pxPerCm.toString();
    for (final f in files) {
      request.files.add(await http.MultipartFile.fromPath('files', f.path));
    }
    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final res = await http.Response.fromStream(streamed);
    final decoded = _decode(res);
    return decoded as Map<String, dynamic>;
  }

  String reportUrl(String inspectionId) => '$_baseUrl/api/inspections/$inspectionId/report.pdf';

  String absoluteImageUrl(String relativeUrl) => '$_baseUrl$relativeUrl';

  Future<File> downloadReport(String inspectionId, String savePath) async {
    final res = await http.get(_uri('/api/inspections/$inspectionId/report.pdf'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw ApiException('Could not download report (HTTP ${res.statusCode}).');
    }
    final file = File(savePath);
    await file.writeAsBytes(res.bodyBytes);
    return file;
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = res.reasonPhrase ?? 'Request failed';
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['detail'] != null) detail = body['detail'].toString();
      } catch (_) {}
      throw ApiException(detail);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
