import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../config/app_config.dart';
import '../common/http_client.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'payment_page.dart';

class OrderPage extends ConsumerStatefulWidget {
  const OrderPage({super.key});

  @override
  ConsumerState<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends ConsumerState<OrderPage> {
  bool _isLoading = true;
  List<Order> _orders = [];
  String? _error;
  Timer? _checkTimer;
  String? _checkingTradeNo;
  Map<String, dynamic>? _subscriptionInfo;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) {
        setState(() {
          _error = '未登录';
          _isLoading = false;
        });
        return;
      }

      print('\n[订单列表] ====== 开始请求订单列表 ======');
      print('[订单列表] 请求URL: ${AppConfig.baseUrl}/api/v1/user/order/fetch');
      print(
          '[订单列表] 请求头: Authorization: $jwtToken, User-Agent: ${AppConfig.userAgent}');

      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/order/fetch'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
        timeout: const Duration(seconds: 8),
        retries: 3,
      );

      print('\n[订单列表] ====== 收到响应 ======');
      print('[订单列表] 响应状态码: ${response.statusCode}');
      print('[订单列表] 响应体: ${response.body}');
      print('[订单列表] ====== 响应结束 ======\n');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final List<dynamic> ordersJson = data['data'];
          print('\n[订单列表] ====== 订单数据解析 ======');
          for (var json in ordersJson) {
            print('[订单列表] 订单号: ${json['trade_no']}, 类型: ${json['type']}');
          }
          print('[订单列表] ====== 解析结束 ======\n');

          setState(() {
            _orders = ordersJson.map((json) => Order.fromJson(json)).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = '获取数据失败';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = '获取数据失败: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('\n[订单列表] ====== 请求异常 ======');
      print('[订单列表] 错误信息: $e');
      print('[订单列表] ====== 异常结束 ======\n');
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<List<PaymentMethod>> _getPaymentMethods() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return [];

      print('[支付方式] 开始获取支付方式...');
      print(
          '[支付方式] 请求URL: ${AppConfig.baseUrl}/api/v1/user/order/getPaymentMethod');
      print(
          '[支付方式] 请求头: Authorization: $jwtToken, User-Agent: ${AppConfig.userAgent}');

      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/order/getPaymentMethod'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
      );

      print('[支付方式] 响应状态码: ${response.statusCode}');
      print('[支付方式] 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final List<dynamic> methodsJson = data['data'];
          return methodsJson
              .map((json) => PaymentMethod.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('[支付方式] 请求异常: $e');
      return [];
    }
  }

  Future<void> _checkOrderStatus(String tradeNo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return;

      print('[订单状态] 开始检查订单状态...');
      print(
          '[订单状态] 请求URL: ${AppConfig.baseUrl}/api/v1/user/order/check?trade_no=$tradeNo');
      print(
          '[订单状态] 请求头: Authorization: $jwtToken, User-Agent: ${AppConfig.userAgent}');

      final response = await HttpClient.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/v1/user/order/check?trade_no=$tradeNo'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
      );

      print('[订单状态] 响应状态码: ${response.statusCode}');
      print('[订单状态] 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // 0: 待支付, 1: 正在开通, 2: 已取消, 3: 已完成, 4: 已抵扣
        if (data['status'] == 2 || data['status'] == 3 || data['status'] == 4) {
          _checkTimer?.cancel();
          _checkingTradeNo = null;
          _loadOrders();
        } else if (data['status'] == 1) {
          // 正在开通状态，继续检查
          _startCheckingOrder(tradeNo);
        }
      }
    } catch (e) {
      print('[订单状态] 请求异常: $e');
    }
  }

  Future<void> _startCheckingOrder(String tradeNo) async {
    _checkingTradeNo = tradeNo;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_checkingTradeNo != null) {
        _checkOrderStatus(_checkingTradeNo!);
      }
    });
  }

  Future<void> _checkout(Order order, int methodId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return;

      final requestBody = {
        'trade_no': order.tradeNo,
        'method': methodId,
      };

      print('[支付] 开始发起支付...');
      print('[支付] 请求URL: ${AppConfig.baseUrl}/api/v1/user/order/checkout');
      print(
          '[支付] 请求头: Authorization: $jwtToken, User-Agent: ${AppConfig.userAgent}');
      print('[支付] 请求体: ${jsonEncode(requestBody)}');

      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/order/checkout'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('[支付] 响应状态码: ${response.statusCode}');
      print('[支付] 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['type'] == -1) {
          // 金额为0，直接支付成功
          _loadOrders();
        } else if (data['type'] == 1 && data['data'] != null) {
          // 在应用内打开支付链接
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentPage(
                  paymentUrl: data['data'],
                  tradeNo: order.tradeNo,
                ),
              ),
            ).then((_) {
              // 支付页面关闭后，开始检查订单状态
              _startCheckingOrder(order.tradeNo);
            });
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('支付失败: ${response.body}')),
          );
        }
      }
    } catch (e) {
      print('[支付] 请求异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('支付失败: $e')),
        );
      }
    }
  }

  void _showPaymentDialog(Order order) async {
    final methods = await _getPaymentMethods();
    if (methods.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取支付方式失败')),
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择支付方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: methods
              .map((method) => ListTile(
                    title: Text(method.name),
                    onTap: () {
                      Navigator.pop(context);
                      _checkout(order, method.id);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 设置窗口大小
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        windowManager.getSize().then((size) {
          if (size.width < 800) {
            windowManager.setSize(const Size(1000, 800));
          }
        });
      });
      windowManager.setMinimumSize(const Size(800, 800));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('订单管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadOrders,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _orders.isEmpty
                  ? const Center(
                      child: Text('暂无订单'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '订单号：${order.tradeNo}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: order.status == 0
                                            ? Colors.orange[100]
                                            : Colors.green[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        order.statusText,
                                        style: TextStyle(
                                          color: order.status == 0
                                              ? Colors.orange[900]
                                              : Colors.green[900],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '订单类型：${order.typeText}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '购买周期：${order.periodText}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '金额：¥${order.formattedBalanceAmount}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '创建时间：${order.createdAt.toString().substring(0, 19)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (order.paidAt != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '支付时间：${order.paidAt.toString().substring(0, 19)}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                                if (order.isPending) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => _showPaymentDialog(order),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('去支付'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
