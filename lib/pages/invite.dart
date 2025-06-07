import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart'; // 用于日期格式化
import 'package:fl_chart/fl_chart.dart'; // 导入 fl_chart

class InviteDetail {
  final String billNo;
  final int paymentAmount;
  final int commissionAmount;
  final int paymentTime;

  InviteDetail({
    required this.billNo,
    required this.paymentAmount,
    required this.commissionAmount,
    required this.paymentTime,
  });

  factory InviteDetail.fromJson(Map<String, dynamic> json) {
    return InviteDetail(
      billNo: json['trade_no'] ?? '',
      paymentAmount: json['order_amount'] ?? 0,
      commissionAmount: json['get_amount'] ?? 0,
      paymentTime: json['created_at'] ?? 0,
    );
  }
}

class InviteCode {
  final int id;
  final int userId;
  final String code;
  final int status;
  final int pv;
  final int createdAt;
  final int updatedAt;

  InviteCode({
    required this.id,
    required this.userId,
    required this.code,
    required this.status,
    required this.pv,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InviteCode.fromJson(Map<String, dynamic> json) {
    return InviteCode(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      code: json['code'] ?? '',
      status: json['status'] ?? 0,
      pv: json['pv'] ?? 0,
      createdAt: json['created_at'] ?? 0,
      updatedAt: json['updated_at'] ?? 0,
    );
  }
}

// 添加提现配置模型
class WithdrawConfig {
  final int isTelegram;
  final String telegramDiscussLink;
  final String? stripePk;
  final List<String> withdrawMethods;
  final int withdrawClose;
  final String currency;
  final String currencySymbol;
  final int commissionDistributionEnable;
  final double? commissionDistributionL1;
  final double? commissionDistributionL2;
  final double? commissionDistributionL3;

  WithdrawConfig({
    required this.isTelegram,
    required this.telegramDiscussLink,
    this.stripePk,
    required this.withdrawMethods,
    required this.withdrawClose,
    required this.currency,
    required this.currencySymbol,
    required this.commissionDistributionEnable,
    this.commissionDistributionL1,
    this.commissionDistributionL2,
    this.commissionDistributionL3,
  });

  factory WithdrawConfig.fromJson(Map<String, dynamic> json) {
    // 处理 withdraw_methods 中的 Unicode 编码
    List<String> methods = [];
    if (json['withdraw_methods'] != null) {
      methods = (json['withdraw_methods'] as List).map((method) {
        // 将 Unicode 编码转换为实际字符
        String decoded = method as String;
        return decoded.replaceAllMapped(
          RegExp(r'\\u([0-9a-fA-F]{4})'),
          (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        );
      }).toList();
    }

    return WithdrawConfig(
      isTelegram: json['is_telegram'] ?? 0,
      telegramDiscussLink: json['telegram_discuss_link'] ?? '',
      stripePk: json['stripe_pk'],
      withdrawMethods: methods,
      withdrawClose: json['withdraw_close'] ?? 0,
      currency: json['currency'] ?? 'CNY',
      currencySymbol: json['currency_symbol'] ?? '¥',
      commissionDistributionEnable: json['commission_distribution_enable'] ?? 0,
      commissionDistributionL1: json['commission_distribution_l1']?.toDouble(),
      commissionDistributionL2: json['commission_distribution_l2']?.toDouble(),
      commissionDistributionL3: json['commission_distribution_l3']?.toDouble(),
    );
  }
}

class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key});

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  bool _isLoading = true;
  String? _error;
  List<InviteCode> _inviteCodes = [];
  List<int> _inviteStat = []; // [邀请人数, 累计返佣, 尚未确认的佣金, 返佣百分比, 可用返佣]
  List<InviteDetail> _inviteDetails = []; // 新增邀请历史记录
  double _averageCommission = 0.0; // 新增平均返佣金额

  // 添加提现相关的状态变量
  WithdrawConfig? _withdrawConfig;
  bool _isWithdrawing = false;
  String? _withdrawError;
  final TextEditingController _withdrawAmountController =
      TextEditingController();
  String? _selectedWithdrawMethod;

  @override
  void initState() {
    super.initState();
    _fetchInviteData();
    _fetchWithdrawConfig();
  }

  @override
  void dispose() {
    _withdrawAmountController.dispose();
    super.dispose();
  }

