import 'dart:io';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/http_client.dart' hide jwtTokenProvider;
import 'package:fl_clash/config/app_config.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/auth_provider.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:fl_clash/views/profiles/add_profile.dart';
import 'traffic_log_page.dart';

typedef OnSelected = void Function(int index);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeBackScope(
      child: Consumer(
        builder: (_, ref, child) {
          final state = ref.watch(homeStateProvider);
          final viewMode = state.viewMode;
          final navigationItems = state.navigationItems;
          final pageLabel = state.pageLabel;
          final index = navigationItems.lastIndexWhere(
            (element) => element.label == pageLabel,
          );
          final currentIndex = index == -1 ? 0 : index;
          final navigationBar = CommonNavigationBar(
            viewMode: viewMode,
            navigationItems: navigationItems,
            currentIndex: currentIndex,
            onClearCache: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                
                // 恢复页面布局和应用设置至默认
                ref.read(appSettingProvider.notifier).updateState(
                  (state) => state.copyWith(
                    showLabel: false, // 恢复showLabel至默认值
                    isAnimateToPage: true, // 恢复页面动画至默认值
                    openLogs: false, // 恢复日志显示至默认值
                    dashboardWidgets: defaultDashboardWidgets, // 重置仪表板小部件至默认
                    // 可以添加其他需要重置的布局相关设置
                  ),
                );
                
                // 重置当前页面至默认页面
                ref.read(currentPageLabelProvider.notifier).state = PageLabel.dashboard;
                
                // 显示成功提示
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('缓存已清除，页面布局已恢复默认'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                // 显示错误提示
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('清除缓存失败：$e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          );
          final bottomNavigationBar =
              viewMode == ViewMode.mobile ? navigationBar : null;
          final sideNavigationBar =
              viewMode != ViewMode.mobile ? navigationBar : null;
          return CommonScaffold(
            key: globalState.homeScaffoldKey,
            title: Intl.message(
              pageLabel.name,
            ),
            sideNavigationBar: sideNavigationBar,
            body: child!,
            bottomNavigationBar: bottomNavigationBar,
            actions: [
              // 编辑布局按钮（只在dashboard页面显示）
              Consumer(
                builder: (context, ref, child) {
                  final pageLabel = ref.watch(currentPageLabelProvider);
                  if (pageLabel != PageLabel.dashboard) return const SizedBox.shrink();
                  
                  return IconButton(
                    onPressed: () {
                      ref.read(appSettingProvider.notifier).updateState(
                            (state) => state.copyWith(
                              showLabel: !state.showLabel,
                            ),
                          );
                    },
                    icon: const Icon(Icons.edit),
                  );
                },
              ),
            ],
          );
        },
        child: _HomePageView(),
      ),
    );
  }
}

class _HomePageView extends ConsumerStatefulWidget {
  const _HomePageView();

  @override
  ConsumerState createState() => _HomePageViewState();
}

class _HomePageViewState extends ConsumerState<_HomePageView> {
  late PageController _pageController;
  late HttpClientHelper _httpHelper;
  bool _isLoading = false;
  
  // 用户信息相关状态
  Map<String, dynamic>? _userInfo;
  String? _balance;
  String? _commission;
  
  // 订阅信息相关状态
  Map<String, dynamic>? _subscriptionInfo;
  String? _subscriptionUrl;

  Future<void> _importOrUpdateProfile(String url) async {
    print('开始导入或更新订阅: $url');
    final profiles = ref.read(profilesProvider);
    print('当前已有配置数量: ${profiles.length}');
    
    final existProfile = profiles.firstWhereOrNull((p) => p.url == url);
    print('是否找到已存在的配置: ${existProfile != null}');

    try {
      if (existProfile != null) {
        print('找到已存在的配置: ${existProfile.label ?? existProfile.id}');
        
        // 检查上次更新时间
        final lastUpdate = existProfile.lastUpdateDate;
        if (lastUpdate != null) {
          final now = DateTime.now();
          final difference = now.difference(lastUpdate);
          
          print('上次更新时间: $lastUpdate');
          print('距离上次更新已过: ${_formatTimeDifference(difference)}');
          
          // 询问用户是否更新
          if (!mounted) return;
          
          final shouldUpdate = await globalState.showMessage(
            title: appLocalizations.tip,
            message: TextSpan(
              text: '发现新的订阅链接，是否更新？',
            ),
          );
          
          if (shouldUpdate != true) {
            print('用户取消更新');
            return;
          }
        }
        
        print('开始更新已存在的配置');
        await _updateSingleProfile(existProfile);
      } else {
        print('开始创建新配置');
        final profile = await Profile.normal(url: url).update();
        print('配置创建成功: ${profile.label ?? profile.id}');
        await globalState.appController.addProfile(profile);
        print('配置添加成功');
        if (mounted) {
          context.showNotifier(appLocalizations.importSuccess);
        }
      }
    } catch (e) {
      print('导入/更新失败: $e');
      if (mounted) {
        context.showNotifier(e.toString());
      }
    }
  }

  Future<void> _updateSingleProfile(Profile profile) async {
    print('开始更新单个配置: ${profile.label ?? profile.id}');
    ref.read(profilesProvider.notifier).setProfile(profile.copyWith(isUpdating: true));
    try {
      print('调用 appController.updateProfile');
      await globalState.appController.updateProfile(profile);
      print('更新成功');
      if (mounted) {
        context.showNotifier(appLocalizations.updateSuccess);
      }
    } catch (e) {
      print('更新失败: $e');
      ref.read(profilesProvider.notifier).setProfile(profile.copyWith(isUpdating: false));
      if (mounted) {
        context.showNotifier(e.toString());
      }
    }
  }

  void _handleShowAddExtendPage({String? importUrl}) {
    print('准备打开添加配置页面，importUrl: $importUrl');
    if (!mounted) {
      print('组件未挂载，无法打开页面');
      return;
    }

    try {
      showExtend(
        context,
        builder: (_, type) {
          print('构建添加配置页面，type: $type');
          return AdaptiveSheetScaffold(
            type: type,
            body: AddProfileView(
              context: context,
              importUrl: importUrl,
            ),
            title: "${appLocalizations.add}${appLocalizations.profile}",
          );
        },
      );
      print('添加配置页面已打开');
    } catch (e) {
      print('打开添加配置页面失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开添加配置页面失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _pageIndex,
      keepPage: true,
    );

    _httpHelper = HttpClientHelper(
      getToken: () async {
        return ref.read(jwtTokenProvider);
      },
      onUnauthorized: () {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      },
    );

    // 检查是否有token，如果有且未加载过数据，则加载
    Future.microtask(() async {
      final token = ref.read(jwtTokenProvider);
      final hasLoadedData = ref.read(dataLoadedProvider);
      if (token != null && !hasLoadedData) {
        await loadInitialData();
      }
    });

    // 检查是否需要更新订阅链接
    if (_subscriptionUrl != null) {
      _importOrUpdateProfile(_subscriptionUrl!);
    }

    ref.listenManual(currentPageLabelProvider, (prev, next) {
      if (prev != next) {
        _toPage(next);
      }
    });
    ref.listenManual(currentNavigationsStateProvider, (prev, next) {
      if (prev?.value.length != next.value.length) {
        _updatePageController();
      }
    });
  }

  String _formatTimeDifference(Duration difference) {
    final days = difference.inDays;
    final hours = difference.inHours;
    final minutes = difference.inMinutes;
    final seconds = difference.inSeconds;
    
    // 优先显示最大的时间单位，只要大于等于1就显示
    if (days >= 1) {
      return '$days天';
    } else if (hours >= 1) {
      return '$hours小时';
    } else if (minutes >= 1) {
      return '$minutes分钟';
    } else {
      return '$seconds秒';
    }
  }

  /// 检查首次登录是否需要提示开启开机自启动
  Future<void> _checkFirstLoginAutoStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasShownAutoStartupDialog = prefs.getBool('has_shown_auto_startup_dialog') ?? false;
      
      // 如果已经显示过开机自启动对话框，则跳过
      if (hasShownAutoStartupDialog) {
        print('已显示过开机自启动对话框，跳过提示');
        return;
      }

      // 检查当前是否已经开启了开机自启动
      final currentAutoLaunch = ref.read(appSettingProvider).autoLaunch;
      if (currentAutoLaunch) {
        print('已开启开机自启动，标记为已显示过对话框');
        await prefs.setBool('has_shown_auto_startup_dialog', true);
        return;
      }

      // 显示开机自启动提示对话框
      if (mounted) {
        final shouldEnable = await globalState.showMessage(
          title: '开机自启动',
          message: const TextSpan(
            text: '为了更好的使用体验，建议开启开机自启动功能。\n\n'
                  '开启后应用将在系统启动时自动运行，您可以随时在设置中关闭此功能。',
          ),
          confirmText: '开启',
          cancelable: true,
        );

        if (shouldEnable == true) {
          // 用户选择开启，更新设置
          ref.read(appSettingProvider.notifier).updateState(
            (state) => state.copyWith(autoLaunch: true),
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('开机自启动已开启'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }

      // 标记为已显示过对话框
      await prefs.setBool('has_shown_auto_startup_dialog', true);
      print('首次登录开机自启动提示完成');
    } catch (e) {
      print('检查首次登录开机自启动失败: $e');
    }
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

// 订阅缓存
String? _cachedSubscriptionUrl;

  Future<void> loadInitialData() async {
    if (!mounted) return;
    
    // 如果已经加载过数据，则不重复加载
    final hasLoadedData = ref.read(dataLoadedProvider);
    if (hasLoadedData) {
      print('数据已加载过，跳过重复加载');
      return;
    }

    // 首次登录检查是否需要提示开启开机自启动
    await _checkFirstLoginAutoStartup();

    setState(() => _isLoading = true);

    try {
      // 获取用户信息
      print('开始获取用户信息');
      final userInfoResponse = await _httpHelper.getJson(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
      );
      print('获取用户信息响应: ${userInfoResponse != null}');

      if (userInfoResponse?['data'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_info', jsonEncode(userInfoResponse['data']));
        
        // 更新用户信息到provider
        ref.read(userInfoProvider.notifier).state = userInfoResponse['data'];
        
        if (mounted) {
          setState(() {
            _userInfo = userInfoResponse['data'];
            _balance = _formatBalance(_userInfo!['balance']);
            _commission = _formatBalance(_userInfo!['commission_balance']);
          });
          print('用户信息更新完成');
        }
      }

      // 先检查本地配置，判断是否需要更新
      final profiles = ref.read(profilesProvider);
      final prefs = await SharedPreferences.getInstance();
      final lastSubscribeUrl = prefs.getString('last_subscribe_url');
      
      // 如果有上次的订阅链接，先检查是否需要更新
      Profile? existingProfile;
      bool shouldSkipSubscriptionCheck = false;
      
      if (lastSubscribeUrl != null && lastSubscribeUrl.isNotEmpty) {
        existingProfile = profiles.firstWhereOrNull((p) => p.url == lastSubscribeUrl);
        
        if (existingProfile != null) {
          final lastUpdate = existingProfile.lastUpdateDate;
          final hasEverUpdated = prefs.getBool('has_ever_updated_subscription') ?? false;
          
          // 如果有更新记录且距离上次更新不足30分钟，跳过订阅检查
          if (hasEverUpdated && lastUpdate != null) {
            final now = DateTime.now();
            final difference = now.difference(lastUpdate);
            final minutesSinceUpdate = difference.inMinutes;
            
            if (minutesSinceUpdate < 30) {
              print('距离上次更新不足30分钟，跳过订阅检查');
              shouldSkipSubscriptionCheck = true;
              await globalState.appController.initCore();
            }
          }
        }
      }
      
      // 如果不需要跳过，才获取订阅信息
      if (!shouldSkipSubscriptionCheck) {
        print('开始获取订阅信息');
        final subscribeResponse = await _httpHelper.getJson(
          Uri.parse('${AppConfig.baseUrl}/api/v1/user/getSubscribe'),
        );
        print('获取订阅信息响应: ${subscribeResponse != null}');

        if (subscribeResponse?['data'] != null) {
          if (!mounted) return;

          setState(() {
            _subscriptionInfo = subscribeResponse['data'];
          });
          print('订阅信息更新完成');

          final newSubscribeUrl = subscribeResponse['data']['subscribe_url'] as String? ?? '';

          if (newSubscribeUrl.isEmpty) {
            print('订阅链接为空，无需处理');
            return;
          }

          await prefs.setString('last_subscribe_url', newSubscribeUrl);

          // 重新查找配置（可能订阅链接已变更）
          Profile? currentProfile = profiles.firstWhereOrNull((p) => p.url == newSubscribeUrl);

          if (currentProfile == null) {
            print('未找到对应的配置，创建新配置');
            currentProfile = Profile.normal(label: '默认订阅', url: newSubscribeUrl);
            await globalState.appController.addProfile(currentProfile);
            print('新配置已添加到状态中');

            // 新配置，强制更新
            print('开始更新订阅配置（新配置）');
            await _updateProfileWithRetry(currentProfile);
          } else {
            // 已有配置，第一次登录时强制更新
            final lastUpdate = currentProfile.lastUpdateDate;
            final hasEverUpdated = prefs.getBool('has_ever_updated_subscription') ?? false;
            
            bool shouldAutoUpdate = false;
            
            // 如果从未更新过（第一次登录），强制更新
            if (!hasEverUpdated) {
              shouldAutoUpdate = true;
              print('第一次登录，强制更新订阅');
              await prefs.setBool('has_ever_updated_subscription', true);
            } else if (lastUpdate != null) {
              final now = DateTime.now();
              final difference = now.difference(lastUpdate);
              final minutesSinceUpdate = difference.inMinutes;
              
              print('距离上次更新已过: ${_formatTimeDifference(difference)}');
              
              // 超过3小时自动更新
              if (minutesSinceUpdate >= 180) { // 180分钟 = 3小时
                shouldAutoUpdate = true;
                print('超过3小时未更新，自动更新订阅');
              }
            } else {
              // 没有更新记录，自动更新
              shouldAutoUpdate = true;
              print('没有更新记录，自动更新订阅');
            }
            
            if (shouldAutoUpdate) {
              // 直接更新，不询问用户
              await _updateProfileWithRetry(currentProfile);
            } else {
              // 30分钟到3小时之间，询问用户是否更新
              final now = DateTime.now();
              final difference = now.difference(lastUpdate!);
              final timeMessage = '距离上次更新已过: ${_formatTimeDifference(difference)}';
              
              final shouldUpdate = await globalState.showMessage(
                title: appLocalizations.tip,
                message: TextSpan(
                  text: '$timeMessage，是否更新？',
                ),
                confirmText: '是',
                cancelable: true,
              );

              if (shouldUpdate == true) {
                await _updateProfileWithRetry(currentProfile);
              } else {
                print('用户取消更新，使用当前配置');
                await globalState.appController.initCore();
                // 即使不更新也刷新，让代理按钮显示出来
              }
            }
          }
        }
      }
    } catch (e) {
      print('加载数据失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载数据失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // 标记数据已加载，防止重复调用
        ref.read(dataLoadedProvider.notifier).state = true;
      }
    }
  }

  Future<void> _updateProfileWithRetry(Profile profile) async {
    while (true) {
      try {
        print('当前配置: ${globalState.config.currentProfile}');
        // 显示正在更新提示
        if (mounted) {
          context.showNotifier(appLocalizations.updating);
        }

        // 直接使用 appController 更新配置，避免重复更新
        await globalState.appController.updateProfile(profile);
        print('配置更新成功');
        print('当前配置: ${globalState.config.currentProfile}');
        if (mounted) {
          context.showNotifier(appLocalizations.updateSuccess);
        }
        break; // 更新成功，退出循环
      } catch (e) {
        print('更新订阅配置失败: $e');
        if (!mounted) return;

        // 询问用户是否重试
        final shouldRetry = await globalState.showMessage(
          title: appLocalizations.tip,
          message: TextSpan(
            text: '更新失败：$e\n是否重试？',
          ),
        );

        if (shouldRetry != true) {
          print('用户取消重试');
          break; // 用户取消重试，退出循环
        }
        print('用户选择重试，开始新的更新尝试');
      }
    }
  }

  int get _pageIndex {
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    return navigationItems.indexWhere(
      (item) => item.label == globalState.appState.pageLabel,
    );
  }

  _toPage(PageLabel pageLabel, [bool ignoreAnimateTo = false]) async {
    if (!mounted) {
      return;
    }
    final navigationItems = ref.read(currentNavigationsStateProvider).value;
    final index = navigationItems.indexWhere((item) => item.label == pageLabel);
    if (index == -1) {
      return;
    }
    final isAnimateToPage = ref.read(appSettingProvider).isAnimateToPage;
    final isMobile = ref.read(isMobileViewProvider);
    if (isAnimateToPage && isMobile && !ignoreAnimateTo) {
      await _pageController.animateToPage(
        index,
        duration: kTabScrollDuration,
        curve: Curves.easeOut,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  _updatePageController() {
    final pageLabel = globalState.appState.pageLabel;
    _toPage(pageLabel, true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _httpHelper.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigationItems = ref.watch(currentNavigationsStateProvider).value;
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: navigationItems.length,
      // onPageChanged: (index) {
      //   debouncer.call(DebounceTag.pageChange, () {
      //     WidgetsBinding.instance.addPostFrameCallback((_) {
      //       if (_pageIndex != index) {
      //         final pageLabel = navigationItems[index].label;
      //         _toPage(pageLabel, true);
      //       }
      //     });
      //   });
      // },
      itemBuilder: (_, index) {
        final navigationItem = navigationItems[index];
        return KeepScope(
          keep: navigationItem.keep,
          key: Key(navigationItem.label.name),
          child: navigationItem.view,
        );
      },
    );
  }

}

class CommonNavigationBar extends ConsumerStatefulWidget {
  final ViewMode viewMode;
  final List<NavigationItem> navigationItems;
  final int currentIndex;
  final VoidCallback? onClearCache;

  const CommonNavigationBar({
    super.key,
    required this.viewMode,
    required this.navigationItems,
    required this.currentIndex,
    this.onClearCache,
  });

  @override
  ConsumerState<CommonNavigationBar> createState() => _CommonNavigationBarState();
}

class _CommonNavigationBarState extends ConsumerState<CommonNavigationBar> {

  @override
  Widget build(BuildContext context) {
    if (widget.viewMode == ViewMode.mobile) {
      return NavigationBarTheme(
        data: _NavigationBarDefaultsM3(context),
        child: NavigationBar(
          destinations: widget.navigationItems
              .map(
                (e) => NavigationDestination(
                  icon: e.icon,
                  label: Intl.message(e.label.name),
                ),
              )
              .toList(),
          onDestinationSelected: (index) {
            globalState.appController.toPage(widget.navigationItems[index].label);
          },
          selectedIndex: widget.currentIndex,
        ),
      );
    }
    
    final showLabel = ref.watch(appSettingProvider).showLabel;
    
    return Material(
      color: context.colorScheme.surfaceContainer,
      child: Column(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: HiddenBarScrollBehavior(),
              child: SingleChildScrollView(
                child: IntrinsicHeight(
                  child: NavigationRail(
                    backgroundColor: context.colorScheme.surfaceContainer,
                    selectedIconTheme: IconThemeData(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    unselectedIconTheme: IconThemeData(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    selectedLabelTextStyle:
                        context.textTheme.labelLarge!.copyWith(
                      color: context.colorScheme.onSurface,
                    ),
                    unselectedLabelTextStyle:
                        context.textTheme.labelLarge!.copyWith(
                      color: context.colorScheme.onSurface,
                    ),
                    destinations: widget.navigationItems
                        .map(
                          (e) => NavigationRailDestination(
                            icon: e.icon,
                            label: Text(
                              Intl.message(e.label.name),
                            ),
                          ),
                        )
                        .toList(),
                    onDestinationSelected: (index) {
                      globalState.appController
                          .toPage(widget.navigationItems[index].label);
                    },
                    extended: false,
                    selectedIndex: widget.currentIndex,
                    labelType: NavigationRailLabelType.all,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 用户头像下拉菜单
          Consumer(
            builder: (context, ref, child) {
              final userInfo = ref.watch(userInfoProvider);
              if (userInfo == null) {
                return const SizedBox.shrink(); // 没有用户信息时不显示
              }
              
              return PopupMenuButton<String>(
                position: PopupMenuPosition.over,
                offset: const Offset(0, -8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: userInfo['avatar_url'] != null && 
                                    userInfo['avatar_url'].toString().isNotEmpty
                        ? NetworkImage(
                            userInfo['avatar_url'],
                            // 强制使用缓存，避免重复网络请求
                          )
                        : null,
                    onBackgroundImageError: userInfo['avatar_url'] != null 
                        ? (exception, stackTrace) {
                            print('头像加载失败: $exception');
                          }
                        : null,
                    child: userInfo['avatar_url'] == null || 
                           userInfo['avatar_url'].toString().isEmpty
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      '余额: ${(userInfo['balance'] / 100).toStringAsFixed(2)} 元',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      '佣金: ${(userInfo['commission_balance'] / 100).toStringAsFixed(2)} 元',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    enabled: false,
                    child: _UserBalanceTransferWidget(),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    onTap: () async {
                      Future.microtask(() async {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          // 只清理JWT token，保留邮箱、密码和头像URL缓存
                          await prefs.remove('jwt_token');
                          
                          // 清理provider状态
                          ref.read(jwtTokenProvider.notifier).state = null;
                          ref.read(dataLoadedProvider.notifier).state = false;
                          
                          if (mounted) {
                            Navigator.pushReplacementNamed(context, '/login');
                          }
                        } catch (e) {
                          print('退出登录失败: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('退出登录失败：$e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      });
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
              );
            },
          ),
          const SizedBox(height: 8),
          IconButton(
            onPressed: widget.onClearCache,
            icon: const Icon(Icons.clear_all),
            tooltip: '清除缓存',
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _NavigationBarDefaultsM3 extends NavigationBarThemeData {
  _NavigationBarDefaultsM3(this.context)
      : super(
          height: 80.0,
          elevation: 3.0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        );

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;
  late final TextTheme _textTheme = Theme.of(context).textTheme;

  @override
  Color? get backgroundColor => _colors.surfaceContainer;

  @override
  Color? get shadowColor => Colors.transparent;

  @override
  Color? get surfaceTintColor => Colors.transparent;

  @override
  WidgetStateProperty<IconThemeData?>? get iconTheme {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return IconThemeData(
        size: 24.0,
        color: states.contains(WidgetState.disabled)
            ? _colors.onSurfaceVariant.opacity38
            : states.contains(WidgetState.selected)
                ? _colors.onSecondaryContainer
                : _colors.onSurfaceVariant,
      );
    });
  }

  @override
  Color? get indicatorColor => _colors.secondaryContainer;

  @override
  ShapeBorder? get indicatorShape => const StadiumBorder();

  @override
  WidgetStateProperty<TextStyle?>? get labelTextStyle {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      final TextStyle style = _textTheme.labelMedium!;
      return style.apply(
          overflow: TextOverflow.ellipsis,
          color: states.contains(WidgetState.disabled)
              ? _colors.onSurfaceVariant.opacity38
              : states.contains(WidgetState.selected)
                  ? _colors.onSurface
                  : _colors.onSurfaceVariant);
    });
  }
}

// 用户余额转换组件
class _UserBalanceTransferWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<_UserBalanceTransferWidget> createState() => _UserBalanceTransferWidgetState();
}

class _UserBalanceTransferWidgetState extends ConsumerState<_UserBalanceTransferWidget> {
  final _transferAmountController = TextEditingController();
  bool _isLoading = false;
  late HttpClientHelper _httpHelper;

  @override
  void initState() {
    super.initState();
    _httpHelper = HttpClientHelper(
      getToken: () async {
        return ref.read(jwtTokenProvider);
      },
      onUnauthorized: () {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      },
    );
  }

  @override
  void dispose() {
    _transferAmountController.dispose();
    _httpHelper.close();
    super.dispose();
  }

  Future<void> _transferBalance() async {
    final amount = double.tryParse(_transferAmountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 调用API，如果HTTP状态码为200，postJson会正常返回，否则会抛出异常
      await _httpHelper.postJson(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/transfer'),
        {
          'transfer_amount': (amount * 100).toInt(),
        },
      );

      // 能执行到这里说明HTTP状态码为200，转换成功
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('转换成功')),
      );
      _transferAmountController.clear();

      // 重新加载用户信息
      await _loadUserInfo();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('转换失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      final userInfoResponse = await _httpHelper.getJson(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
      );

      if (userInfoResponse?['data'] != null) {
        ref.read(userInfoProvider.notifier).state = userInfoResponse['data'];
      }
    } catch (e) {
      print('加载用户信息失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '转换余额:',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _transferAmountController,
                decoration: const InputDecoration(
                  hintText: '输入转换金额(元)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _transferBalance,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                minimumSize: const Size(80, 36),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('转换'),
            ),
          ],
        ),
      ],
    );
  }
}

class HomeBackScope extends StatelessWidget {
  final Widget child;

  const HomeBackScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return CommonPopScope(
        onPop: () async {
          final canPop = Navigator.canPop(context);
          if (canPop) {
            Navigator.pop(context);
          } else {
            await globalState.appController.handleBackOrExit();
          }
          return false;
        },
        child: child,
      );
    }
    return child;
  }
}
