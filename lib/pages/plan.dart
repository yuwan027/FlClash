import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import '../config/app_config.dart';
import '../common/http_client.dart';
import '../models/plan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'order.dart';

class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({super.key});

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  bool _isLoading = true;
  List<Plan> _plans = [];
  String? _error;
  bool _isPurchaseDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
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

      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/plan/fetch'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
        timeout: const Duration(seconds: 8),
        retries: 3,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final List<dynamic> plansJson = data['data'];
          setState(() {
            _plans = plansJson.map((json) => Plan.fromJson(json)).toList()
              ..sort((a, b) => a.sort.compareTo(b.sort));
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
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createOrder(Plan plan, String period) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未登录')),
          );
        }
        return;
      }

      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/order/save'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'plan_id': plan.id,
          'period': period,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          if (mounted) {
            if (_isPurchaseDialogShowing && Navigator.of(context).canPop()) {
              Navigator.pop(context);
            }
            _isPurchaseDialogShowing = false;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const OrderPage(),
              ),
            );
          }
        }
      } else {
        if (_isPurchaseDialogShowing &&
            mounted &&
            Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
        _isPurchaseDialogShowing = false;

        Map<String, dynamic>? data;
        try {
          if (response.body.isNotEmpty) {
            data = jsonDecode(response.body);
          }
        } catch (e) {
          print('Error decoding response body: $e');
        }

        if (mounted) {
          if (data != null &&
              (data['message']?.toString().contains('未支付订单') ?? false)) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('提示'),
                content: const Text('您有老的未付订单，请先前往订单管理页面取消老订单'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            );
          } else {
            Future.delayed(const Duration(milliseconds: 100), () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('创建订单失败: ${data?['message'] ?? '未知错误，请重试。'}')),
              );
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        if (_isPurchaseDialogShowing && Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
        _isPurchaseDialogShowing = false;

        Future.delayed(const Duration(milliseconds: 100), () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('提示'),
              content: const Text('创建订单失败，请检查网络或前往订单管理页面取消老订单再重试。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
        });
        print('创建订单失败 (捕获异常): $e');
      }
    }
  }

  void _showPurchaseDialog(BuildContext context, Plan plan) {
    _isPurchaseDialogShowing = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择购买周期',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (plan.monthPrice != null)
              _buildPurchaseOption(
                context,
                '月付',
                plan.formattedMonthPrice,
                () => _createOrder(plan, 'month_price'),
              ),
            if (plan.quarterPrice != null)
              _buildPurchaseOption(
                context,
                '季付',
                plan.formattedQuarterPrice,
                () => _createOrder(plan, 'quarter_price'),
              ),
            if (plan.halfYearPrice != null)
              _buildPurchaseOption(
                context,
                '半年付',
                plan.formattedHalfYearPrice,
                () => _createOrder(plan, 'half_year_price'),
              ),
            if (plan.yearPrice != null)
              _buildPurchaseOption(
                context,
                '年付',
                plan.formattedYearPrice,
                () => _createOrder(plan, 'year_price'),
              ),
            if (plan.twoYearPrice != null)
              _buildPurchaseOption(
                context,
                '两年付',
                plan.formattedTwoYearPrice,
                () => _createOrder(plan, 'two_year_price'),
              ),
            if (plan.threeYearPrice != null)
              _buildPurchaseOption(
                context,
                '三年付',
                plan.formattedThreeYearPrice,
                () => _createOrder(plan, 'three_year_price'),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseOption(
    BuildContext context,
    String period,
    String price,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              period,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              price,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('套餐列表'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlans,
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
                        onPressed: _loadPlans,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    return Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${plan.formattedTransferEnable} / 月',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (plan.sort <= 8)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '推荐',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '订阅介绍',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Html(
                                        data: plan.content,
                                        style: {
                                          'body': Style(
                                            margin: Margins.zero,
                                            padding: HtmlPaddings.zero,
                                            fontSize: FontSize(14),
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color,
                                          ),
                                          'br': Style(
                                            margin: Margins.zero,
                                            padding: HtmlPaddings.zero,
                                          ),
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (plan.monthPrice != null ||
                                      plan.quarterPrice != null)
                                    ElevatedButton(
                                      onPressed: () =>
                                          _showPurchaseDialog(context, plan),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: Colors.white,
                                        minimumSize:
                                            const Size(double.infinity, 48),
                                      ),
                                      child: const Text(
                                        '购买',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