  Future<void> _fetchInviteData() async {
    print('[邀请页面] 开始获取邀请数据...');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      print('[邀请页面] 获取到JWT Token: $jwtToken');
      if (jwtToken == null) {
        setState(() {
          _error = '未登录';
          _isLoading = false;
        });
        return;
      }

      // Fetch invitation codes and stats
      print(
          '[邀请页面] 发起 invite/fetch 请求: ${AppConfig.baseUrl}/api/v1/user/invite/fetch');
      final inviteResponse = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/invite/fetch'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
        timeout: const Duration(seconds: 8),
        retries: 3,
      );
      print('[邀请页面] invite/fetch 响应状态码: ${inviteResponse.statusCode}');
      print('[邀请页面] invite/fetch 响应体: ${inviteResponse.body}');

      if (inviteResponse.statusCode == 200) {
        final data = jsonDecode(inviteResponse.body);
        if (data['data'] != null) {
          final List<dynamic> codesJson = data['data']['codes'];
          final List<dynamic> statJson = data['data']['stat'];

          setState(() {
            _inviteCodes =
                codesJson.map((json) => InviteCode.fromJson(json)).toList();
            _inviteStat = List<int>.from(statJson);
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = '获取邀请数据失败';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = '获取邀请数据失败: ${inviteResponse.statusCode}';
          _isLoading = false;
        });
      }

      // Fetch invitation details
      print(
          '[邀请页面] 发起 invite/details 请求: ${AppConfig.baseUrl}/api/v1/user/invite/details');
      final detailsResponse = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/invite/details'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
        timeout: const Duration(seconds: 8),
        retries: 3,
      );
      print('[邀请页面] invite/details 响应状态码: ${detailsResponse.statusCode}');
      print('[邀请页面] invite/details 响应体: ${detailsResponse.body}');

