import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_clash/common/common.dart';

class HttpClient {
  static Future<http.Response> get(Uri url,
      {Map<String, String>? headers}) async {
    commonPrint.log('HTTP请求URL: $url');
    commonPrint.log('HTTP请求方法: GET');
    if (headers != null) {
      commonPrint.log('HTTP请求头: $headers');
    }

    final response = await http.get(url, headers: headers);

    commonPrint.log('HTTP响应状态码: ${response.statusCode}');
    commonPrint.log('HTTP响应头: ${response.headers}');
    commonPrint.log('HTTP响应体: ${response.body}');

    return response;
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    commonPrint.log('HTTP请求URL: $url');
    commonPrint.log('HTTP请求方法: POST');
    if (headers != null) {
      commonPrint.log('HTTP请求头: $headers');
    }
    if (body != null) {
      commonPrint.log('HTTP请求体: $body');
    }

    final response =
        await http.post(url, headers: headers, body: body, encoding: encoding);

    commonPrint.log('HTTP响应状态码: ${response.statusCode}');
    commonPrint.log('HTTP响应头: ${response.headers}');
    commonPrint.log('HTTP响应体: ${response.body}');

    return response;
  }
}
