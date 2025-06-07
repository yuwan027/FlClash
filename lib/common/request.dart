import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';

class Request {
  late final Dio _dio;
  late final Dio _clashDio;
  String? userAgent;

  Request() {
    _dio = Dio(
      BaseOptions(
        headers: {
          "User-Agent": browserUa,
        },
      ),
    );

    // 添加请求拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        commonPrint.log('请求URL: ${options.uri}');
        commonPrint.log('请求方法: ${options.method}');
        commonPrint.log('请求头: ${options.headers}');
        if (options.data != null) {
          commonPrint.log('请求体: ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        commonPrint.log('响应状态码: ${response.statusCode}');
        commonPrint.log('响应头: ${response.headers}');
        commonPrint.log('响应体: ${response.data}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        commonPrint.log('请求错误: ${e.message}');
        commonPrint.log('错误类型: ${e.type}');
        commonPrint.log('错误响应: ${e.response?.data}');
        return handler.next(e);
      },
    ));

    _clashDio = Dio();
    _clashDio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (Uri uri) {
        client.userAgent = globalState.ua;
        return FlClashHttpOverrides.handleFindProxy(uri);
      };
      return client;
    });

    // 为_clashDio也添加相同的拦截器
    _clashDio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        commonPrint.log('Clash请求URL: ${options.uri}');
        commonPrint.log('Clash请求方法: ${options.method}');
        commonPrint.log('Clash请求头: ${options.headers}');
        if (options.data != null) {
          commonPrint.log('Clash请求体: ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        commonPrint.log('Clash响应状态码: ${response.statusCode}');
        commonPrint.log('Clash响应头: ${response.headers}');
        commonPrint.log('Clash响应体: ${response.data}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        commonPrint.log('Clash请求错误: ${e.message}');
        commonPrint.log('Clash错误类型: ${e.type}');
        commonPrint.log('Clash错误响应: ${e.response?.data}');
        return handler.next(e);
      },
    ));
  }

  Future<Response> get(String url, {Options? options}) async {
    return await _dio.get(url, options: options);
  }

  Future<Response> post(String url, {dynamic data, Options? options}) async {
    return await _dio.post(url, data: data, options: options);
  }

  Future<Response> getFileResponseForUrl(String url) async {
    final response = await _clashDio.get(
      url,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
    return response;
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await _dio.get<Uint8List>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    final response = await _dio.get(
      "https://api.github.com/repos/$repository/releases/latest",
      options: Options(
        responseType: ResponseType.json,
      ),
    );
    if (response.statusCode != 200) return null;
    final data = response.data as Map<String, dynamic>;
    final remoteVersion = data['tag_name'];
    final version = globalState.packageInfo.version;
    final hasUpdate =
        utils.compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
    if (!hasUpdate) return null;
    return data;
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    "https://ipwho.is/": IpInfo.fromIpwhoIsJson,
    "https://api.ip.sb/geoip/": IpInfo.fromIpSbJson,
    "https://ipapi.co/json/": IpInfo.fromIpApiCoJson,
    "https://ipinfo.io/json/": IpInfo.fromIpInfoIoJson,
  };

  Future<IpInfo?> checkIp({CancelToken? cancelToken}) async {
    for (final source in _ipInfoSources.entries) {
      try {
        final response = await Dio()
            .get<Map<String, dynamic>>(
              source.key,
              cancelToken: cancelToken,
              options: Options(
                responseType: ResponseType.json,
              ),
            )
            .timeout(
              Duration(
                seconds: 30,
              ),
            );
        if (response.statusCode != 200 || response.data == null) {
          continue;
        }
        if (response.data == null) {
          continue;
        }
        return source.value(response.data!);
      } catch (e) {
        commonPrint.log("checkIp error ===> $e");
        if (e is DioException && e.type == DioExceptionType.cancel) {
          throw "cancelled";
        }
      }
    }
    return null;
  }

  Future<bool> pingHelper() async {
    try {
      final response = await _dio
          .get(
            "http://$localhost:$helperPort/ping",
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String) == globalState.coreSHA256;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/start",
            data: json.encode({
              "path": appPath.corePath,
              "arg": arg,
            }),
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopCoreByHelper() async {
    try {
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/stop",
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }
}

final request = Request();