      if (detailsResponse.statusCode == 200) {
        final data = jsonDecode(detailsResponse.body);
        if (data['data'] != null) {
          final List<dynamic> detailsJson = data['data'];
          setState(() {
            _inviteDetails = detailsJson
                .map((json) => InviteDetail.fromJson(json))
                .toList()
              ..sort(
                  (a, b) => b.paymentTime.compareTo(a.paymentTime)); // 按时间降序排序
          });
        } else {
          print('[邀请页面] 获取邀请历史数据为空');
        }
      } else {
        print('[邀请页面] 获取邀请历史数据失败: ${detailsResponse.statusCode}');
      }
    } catch (e) {
      print('[邀请页面] 请求异常: $e');
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }

    _calculateAverageCommission(); // 计算平均返佣
  }

  Future<void> _fetchWithdrawConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) {
        print('[提现配置] JWT Token 为空');
        return;
      }

      print('[提现配置] 开始获取配置...');
      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/comm/config'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
      );

      print('[提现配置] 响应状态码: ${response.statusCode}');
      print('[提现配置] 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          setState(() {
            _withdrawConfig = WithdrawConfig.fromJson(data['data']);
            print(
                '[提现配置] 配置已更新: withdrawClose=${_withdrawConfig?.withdrawClose}');
          });
        } else {
          print('[提现配置] 响应数据为空');
        }
      }
    } catch (e) {
      print('[提现配置] 获取失败: $e');
    }
  }

  // 处理提现请求
  Future<void> _handleWithdraw() async {
    if (_selectedWithdrawMethod == null) {
      setState(() => _withdrawError = '请选择提现方式');
      return;
    }

    final amount = double.tryParse(_withdrawAmountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _withdrawError = '请输入有效的提现金额');
      return;
    }

    // 检查最低提现金额
    final amountInCents = (amount * 100).toInt();
    if (amountInCents < AppConfig.minWithdrawAmount) {
      setState(() =>
          _withdrawError = '最低提现金额为${AppConfig.minWithdrawAmount / 100}元');
      return;
    }

    setState(() {
      _isWithdrawing = true;
      _withdrawError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) {
        setState(() {
          _withdrawError = '未登录';
          _isWithdrawing = false;
        });
        return;
      }

      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/ticket/withdraw'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'withdraw_method': _selectedWithdrawMethod,
          'withdraw_account': amountInCents,
        }),
      );

      if (response.statusCode == 200) {
        // 提现成功，刷新数据
        _fetchInviteData();
        _withdrawAmountController.clear();
        _selectedWithdrawMethod = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提现申请已提交')),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        setState(() => _withdrawError = data['message'] ?? '提现失败');
      }
    } catch (e) {
      setState(() => _withdrawError = '提现请求失败: $e');
    } finally {
      setState(() => _isWithdrawing = false);
    }
  }

  // 显示提现对话框
  void _showWithdrawDialog() {
    print('[提现对话框] 开始显示对话框');
    print('[提现对话框] 配置状态: ${_withdrawConfig == null ? "null" : "已加载"}');
    print('[提现对话框] withdrawClose: ${_withdrawConfig?.withdrawClose}');

    if (_withdrawConfig == null) {
      print('[提现对话框] 配置为空，重新获取配置');
      _fetchWithdrawConfig();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在加载提现配置，请稍后重试')),
      );
      return;
    }

    if (_withdrawConfig!.withdrawClose == 1) {
      print('[提现对话框] 提现功能已关闭');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提现功能暂时关闭')),
      );
      return;
    }

    print('[提现对话框] 显示提现对话框');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('申请提现'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('可用返佣: ${_formatCommission(_inviteStat[4])}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedWithdrawMethod,
                decoration: const InputDecoration(
                  labelText: '提现方式',
                  border: OutlineInputBorder(),
                ),
                items: _withdrawConfig!.withdrawMethods.map((method) {
                  return DropdownMenuItem(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedWithdrawMethod = value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _withdrawAmountController,
                decoration: const InputDecoration(
                  labelText: '提现金额（元）',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              if (_withdrawError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _withdrawError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: _isWithdrawing ? null : _handleWithdraw,
            child: _isWithdrawing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认提现'),
          ),
        ],
      ),
    );
  }

  void _calculateAverageCommission() {
    if (_inviteDetails.isEmpty) {
      _averageCommission = 0.0;
      return;
    }
    int totalCommission =
        _inviteDetails.fold(0, (sum, detail) => sum + detail.commissionAmount);
    _averageCommission =
        totalCommission / _inviteDetails.length / 100.0; // 转换为元并计算平均值
  }

  String _formatCommission(int commission) {
    return (commission / 100).toStringAsFixed(2);
  }

  // Calculates the appropriate maxY for the chart
  double _calculateChartMaxY() {
    if (_inviteDetails.isEmpty) {
      return 5.0; // Default max Y if no data, or a small default value
    }

    // Find the maximum commission amount from details, convert to currency
    final maxCommissionAmount = _inviteDetails
        .map((e) => e.commissionAmount)
        .reduce((a, b) => a > b ? a : b);

    double rawMaxY = maxCommissionAmount / 100.0; // Convert to currency

    // Add a 20% buffer to the max Y to avoid data points touching the top
    double bufferedMaxY = rawMaxY * 1.2;

    // Ensure minimum Y value to avoid very compressed charts or division by zero with small numbers
    if (bufferedMaxY < 1.0) {
      // For example, if max commission is less than $1
      bufferedMaxY = 5.0; // A reasonable default for small values
    }
    return bufferedMaxY;
  }

  // Calculates the interval for the Y-axis to show roughly 5 lines (including 0)
  double _getChartYAxisInterval() {
    double calculatedMaxY = _calculateChartMaxY();
    // We want 5 lines (0, 1*interval, 2*interval, 3*interval, 4*interval = maxY)
    // So, interval = maxY / 4
    double interval = calculatedMaxY / 4.0;

    // Ensure interval is not too small, e.g., for very small commission values
    if (interval < 0.1) {
      // If interval is less than 10 cents
      interval = 0.1; // Set a minimum interval
    }
    return interval;
  }

  List<FlSpot> _getDailyCommissionSpots() {
    if (_inviteDetails.isEmpty) return [];

    Map<String, double> dailyCommissions = {};

    // Group commissions by day
    for (var detail in _inviteDetails) {
      DateTime paymentDate =
          DateTime.fromMillisecondsSinceEpoch(detail.paymentTime * 1000);
      String formattedDate = DateFormat('yyyy-MM-dd').format(paymentDate);
      dailyCommissions.update(
          formattedDate, (value) => value + detail.commissionAmount / 100.0,
          ifAbsent: () => detail.commissionAmount / 100.0); // 转换为元
    }

    // Sort dates and determine min/max X values
    List<DateTime> sortedDates = dailyCommissions.keys
        .map((e) => DateTime.parse(e))
        .toList()
      ..sort((a, b) => a.compareTo(b));

    if (sortedDates.isEmpty) return [];

    DateTime firstDate = sortedDates.first;
    List<FlSpot> spots = [];

    for (int i = 0; i < sortedDates.length; i++) {
      DateTime currentDate = sortedDates[i];
      double x = currentDate.difference(firstDate).inDays.toDouble();
      spots.add(FlSpot(
          x, dailyCommissions[DateFormat('yyyy-MM-dd').format(currentDate)]!));
    }

    return spots;
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀请返佣'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchInviteData,
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
                        onPressed: _fetchInviteData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 邀请统计数据
                      if (_inviteStat.isNotEmpty)
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '邀请统计',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatItem(
                                        '邀请人数', _inviteStat[0].toString()),
                                    _buildStatItem('累计返佣',
                                        '¥${_formatCommission(_inviteStat[1])}'),
                                    _buildStatItem('尚未确认',
                                        '¥${_formatCommission(_inviteStat[2])}'),
                                    _buildStatItem(
                                        '返佣比例', '${_inviteStat[3]}%'),
                                    _buildStatItem('可用返佣',
                                        '¥${_formatCommission(_inviteStat[4])}'),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _withdrawConfig?.withdrawClose == 1
                                            ? null
                                            : _showWithdrawDialog,
                                    icon: const Icon(
                                        Icons.account_balance_wallet),
                                    label: const Text('申请提现'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // 返佣图表
                      Text(
                        '邀请返佣趋势', // 标题不再限定"近5日"
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 250,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              horizontalInterval:
                                  _getChartYAxisInterval(), // 使用计算的间隔
                              verticalInterval:
                                  _getDailyCommissionSpots().length > 1
                                      ? (_getDailyCommissionSpots().last.x -
                                              _getDailyCommissionSpots()
                                                  .first
                                                  .x) /
                                          4.0
                                      : 1.0, // 动态计算横轴间隔，保持5条线
                              getDrawingHorizontalLine: (value) => const FlLine(
                                  color: Colors.grey, strokeWidth: 0.5),
                              getDrawingVerticalLine: (value) => const FlLine(
                                  color: Colors.grey, strokeWidth: 0.5),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval:
                                      _getDailyCommissionSpots().length > 1
                                          ? (_getDailyCommissionSpots().last.x -
                                                  _getDailyCommissionSpots()
                                                      .first
                                                      .x) /
                                              4.0
                                          : 1.0, // 与 verticalInterval 一致
                                  getTitlesWidget: (value, meta) {
                                    if (_inviteDetails.isEmpty)
                                      return const Text('');

                                    // Find the first recorded date to calculate the offset
                                    DateTime firstRecordedDate =
                                        DateTime.fromMillisecondsSinceEpoch(
                                      _inviteDetails
                                              .map((e) => e.paymentTime)
                                              .reduce((a, b) => a < b ? a : b) *
                                          1000,
                                    );
                                    DateTime date = firstRecordedDate
                                        .add(Duration(days: value.toInt()));

                                    return SideTitleWidget(
                                      axisSide: meta.axisSide,
                                      space: 8.0,
                                      child: Text(
                                          DateFormat('MM/dd').format(date),
                                          style: const TextStyle(fontSize: 10)),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    return Text(value.toStringAsFixed(2),
                                        style: const TextStyle(fontSize: 10));
                                  },
                                  interval: _getChartYAxisInterval(), // 与水平间隔一致
                                ),
                              ),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                  color: const Color(0xff37434d), width: 1),
                            ),
                            minX: 0,
                            maxX: _getDailyCommissionSpots().isEmpty
                                ? 0
                                : _getDailyCommissionSpots().last.x, // 动态设置最大X值
                            minY: 0,
                            maxY: _calculateChartMaxY(), // 使用计算的最大Y值
                            lineBarsData: [
                              LineChartBarData(
                                spots: _getDailyCommissionSpots(),
                                isCurved: true,
                                color: Colors.blueAccent,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 邀请码列表
                      Text(
                        '我的邀请码',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _inviteCodes.length,
                        itemBuilder: (context, index) {
                          final code = _inviteCodes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('邀请码: ${code.code}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                      '创建时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(code.createdAt * 1000))}'),
                                  Text('访问量: ${code.pv}'),
                                  // 可以根据 status 显示不同的文本，例如：
                                  // Text('状态: ${code.status == 0 ? '可用' : '未知'}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // 邀请历史
                      Text(
                        '邀请历史',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _inviteDetails.length,
                        itemBuilder: (context, index) {
                          final detail = _inviteDetails[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('账单号: ${detail.billNo}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                      '支付金额: ¥${(detail.paymentAmount / 100).toStringAsFixed(2)}'),
                                  Text(
                                      '返佣金额: ¥${(detail.commissionAmount / 100).toStringAsFixed(2)}'),
                                  Text(
                                      '支付时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(detail.paymentTime * 1000))}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }
}
