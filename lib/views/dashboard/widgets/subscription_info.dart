import 'dart:convert';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/http_client.dart' hide jwtTokenProvider;
import 'package:fl_clash/config/app_config.dart';
import 'package:fl_clash/providers/auth_provider.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionInfo extends ConsumerStatefulWidget {
  const SubscriptionInfo({super.key});

  @override
  ConsumerState<SubscriptionInfo> createState() => _SubscriptionInfoState();
}

class _SubscriptionInfoState extends ConsumerState<SubscriptionInfo> {
  late HttpClientHelper _httpHelper;
  Map<String, dynamic>? _subscriptionInfo;
  bool _isLoading = false;
  bool _hasAutoLoaded = false; // 标记是否已经自动加载过

  @override
  void initState() {
    super.initState();
    _httpHelper = HttpClientHelper(
      getToken: () async {
        return ref.read(jwtTokenProvider);
      },
      onUnauthorized: () {},
    );
    _loadCachedData();
    
    // 监听用户信息变化，避免在didChangeDependencies中触发多次调用
    ref.listenManual(userInfoProvider, (prev, next) {
      if (next != null && !_hasAutoLoaded) {
        _hasAutoLoaded = true;
        Future.microtask(() => _loadSubscriptionData());
      } else if (next == null) {
        // 用户登出时重置状态
        _hasAutoLoaded = false;
        if (mounted) {
          setState(() {
            _subscriptionInfo = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _httpHelper.close();
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final subscriptionInfoString = prefs.getString('subscription_info');
      if (subscriptionInfoString != null && mounted) {
        setState(() {
          _subscriptionInfo = jsonDecode(subscriptionInfoString);
        });
      }
    } catch (e) {
      // 忽略缓存加载错误
    }
  }

  Future<void> _loadSubscriptionData() async {
    if (!mounted || _isLoading) return;
    
    // 检查是否有有效的token
    final token = ref.read(jwtTokenProvider);
    if (token == null || token.isEmpty) return;
    
    setState(() => _isLoading = true);

    try {
      // 获取订阅信息
      final subscribeResponse = await _httpHelper.getJson(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/getSubscribe'),
      );

      if (subscribeResponse['data'] != null && mounted) {
        setState(() {
          _subscriptionInfo = subscribeResponse['data'];
        });
        
        // 缓存订阅信息
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('subscription_info', jsonEncode(subscribeResponse['data']));
        } catch (e) {
          // 忽略缓存保存错误
        }
      }
    } catch (e) {
      // 处理错误但不显示给用户，保持UI简洁
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  double _calculateUsagePercentage() {
    if (_subscriptionInfo == null) return 0;
    final total = _subscriptionInfo!['transfer_enable'] as int;
    final used = (_subscriptionInfo!['u'] as int) + (_subscriptionInfo!['d'] as int);
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
    final used = (_subscriptionInfo!['u'] as int) + (_subscriptionInfo!['d'] as int);
    return _formatBytes(total - used);
  }

  String _getExpiryText() {
    if (_subscriptionInfo == null || _subscriptionInfo!['expired_at'] == null) {
      return '该订阅永不到期';
    }

    final expiredAt = DateTime.fromMillisecondsSinceEpoch(
      _subscriptionInfo!['expired_at'] * 1000,
    );
    final now = DateTime.now();
    final difference = expiredAt.difference(now).inDays;

    if (difference <= 0) {
      return '该订阅已过期';
    }
    return '该订阅剩余$difference天到期';
  }

  Color _getExpiryColor() {
    if (_subscriptionInfo == null || _subscriptionInfo!['expired_at'] == null) {
      return Colors.grey[600]!;
    }

    final expiredAt = DateTime.fromMillisecondsSinceEpoch(
      _subscriptionInfo!['expired_at'] * 1000,
    );
    final now = DateTime.now();
    final difference = expiredAt.difference(now).inDays;

    if (difference <= 7) {
      return Colors.red;
    }
    return Colors.grey[600]!;
  }

  bool _shouldShowWarning() {
    if (_subscriptionInfo == null || _subscriptionInfo!['expired_at'] == null) {
      return false;
    }

    final expiredAt = DateTime.fromMillisecondsSinceEpoch(
      _subscriptionInfo!['expired_at'] * 1000,
    );
    final now = DateTime.now();
    final difference = expiredAt.difference(now).inDays;

    return difference <= 7;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(2),
      child: CommonCard(
        onPressed: () {}, // 保持点击和悬停效果，但不执行任何操作
        info: Info(
          label: '订阅信息',
          iconData: Icons.subscriptions,
        ),
        child: _isLoading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _subscriptionInfo == null
                ? Center(
                    child: Text(
                      '请先登录查看订阅信息',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurface.opacity60,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 套餐名称和到期时间
                        if (_subscriptionInfo!['plan'] != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _subscriptionInfo!['plan']['name'] ?? '未知套餐',
                                  style: context.textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (_shouldShowWarning())
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Text('⚠️', style: TextStyle(fontSize: 12)),
                                ),
                              Expanded(
                                child: Text(
                                  _getExpiryText(),
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: _getExpiryColor(),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // 流量使用情况
                        Row(
                          children: [
                            Icon(
                              Icons.arrow_upward,
                              size: 14,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                _formatBytes(_subscriptionInfo!['u'] ?? 0),
                                style: context.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_downward,
                              size: 14,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                _formatBytes(_subscriptionInfo!['d'] ?? 0),
                                style: context.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 进度条
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _calculateUsagePercentage(),
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getProgressColor(_calculateUsagePercentage()),
                            ),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 总流量和剩余流量
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '总计: ${_formatBytes(_subscriptionInfo!['transfer_enable'] ?? 0)}',
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '剩余: ${_getRemainingTraffic()}',
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
} 