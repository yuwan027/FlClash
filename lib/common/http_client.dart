import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// JWT token 管理的 Riverpod Provider，初始为 null（未登录或无token）
final jwtTokenProvider = StateProvider<String?>((ref) => null);

typedef OnUnauthorizedCallback = void Function();

class HttpClientHelper {
  final HttpClient _httpClient = HttpClient();

  /// 通过回调异步获取当前有效的 JWT token（可能为 null）
  final Future<String?> Function() getToken;

  /// 当收到 401 Unauthorized 时触发回调，一般用来跳转登录页
  final OnUnauthorizedCallback onUnauthorized;

  HttpClientHelper({
    required this.getToken,
    required this.onUnauthorized,
  });

  /// 发送 POST 请求，body 是 json 格式，自动添加 token（如果有且匹配 baseUrl）
  Future<Map<String, dynamic>> postJson(
    Uri url,
    Map<String, dynamic> jsonBody, {
    Map<String, String>? headers,
  }) async {
    print('[HTTP] POST $url');
    print('[HTTP] Request body: ${jsonEncode(jsonBody)}');

    final request = await _httpClient.postUrl(url);

    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

    if (url.toString().startsWith(AppConfig.baseUrl)) {
      // 添加自定义 User-Agent
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);

      // 自动添加 token 头（无 Bearer 前缀）
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, token);
      }
    }

    // 合并用户传入的额外 headers，覆盖前面设置的相同 key
    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });

    // 发送请求体
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
    } else if (response.statusCode == 401) {
      // Token 过期或未授权，执行回调
      onUnauthorized();
      throw Exception('未授权（401），请重新登录');
    } else {
      throw Exception('HTTP请求失败，状态码: ${response.statusCode}');
    }
  }

  /// 关闭底层 HttpClient
  void close() {
    _httpClient.close(force: true);
  }
}
