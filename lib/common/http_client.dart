import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:fl_clash/common/common.dart';

class HttpClient {
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    int? retries,
  }) async {
    int attempts = 0;
    int maxAttempts = retries ?? 1;

    while (attempts < maxAttempts) {
      try {
        final response = await http
            .get(
              url,
              headers: headers,
            )
            .timeout(timeout ?? const Duration(seconds: 8));

        if (response.statusCode == 200) {
          return response;
        }

        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
      } catch (e) {
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        rethrow;
      }
    }

    throw Exception('请求失败，已重试 $maxAttempts 次');
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int? retries,
  }) async {
    int attempts = 0;
    int maxAttempts = retries ?? 1;

    while (attempts < maxAttempts) {
      try {
        final response = await http
            .post(
              url,
              headers: headers,
              body: body,
            )
            .timeout(timeout ?? const Duration(seconds: 8));

        if (response.statusCode == 200) {
          return response;
        }

        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
      } catch (e) {
        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        rethrow;
      }
    }

    throw Exception('请求失败，已重试 $maxAttempts 次');
  }
}
