import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';

class HttpClientHelper {
  final HttpClient _httpClient = HttpClient();

  /// 通用POST请求，发送jsonBody，返回解析后的json Map
  Future<Map<String, dynamic>> postJson(Uri url, Map<String, dynamic> jsonBody,
      {Map<String, String>? headers}) async {
    print('[HTTP] POST $url');
    print('[HTTP] Request body: ${jsonEncode(jsonBody)}');

    final request = await _httpClient.postUrl(url);

    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

    // 只有当请求URL以 baseUrl 开头时，才设置特定User-Agent
    if (url.toString().startsWith(AppConfig.baseUrl)) {
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);
    }

    // 如果额外传入headers，覆盖或添加
    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });

    request.add(utf8.encode(jsonEncode(jsonBody)));

    final response = await request.close();

    final responseBody = await response.transform(utf8.decoder).join();

    print('[HTTP] Response status: ${response.statusCode}');
    print('[HTTP] Response body: $responseBody');

    if (response.statusCode == 200) {
      try {
        return jsonDecode(responseBody);
      } catch (e) {
        throw Exception('响应JSON解析失败: $e');
      }
    } else {
      throw Exception('HTTP请求失败，状态码: ${response.statusCode}');
    }
  }

  void close() {
    _httpClient.close(force: true);
  }
}
