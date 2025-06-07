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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/providers/app.dart';
import '../controller.dart';
import '../providers/network.dart' as network;
import '../providers/clash.dart' as clash;
import '../providers/state.dart';
import '../providers/config.dart';
import 'traffic_log.dart';
import 'plan.dart';
import 'order.dart';
import 'dart:async';
import 'invite.dart';

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage> {
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _subscriptionInfo;
  final TextEditingController _transferAmountController =
      TextEditingController();
  bool _isLoading = true;
  String _balance = '0.00';
  String _commission = '0.00';
  bool _hasLoadedSubscription = false;
  String? _error;
  String? _subscriptionUrl;
  late AppController _controller;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _controller = AppController(context, ref);

    // 只在初始化时设置窗口大小
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        windowManager.getSize().then((size) {
          if (size.width < 600) {
            windowManager.setSize(const Size(800, 700));
          }
        });
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载缓存的用户信息
      final cachedUserInfo = prefs.getString('user_info');
      if (cachedUserInfo != null) {
        _userInfo = jsonDecode(cachedUserInfo);
        _balance = _formatBalance(_userInfo!['balance']);
        _commission = _formatBalance(_userInfo!['commission_balance']);
      }

      // 加载缓存的订阅信息
      final cachedSubscriptionInfo = prefs.getString('subscription_info');
      if (cachedSubscriptionInfo != null) {
        _subscriptionInfo = jsonDecode(cachedSubscriptionInfo);
      }
      _subscriptionUrl = prefs.getString('subscription_url');
      _hasLoadedSubscription = true;
    } catch (e) {
      print('加载缓存数据失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
      // 加载完缓存后立即请求最新数据
      _loadUserInfo();
      _loadSubscription();
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwt_token');
    if (jwtToken == null) return;

    try {
      print('开始加载用户info信息...');
      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
        headers: {'Authorization': jwtToken, 'User-Agent': AppConfig.userAgent},
        timeout: const Duration(seconds: 8),
        retries: 3,
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

  Future<void> _loadSubscription() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) return;

      print('开始加载用户getSubscribe信息...');
      print('请求URL: ${AppConfig.baseUrl}/api/v1/user/getSubscribe');
      print(
          '请求头: Authorization: $jwtToken, User-Agent: ${AppConfig.userAgent}');

      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/getSubscribe'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
        timeout: const Duration(seconds: 8),
        retries: 3,
      );

      print('响应状态码: ${response.statusCode}');
      print('响应体: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          setState(() {
            _subscriptionInfo = data['data'];
          });

          // 检查是否需要更新订阅链接
          final newSubscribeUrl = data['data']['subscribe_url'];
          if (newSubscribeUrl != null && newSubscribeUrl != _subscriptionUrl) {
            print('需要更新订阅链接');
            print('新订阅链接: $newSubscribeUrl');
            print('旧订阅链接: $_subscriptionUrl');

            // 导入新订阅
            final success =
                await SubscriptionImporter.importFromUrl(newSubscribeUrl);
            if (success) {
              _subscriptionUrl = newSubscribeUrl;
              await prefs.setString('subscription_url', _subscriptionUrl!);
              await prefs.setString(
                  'subscription_info', jsonEncode(data['data']));
            } else {
              _error = '导入订阅失败';
            }
          } else {
            // 不需要更新订阅链接，只更新订阅信息
            await prefs.setString(
                'subscription_info', jsonEncode(data['data']));
          }
        } else {
          _error = '获取订阅信息失败';
        }
      } else {
        _error = '获取订阅信息失败: ${response.statusCode}';
      }
    } catch (e) {
      print('加载订阅信息失败: $e');
      _error = '加载订阅信息失败: $e';
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        width: MediaQuery.of(context).size.width * 0.5,
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
    if (_subscriptionInfo == null) return 0;
    final total = _subscriptionInfo!['transfer_enable'] as int;
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
    if (_subscriptionInfo == null) return '0 B';
    final total = _subscriptionInfo!['transfer_enable'] as int;
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
        await _loadUserInfo();
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

  Future<void> _toggleSystemProxy(bool value) async {
    print('切换系统代理: $value');
    try {
      // 先更新系统代理状态
      ref.read(networkSettingProvider.notifier).updateState((state) {
        return state.copyWith(systemProxy: value);
      });

      // 获取当前选中的节点
      final prefs = await SharedPreferences.getInstance();
      final selectedNode = prefs.getString('selected_node');

      if (value && selectedNode != null) {
        // 如果开启系统代理且有选中的节点，确保使用该节点
        print('使用选中的节点: $selectedNode');
        // 这里可以添加设置选中节点的逻辑
      }

      _controller.updateClashConfigDebounce();
      print('系统代理状态已更新: $value');
    } catch (e) {
      print('切换系统代理失败: $e');
    }
  }

  void _toggleTunMode(bool value) {
    print('切换TUN模式: $value');
    try {
      ref.read(clash.patchClashConfigProvider.notifier).updateState((config) {
        return config.copyWith(
          tun: config.tun.copyWith(enable: value),
        );
      });
      _controller.updateClashConfigDebounce();
      print('TUN模式状态已更新: $value');
    } catch (e) {
      print('切换TUN模式失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystemProxyEnabled = ref.watch(networkSettingProvider).systemProxy;
    final isTunEnabled = ref.watch(clash.patchClashConfigProvider).tun.enable;
    if (_userInfo == null || _subscriptionInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).subscriptionInfo),
        automaticallyImplyLeading: false,
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
                  const SizedBox(width: 8),
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
                        onPressed: () {
                          _hasLoadedSubscription = false;
                          _loadSubscription();
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 主体内容
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左侧套餐信息
                            Expanded(
                              child: Container(
                                height: 540,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_subscriptionInfo != null &&
                                        _subscriptionInfo!['plan'] != null) ...[
                                      Text(
                                        '${AppLocalizations.of(context).currentPlan}: ${_subscriptionInfo!['plan']['name']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (_shouldShowWarning())
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(right: 4),
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
                                                  ?.copyWith(
                                                      color: _getExpiryColor()),
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
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value:
                                                  _calculateUsagePercentage(),
                                              backgroundColor: Colors.grey[200],
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${AppLocalizations.of(context).totalTraffic}: ${_formatBytes(_subscriptionInfo!['transfer_enable'])}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                      color: Colors.grey[600]),
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
                                                  ?.copyWith(
                                                      color: Colors.grey[600]),
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: Html(
                                            data: _subscriptionInfo!['plan']
                                                ['content'],
                                            style: {
                                              'body': Style(
                                                margin: Margins.zero,
                                                padding: HtmlPaddings.zero,
                                                fontSize: FontSize(14),
                                                color: Colors.grey[600],
                                              ),
                                              'font': Style(
                                                  color: Colors.grey[600]),
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
                            const SizedBox(width: 16),
                            // 右侧代理设置
                            Container(
                              width: 280,
                              height: 200,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '代理设置',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: isSystemProxyEnabled,
                                        onChanged: _toggleSystemProxy,
                                        activeColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('系统代理'),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: isTunEnabled,
                                        onChanged: _toggleTunMode,
                                        activeColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text('TUN模式'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 页脚
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NodeListPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.list_alt),
                            label: const Text('节点选择'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TrafficLogPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.show_chart),
                            label: const Text('流量记录'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const PlanPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.shopping_cart),
                            label: const Text('购买套餐'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const OrderPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('订单管理'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const InvitePage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.person_add),
                            label: const Text('邀请返佣'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
