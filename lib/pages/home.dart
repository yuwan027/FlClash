import 'dart:io';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/http_client.dart';
import 'package:fl_clash/config/app_config.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
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
          final days = difference.inDays;
          
          print('上次更新时间: $lastUpdate');
          print('距离上次更新已过: $days 天');
          
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

    // 使用 Future.microtask 延迟加载数据
    Future.microtask(() => loadInitialData());

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
        
        if (mounted) {
          setState(() {
            _userInfo = userInfoResponse['data'];
            _balance = _formatBalance(_userInfo!['balance']);
            _commission = _formatBalance(_userInfo!['commission_balance']);
          });
          print('用户信息更新完成');
        }
      }

      // 获取订阅信息
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

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_subscribe_url', newSubscribeUrl);

        // 读取本地所有 profiles
        final profiles = ref.read(profilesProvider);
        // 查找当前订阅链接对应的 Profile
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
  // 已有配置，弹窗询问是否更新
  final shouldUpdate = await globalState.showMessage(
    title: appLocalizations.tip,
    message: TextSpan(
      text: '检测到已存在相同订阅配置，是否更新？',
    ),
    confirmText: '是',
    cancelable: true,
  );

if (shouldUpdate == true) {
  await _updateProfileWithRetry(currentProfile);  // 重新拉取更新
} else {
  print('用户取消更新，使用当前配置');
  await globalState.appController.initCore();
 // 即使不更新也刷新，让代理按钮显示出来
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
        setState(() => _isLoading = false);
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

class CommonNavigationBar extends ConsumerWidget {
  final ViewMode viewMode;
  final List<NavigationItem> navigationItems;
  final int currentIndex;

  const CommonNavigationBar({
    super.key,
    required this.viewMode,
    required this.navigationItems,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context, ref) {
    if (viewMode == ViewMode.mobile) {
      return NavigationBarTheme(
        data: _NavigationBarDefaultsM3(context),
        child: NavigationBar(
          destinations: navigationItems
              .map(
                (e) => NavigationDestination(
                  icon: e.icon,
                  label: Intl.message(e.label.name),
                ),
              )
              .toList(),
          onDestinationSelected: (index) {
            globalState.appController.toPage(navigationItems[index].label);
          },
          selectedIndex: currentIndex,
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
                    destinations: navigationItems
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
                          .toPage(navigationItems[index].label);
                    },
                    extended: false,
                    selectedIndex: currentIndex,
                    labelType: showLabel
                        ? NavigationRailLabelType.all
                        : NavigationRailLabelType.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          IconButton(
            onPressed: () {
              ref.read(appSettingProvider.notifier).updateState(
                    (state) => state.copyWith(
                      showLabel: !state.showLabel,
                    ),
                  );
            },
            icon: const Icon(Icons.menu),
          ),
          const SizedBox(
            height: 16,
          ),
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
