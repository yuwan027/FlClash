import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:window_manager/window_manager.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';
import '../l10n/l10n.dart';
import '../utils/subscription_importer.dart';
import 'login.dart';
import 'node_list.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _subscriptionInfo;
  final TextEditingController _transferAmountController =
      TextEditingController();
  bool _isLoading = false;
  String _balance = '0.00';
  String _commission = '0.00';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadSubscriptionInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwt_token');
    if (jwtToken == null) return;

    try {
      print('开始加载用户信息...');
      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
        headers: {'Authorization': jwtToken, 'User-Agent': AppConfig.userAgent},
      );

      if (response.statusCode == 200) {
        print('用户信息加载成功，开始解析数据...');
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          print('用户信息数据: ${data['data']}');
          await prefs.setString('user_info', jsonEncode(data['data']));
          if (mounted) {
            setState(() {
              _userInfo = data['data'];
              _balance = _formatBalance(_userInfo!['balance']);
              _commission = _formatBalance(_userInfo!['commission_balance']);
            });
          }
        }
      }
    } catch (e) {
      print('获取用户信息失败: $e');
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwt_token');
    if (jwtToken == null) return;

    try {
      print('开始加载订阅信息...');
      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/getSubscribe'),
        headers: {'Authorization': jwtToken, 'User-Agent': AppConfig.userAgent},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data']['subscribe_url'] != null) {
          final subscribeUrl = data['data']['subscribe_url'] as String;
          print('获取到订阅链接: $subscribeUrl');

          // 保存或使用订阅链接
          setState(() {
            _subscriptionInfo = data['data'];
          });

          // 检查是否需要更新订阅
          final lastUpdateTime = prefs.getInt('last_subscription_update');
          final now = DateTime.now().millisecondsSinceEpoch;
          final shouldUpdate = lastUpdateTime == null ||
              (now - lastUpdateTime) > 3600000; // 1小时更新一次

          if (shouldUpdate) {
            // 直接导入订阅
            final success =
                await SubscriptionImporter.importFromUrl(subscribeUrl);
            print('导入订阅结果: $success');

            if (success && mounted) {
              // 保存更新时间
              await prefs.setInt('last_subscription_update', now);
              _showSuccessSnackBar('订阅导入成功');
            }
          } else {
            print('订阅已是最新，无需更新');
          }
        } else {
          print('未获取到有效的订阅链接');
        }
      }
    } catch (e) {
      print('获取订阅信息失败: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  String _formatBalance(int balance) {
    return (balance / 100).toStringAsFixed(2);
  }

  double _calculateUsagePercentage() {
    if (_subscriptionInfo == null || _userInfo == null) return 0;
    final total = _userInfo!['transfer_enable'] as int;
    final used =
        (_subscriptionInfo!['u'] as int) + (_subscriptionInfo!['d'] as int);
    return used / total;
  }

  Color _getProgressColor(double percentage) {
    if (percentage < 0.5) {
      return Colors.green;
    } else if (percentage < 0.8) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  String _getRemainingTraffic() {
    if (_subscriptionInfo == null || _userInfo == null) return '0 B';
    final total = _userInfo!['transfer_enable'] as int;
    final used =
        (_subscriptionInfo!['u'] as int) + (_subscriptionInfo!['d'] as int);
    return _formatBytes(total - used);
  }

  String _getExpiryText() {
    if (_userInfo == null || _userInfo!['expired_at'] == null) {
      return '该订阅永不到期';
    }

    final expiredAt = DateTime.fromMillisecondsSinceEpoch(
      _userInfo!['expired_at'] * 1000,
    );
    final now = DateTime.now();
    final difference = expiredAt.difference(now).inDays;

    if (difference <= 0) {
      return '该订阅已过期';
    }
    return '该订阅剩余$difference天到期';
  }

  Color _getExpiryColor() {
    if (_userInfo == null || _userInfo!['expired_at'] == null) {
      return Colors.grey[600]!;
    }

    final expiredAt = DateTime.fromMillisecondsSinceEpoch(
      _userInfo!['expired_at'] * 1000,
    );
    final now = DateTime.now();
    final difference = expiredAt.difference(now).inDays;

    if (difference <= 7) {
      return Colors.red;
    }
    return Colors.grey[600]!;
  }

  bool _shouldShowWarning() {
    if (_userInfo == null || _userInfo!['expired_at'] == null) {
      return false;
    }

    final expiredAt = DateTime.fromMillisecondsSinceEpoch(
      _userInfo!['expired_at'] * 1000,
    );
    final now = DateTime.now();
    final difference = expiredAt.difference(now).inDays;

    return difference <= 7;
  }

  Future<void> _transferBalance() async {
    if (_transferAmountController.text.isEmpty) return;

    final amount = double.tryParse(_transferAmountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).enterValidAmount)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return;

      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/transfer'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'transfer_amount': (amount * 100).toInt()}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).transferSuccess)),
        );
        _transferAmountController.clear();

        // 立即请求用户信息更新余额和佣金
        try {
          final userInfoResponse = await HttpClient.get(
            Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
            headers: {
              'Authorization': jwtToken,
              'User-Agent': AppConfig.userAgent,
            },
          );

          if (userInfoResponse.statusCode == 200) {
            final data = jsonDecode(userInfoResponse.body);
            if (data['data'] != null) {
              await prefs.setString('user_info', jsonEncode(data['data']));
              if (mounted) {
                setState(() {
                  _userInfo = data['data'];
                  _balance = _formatBalance(_userInfo!['balance']);
                  _commission = _formatBalance(
                    _userInfo!['commission_balance'],
                  );
                });
              }
            }
          }
        } catch (e) {
          print('更新用户信息失败: $e');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).transferFailed)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).transferFailed)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // 设置窗口大小
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setSize(const Size(800, 700));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).subscriptionInfo),
        actions: [
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: NetworkImage(
                      _userInfo!['avatar_url'] ?? '',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_userInfo!['email'] ?? ''),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  AppLocalizations.of(context).yourBalance(_balance),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              PopupMenuItem(
                enabled: false,
                child: Text(
                  AppLocalizations.of(context).yourCommission(_commission),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '转换余额:',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _transferAmountController,
                              decoration: InputDecoration(
                                hintText: '单位: 元',
                                hintStyle: TextStyle(color: Colors.grey[600]),
                                filled: true,
                                fillColor: Colors.grey[200],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          Container(
                            height: 20,
                            width: 1,
                            color: Colors.grey[400],
                          ),
                          SizedBox(
                            width: 60,
                            child: TextButton(
                              onPressed: _isLoading ? null : _transferBalance,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: Theme.of(context).primaryColor,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      '提交',
                                      style: TextStyle(fontSize: 13),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('jwt_token');
                  await prefs.remove('user_info');
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.logout,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '退出登录',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Container(
                      width: 420,
                      height: 460,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_subscriptionInfo != null &&
                              _subscriptionInfo!['plan'] != null) ...[
                            Text(
                              '${AppLocalizations.of(context).currentPlan}: ${_subscriptionInfo!['plan']['name']}',
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (_shouldShowWarning())
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Text(
                                      '⚠️',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    _getExpiryText(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: _getExpiryColor()),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_subscriptionInfo != null) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  size: 16,
                                  color: Colors.green[700],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${AppLocalizations.of(context).usedUpload}: ${_formatBytes(_subscriptionInfo!['u'])}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_downward,
                                  size: 16,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${AppLocalizations.of(context).usedDownload}: ${_formatBytes(_subscriptionInfo!['d'])}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _calculateUsagePercentage(),
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _getProgressColor(
                                        _calculateUsagePercentage(),
                                      ),
                                    ),
                                    minHeight: 8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${AppLocalizations.of(context).totalTraffic}: ${_formatBytes(_userInfo!['transfer_enable'])}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '剩余: ${_getRemainingTraffic()}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_subscriptionInfo != null &&
                              _subscriptionInfo!['plan'] != null &&
                              _subscriptionInfo!['plan']['content'] !=
                                  null) ...[
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              '订阅介绍',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Html(
                                  data: _subscriptionInfo!['plan']['content'],
                                  style: {
                                    'body': Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                      fontSize: FontSize(14),
                                      color: Colors.grey[600],
                                    ),
                                    'font': Style(color: Colors.grey[600]),
                                    'p': Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                    ),
                                    'br': Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                    ),
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: NetworkImage(
                            _userInfo!['avatar_url'] ?? '',
                          ),
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _userInfo!['email'] ?? '',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () {
                        print('开始切换到节点列表页面...');
                        try {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) {
                                print('创建节点列表页面...');
                                return NodeListPage();
                              },
                            ),
                          );
                          print('页面切换完成');
                        } catch (e, stackTrace) {
                          print('页面切换失败: $e');
                          print('错误堆栈: $stackTrace');
                        }
                      },
                      icon: const Icon(Icons.list_alt),
                      label: const Text('节点列表'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
