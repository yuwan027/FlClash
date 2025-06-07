import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app.dart';
import '../models/core.dart';

class SubscriptionImporter {
  static Future<bool> importFromUrl(String subscribeUrl) async {
    try {
      print('开始从URL导入订阅: $subscribeUrl');
      final response = await HttpClient.get(
        Uri.parse(subscribeUrl),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print('订阅导入请求状态码: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('订阅导入成功');
        // 解析节点信息并保存到本地
        try {
          // 假设订阅内容为base64编码的多行节点配置
          final decoded = utf8.decode(base64.decode(response.body.trim()));
          final lines = decoded
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .toList();

          // 保存到本地存储
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('nodes', jsonEncode(lines));
          print('节点信息已保存到本地');

          // 创建 ExternalProvider 并更新 providersProvider
          final provider = ExternalProvider(
            name: 'Default Provider',
            type: 'Proxy',
            count: lines.length,
            vehicleType: 'HTTP',
            updateAt: DateTime.now(),
          );

          // 更新 providersProvider
          final container = ProviderContainer();
          container.read(providersProvider.notifier).state = [provider];
          print('providersProvider 已更新: ${container.read(providersProvider)}');

          return true;
        } catch (e) {
          print('解析或保存节点信息失败: $e');
          return false;
        }
      } else {
        print('订阅导入失败: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('订阅导入出错: $e');
      return false;
    }
  }

  static Future<bool> importSubscription() async {
    try {
      print('开始导入订阅...');
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString('user_info');
      if (userInfoStr == null) {
        print('未找到用户信息');
        return false;
      }

      final userInfo = jsonDecode(userInfoStr);
      final subscribeUrl = userInfo['subscribe_url'];
      if (subscribeUrl == null) {
        print('未找到订阅链接');
        return false;
      }

      return await importFromUrl(subscribeUrl);
    } catch (e) {
      print('订阅导入出错: $e');
      return false;
    }
  }

  static Future<bool> updateSubscription() async {
    try {
      print('开始更新订阅...');
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString('user_info');
      if (userInfoStr == null) {
        print('未找到用户信息');
        return false;
      }

      final userInfo = jsonDecode(userInfoStr);
      final subscribeUrl = userInfo['subscribe_url'];
      if (subscribeUrl == null) {
        print('未找到订阅链接');
        return false;
      }

      return await importFromUrl(subscribeUrl);
    } catch (e) {
      print('订阅更新出错: $e');
      return false;
    }
  }
}
