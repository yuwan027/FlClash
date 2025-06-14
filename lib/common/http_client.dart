import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 这里用 String?，为空时代表没登录或无auth_data
final jwtTokenProvider = StateProvider<String?>((ref) => null);

typedef OnUnauthorizedCallback = void Function();

class HttpClientHelper {
  final HttpClient _httpClient = HttpClient();

  /// 获取当前有效 JWT 的异步方法
  final Future<String?> Function() getToken;

  /// 遇到401时调用，进行登录跳转等操作
  final OnUnauthorizedCallback onUnauthorized;

  HttpClientHelper({
    required this.getToken,
    required this.onUnauthorized,
  });

  Future<Map<String, dynamic>> getJson(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    print('[HTTP] GET $url');

    final request = await _httpClient.getUrl(url);

    if (url.toString().startsWith(AppConfig.baseUrl)) {
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);

      final authData = await getToken();
      if (authData != null && authData.isNotEmpty) {
        // 直接使用 auth_data，不添加 Bearer 前缀
        request.headers.set(HttpHeaders.authorizationHeader, authData);
      }
    }

    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });

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
      onUnauthorized();
      throw Exception('未授权（401），请重新登录');
    } else {
      throw Exception('HTTP请求失败，状态码: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> postJson(Uri url, Map<String, dynamic> jsonBody,
      {Map<String, String>? headers}) async {
    print('[HTTP] POST $url');
    print('[HTTP] Request body: ${jsonEncode(jsonBody)}');

    final request = await _httpClient.postUrl(url);

    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

    if (url.toString().startsWith(AppConfig.baseUrl)) {
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);

      final authData = await getToken();
      if (authData != null && authData.isNotEmpty) {
        // 直接使用 auth_data，不添加 Bearer 前缀
        request.headers.set(HttpHeaders.authorizationHeader, authData);
      }
    }

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
    } else if (response.statusCode == 401) {
      onUnauthorized();
      throw Exception('未授权（401），请重新登录');
    } else {
      throw Exception('HTTP请求失败，状态码: ${response.statusCode}');
    }
  }

  void close() {
    _httpClient.close(force: true);
  }
}
