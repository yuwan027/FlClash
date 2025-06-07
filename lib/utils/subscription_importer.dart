import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';

class SubscriptionImporter {
  static Future<bool> importSubscription(String subscribeUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return false;

      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/importSubscription'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'subscribe_url': subscribeUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] == true;
      }
      return false;
    } catch (e) {
      print('导入订阅失败: $e');
      return false;
    }
  }

  static Future<bool> updateSubscription(String subscribeUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return false;

      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/updateSubscription'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'subscribe_url': subscribeUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] == true;
      }
      return false;
    } catch (e) {
      print('更新订阅失败: $e');
      return false;
    }
  }
}
