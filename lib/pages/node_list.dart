import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_html/flutter_html.dart';
import 'dart:ui';
import '../l10n/l10n.dart';
import 'login.dart';
import 'subscription.dart';
import '../utils/subscription_importer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/providers/app.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';
import 'package:characters/characters.dart';
import 'package:flag/flag.dart';
import 'package:flutter/rendering.dart';

enum ProxyMode {
  global,
  rule,
}

class NodeListPage extends ConsumerStatefulWidget {
  @override
  ConsumerState<NodeListPage> createState() => _NodeListPageState();
}

class _NodeListPageState extends ConsumerState<NodeListPage> {
  bool _isLoading = true;
  ProxyMode _selectedMode = ProxyMode.rule;
  String? _selectedNode;
  List<String> _nodes = [];
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final nodesStr = prefs.getString('nodes');
      if (nodesStr != null) {
        final List<dynamic> decodedNodes = jsonDecode(nodesStr);
        setState(() {
          _nodes = decodedNodes.cast<String>();
        });
        print('加载到的节点数量: ${_nodes.length}');
        if (_nodes.isNotEmpty) {
          print('第一个节点示例: ${_nodes[0]}');
        }
      }

      final savedMode = prefs.getString('proxy_mode');
      if (savedMode != null) {
        setState(() {
          _selectedMode = ProxyMode.values.firstWhere(
            (mode) => mode.toString() == savedMode,
            orElse: () => ProxyMode.rule,
          );
        });
      }

      final savedNode = prefs.getString('selected_node');
      if (savedNode != null) {
        setState(() {
          _selectedNode = savedNode;
        });
      }
    } catch (e) {
      print('加载数据失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _decodeBase64(String encoded) {
    try {
      // 添加必要的填充
      String padded = encoded;
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      return utf8.decode(base64Decode(padded));
    } catch (e) {
      print('Base64解码失败: $e');
      return encoded;
    }
  }

  String _getNodeName(String node) {
    try {
      // 解析节点字符串，格式如：ss://xxx@xxx:xxx#%F0%9F%87%BA%F0%9F%87%B8%20US2
      final parts = node.split('#');
      if (parts.length > 1) {
        // 获取最后一个#后面的内容
        final encodedName = parts.last;
        // URL解码
        final decodedName = Uri.decodeComponent(encodedName);
        // 分割空格，获取节点名称
        final nameParts = decodedName.split(' ');
        if (nameParts.length > 1) {
          // 返回除国旗外的部分，并处理特殊字符
          final name = nameParts.sublist(1).join(' ');
          // 处理重复的名称
          if (name.contains('⌛到期:')) {
            return name.replaceAll('⌛到期:', '到期:');
          }
          return name;
        }
        return decodedName;
      }
      return node;
    } catch (e) {
      print('解析节点名称失败: $e');
      return node;
    }
  }

  String _getNodeFlag(String node) {
    try {
      // 解析节点字符串，格式如：ss://xxx@xxx:xxx#%F0%9F%87%BA%F0%9F%87%B8%20US2
      final parts = node.split('#');
      if (parts.length > 1) {
        // 获取最后一个#后面的内容
        final encodedName = parts.last;
        // URL解码
        final decodedName = Uri.decodeComponent(encodedName);
        // 分割空格，获取国家代码
        final nameParts = decodedName.split(' ');
        if (nameParts.isNotEmpty) {
          // 从节点名称中提取国家代码
          final countryCode = _extractCountryCode(nameParts[0]);
          if (countryCode != null) {
            return countryCode;
          }
        }
      }
      return 'UN'; // 默认使用联合国图标
    } catch (e) {
      print('解析节点国旗失败: $e');
      return 'UN';
    }
  }

  String? _extractCountryCode(String flagEmoji) {
    // 将emoji转换为国家代码
    final Map<String, String> emojiToCountryCode = {
      '🇦🇫': 'AF', // 阿富汗
      '🇦🇱': 'AL', // 阿尔巴尼亚
      '🇩🇿': 'DZ', // 阿尔及利亚
      '🇦🇩': 'AD', // 安道尔
      '🇦🇴': 'AO', // 安哥拉
      '🇦🇬': 'AG', // 安提瓜和巴布达
      '🇦🇷': 'AR', // 阿根廷
      '🇦🇲': 'AM', // 亚美尼亚
      '🇦🇺': 'AU', // 澳大利亚
      '🇦🇹': 'AT', // 奥地利
      '🇦🇿': 'AZ', // 阿塞拜疆
      '🇧🇸': 'BS', // 巴哈马
      '🇧🇭': 'BH', // 巴林
      '🇧🇩': 'BD', // 孟加拉国
      '🇧🇧': 'BB', // 巴巴多斯
      '🇧🇾': 'BY', // 白俄罗斯
      '🇧🇪': 'BE', // 比利时
      '🇧🇿': 'BZ', // 伯利兹
      '🇧🇯': 'BJ', // 贝宁
      '🇧🇹': 'BT', // 不丹
      '🇧🇴': 'BO', // 玻利维亚
      '🇧🇦': 'BA', // 波斯尼亚和黑塞哥维那
      '🇧🇼': 'BW', // 博茨瓦纳
      '🇧🇷': 'BR', // 巴西
      '🇧🇳': 'BN', // 文莱
      '🇧🇬': 'BG', // 保加利亚
      '🇧🇫': 'BF', // 布基纳法索
      '🇧🇮': 'BI', // 布隆迪
      '🇰🇭': 'KH', // 柬埔寨
      '🇨🇲': 'CM', // 喀麦隆
      '🇨🇦': 'CA', // 加拿大
      '🇨🇻': 'CV', // 佛得角
      '🇨🇫': 'CF', // 中非共和国
      '🇹🇩': 'TD', // 乍得
      '🇨🇱': 'CL', // 智利
      '🇨🇳': 'CN', // 中国
      '🇨🇴': 'CO', // 哥伦比亚
      '🇰🇲': 'KM', // 科摩罗
      '🇨🇬': 'CG', // 刚果
      '🇨🇩': 'CD', // 刚果民主共和国
      '🇨🇷': 'CR', // 哥斯达黎加
      '🇨🇮': 'CI', // 科特迪瓦
      '🇭🇷': 'HR', // 克罗地亚
      '🇨🇺': 'CU', // 古巴
      '🇨🇾': 'CY', // 塞浦路斯
      '🇨🇿': 'CZ', // 捷克
      '🇩🇰': 'DK', // 丹麦
      '🇩🇯': 'DJ', // 吉布提
      '🇩🇲': 'DM', // 多米尼克
      '🇩🇴': 'DO', // 多米尼加共和国
      '🇪🇨': 'EC', // 厄瓜多尔
      '🇪🇬': 'EG', // 埃及
      '🇸🇻': 'SV', // 萨尔瓦多
      '🇬🇶': 'GQ', // 赤道几内亚
      '🇪🇷': 'ER', // 厄立特里亚
      '🇪🇪': 'EE', // 爱沙尼亚
      '🇪🇹': 'ET', // 埃塞俄比亚
      '🇫🇯': 'FJ', // 斐济
      '🇫🇮': 'FI', // 芬兰
      '🇫🇷': 'FR', // 法国
      '🇬🇦': 'GA', // 加蓬
      '🇬🇲': 'GM', // 冈比亚
      '🇬🇪': 'GE', // 格鲁吉亚
      '🇩🇪': 'DE', // 德国
      '🇬🇭': 'GH', // 加纳
      '🇬🇷': 'GR', // 希腊
      '🇬🇩': 'GD', // 格林纳达
      '🇬🇹': 'GT', // 危地马拉
      '🇬🇳': 'GN', // 几内亚
      '🇬🇼': 'GW', // 几内亚比绍
      '🇬🇾': 'GY', // 圭亚那
      '🇭🇹': 'HT', // 海地
      '🇭🇳': 'HN', // 洪都拉斯
      '🇭🇰': 'HK', // 香港
      '🇭🇺': 'HU', // 匈牙利
      '🇮🇸': 'IS', // 冰岛
      '🇮🇳': 'IN', // 印度
      '🇮🇩': 'ID', // 印度尼西亚
      '🇮🇷': 'IR', // 伊朗
      '🇮🇶': 'IQ', // 伊拉克
      '🇮🇪': 'IE', // 爱尔兰
      '🇮🇱': 'IL', // 以色列
      '🇮🇹': 'IT', // 意大利
      '🇯🇲': 'JM', // 牙买加
      '🇯🇵': 'JP', // 日本
      '🇯🇴': 'JO', // 约旦
      '🇰🇿': 'KZ', // 哈萨克斯坦
      '🇰🇪': 'KE', // 肯尼亚
      '🇰🇮': 'KI', // 基里巴斯
      '🇰🇵': 'KP', // 朝鲜
      '🇰🇷': 'KR', // 韩国
      '🇰🇼': 'KW', // 科威特
      '🇰🇬': 'KG', // 吉尔吉斯斯坦
      '🇱🇦': 'LA', // 老挝
      '🇱🇻': 'LV', // 拉脱维亚
      '🇱🇧': 'LB', // 黎巴嫩
      '🇱🇸': 'LS', // 莱索托
      '🇱🇷': 'LR', // 利比里亚
      '🇱🇾': 'LY', // 利比亚
      '🇱🇮': 'LI', // 列支敦士登
      '🇱🇹': 'LT', // 立陶宛
      '🇱🇺': 'LU', // 卢森堡
      '🇲🇴': 'MO', // 澳门
      '🇲🇰': 'MK', // 北马其顿
      '🇲🇬': 'MG', // 马达加斯加
      '🇲🇼': 'MW', // 马拉维
      '🇲🇾': 'MY', // 马来西亚
      '🇲🇻': 'MV', // 马尔代夫
      '🇲🇱': 'ML', // 马里
      '🇲🇹': 'MT', // 马耳他
      '🇲🇭': 'MH', // 马绍尔群岛
      '🇲🇷': 'MR', // 毛里塔尼亚
      '🇲🇺': 'MU', // 毛里求斯
      '🇲🇽': 'MX', // 墨西哥
      '🇫🇲': 'FM', // 密克罗尼西亚
      '🇲🇩': 'MD', // 摩尔多瓦
      '🇲🇨': 'MC', // 摩纳哥
      '🇲🇳': 'MN', // 蒙古
      '🇲🇪': 'ME', // 黑山
      '🇲🇦': 'MA', // 摩洛哥
      '🇲🇿': 'MZ', // 莫桑比克
      '🇲🇲': 'MM', // 缅甸
      '🇳🇦': 'NA', // 纳米比亚
      '🇳🇷': 'NR', // 瑙鲁
      '🇳🇵': 'NP', // 尼泊尔
      '🇳🇱': 'NL', // 荷兰
      '🇳🇿': 'NZ', // 新西兰
      '🇳🇮': 'NI', // 尼加拉瓜
      '🇳🇪': 'NE', // 尼日尔
      '🇳🇬': 'NG', // 尼日利亚
      '🇳🇴': 'NO', // 挪威
      '🇴🇲': 'OM', // 阿曼
      '🇵🇰': 'PK', // 巴基斯坦
      '🇵🇼': 'PW', // 帕劳
      '🇵🇸': 'PS', // 巴勒斯坦
      '🇵🇦': 'PA', // 巴拿马
      '🇵🇬': 'PG', // 巴布亚新几内亚
      '🇵🇾': 'PY', // 巴拉圭
      '🇵🇪': 'PE', // 秘鲁
      '🇵🇭': 'PH', // 菲律宾
      '🇵🇱': 'PL', // 波兰
      '🇵🇹': 'PT', // 葡萄牙
      '🇶🇦': 'QA', // 卡塔尔
      '🇷🇴': 'RO', // 罗马尼亚
      '🇷🇺': 'RU', // 俄罗斯
      '🇷🇼': 'RW', // 卢旺达
      '🇰🇳': 'KN', // 圣基茨和尼维斯
      '🇱🇨': 'LC', // 圣卢西亚
      '🇻🇨': 'VC', // 圣文森特和格林纳丁斯
      '🇼🇸': 'WS', // 萨摩亚
      '🇸🇲': 'SM', // 圣马力诺
      '🇸🇹': 'ST', // 圣多美和普林西比
      '🇸🇦': 'SA', // 沙特阿拉伯
      '🇸🇳': 'SN', // 塞内加尔
      '🇷🇸': 'RS', // 塞尔维亚
      '🇸🇨': 'SC', // 塞舌尔
      '🇸🇱': 'SL', // 塞拉利昂
      '🇸🇬': 'SG', // 新加坡
      '🇸🇰': 'SK', // 斯洛伐克
      '🇸🇮': 'SI', // 斯洛文尼亚
      '🇸🇧': 'SB', // 所罗门群岛
      '🇸🇴': 'SO', // 索马里
      '🇿🇦': 'ZA', // 南非
      '🇸🇸': 'SS', // 南苏丹
      '🇪🇸': 'ES', // 西班牙
      '🇱🇰': 'LK', // 斯里兰卡
      '🇸🇩': 'SD', // 苏丹
      '🇸🇷': 'SR', // 苏里南
      '🇸🇿': 'SZ', // 斯威士兰
      '🇸🇪': 'SE', // 瑞典
      '🇨🇭': 'CH', // 瑞士
      '🇸🇾': 'SY', // 叙利亚
      '🇹🇼': 'TW', // 台湾
      '🇹🇯': 'TJ', // 塔吉克斯坦
      '🇹🇿': 'TZ', // 坦桑尼亚
      '🇹🇭': 'TH', // 泰国
      '🇹🇱': 'TL', // 东帝汶
      '🇹🇬': 'TG', // 多哥
      '🇹🇴': 'TO', // 汤加
      '🇹🇹': 'TT', // 特立尼达和多巴哥
      '🇹🇳': 'TN', // 突尼斯
      '🇹🇷': 'TR', // 土耳其
      '🇹🇲': 'TM', // 土库曼斯坦
      '🇹🇻': 'TV', // 图瓦卢
      '🇺🇬': 'UG', // 乌干达
      '🇺🇦': 'UA', // 乌克兰
      '🇦🇪': 'AE', // 阿联酋
      '🇬🇧': 'GB', // 英国
      '🇺🇸': 'US', // 美国
      '🇺🇾': 'UY', // 乌拉圭
      '🇺🇿': 'UZ', // 乌兹别克斯坦
      '🇻🇺': 'VU', // 瓦努阿图
      '🇻🇦': 'VA', // 梵蒂冈
      '🇻🇪': 'VE', // 委内瑞拉
      '🇻🇳': 'VN', // 越南
      '🇾🇪': 'YE', // 也门
      '🇿🇲': 'ZM', // 赞比亚
      '🇿🇼': 'ZW', // 津巴布韦
    };

    return emojiToCountryCode[flagEmoji];
  }

  String _getNodeProtocol(String node) {
    try {
      // 从节点字符串中提取协议
      final protocol = node.split('://')[0].toUpperCase();
      switch (protocol) {
        case 'SS':
          return 'Shadowsocks';
        case 'VMESS':
          return 'Vmess';
        case 'VLESS':
          return 'Vless';
        case 'HYSTERIA':
          return 'Hysteria';
        case 'HYSTERIA2':
          return 'Hysteria2';
        default:
          return protocol;
      }
    } catch (e) {
      print('解析节点协议失败: $e');
      return 'Unknown';
    }
  }

  void _applySettings() async {
    if (_selectedNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先选择一个节点'),
          width: MediaQuery.of(context).size.width * 0.45,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('proxy_mode', _selectedMode.toString());
      await prefs.setString('selected_node', _selectedNode!);

      _showSuccessSnackBar('设置已保存');
    } catch (e) {
      print('保存设置失败: $e');
      _showSuccessSnackBar('保存设置失败');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 700),
        behavior: SnackBarBehavior.floating,
        width: MediaQuery.of(context).size.width * 0.45,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 设置窗口大小
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 只在初始化时设置窗口大小
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
        title: const Text('节点选择'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 模式选择
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Text('代理模式：', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 16),
                      ChoiceChip(
                        label: const Text('全局模式'),
                        selected: _selectedMode == ProxyMode.global,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedMode = ProxyMode.global;
                            });
                            _applySettings();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('规则模式'),
                        selected: _selectedMode == ProxyMode.rule,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedMode = ProxyMode.rule;
                            });
                            _applySettings();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                // 节点列表
                Expanded(
                  child: _nodes.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off,
                                  size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('暂无节点信息',
                                  style: TextStyle(color: Colors.grey)),
                              SizedBox(height: 8),
                              Text('请点击右上角刷新按钮更新节点列表',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            // 计算每行可以放置的卡片数量
                            final cardWidth = 280.0; // 卡片宽度
                            final cardHeight = 80.0; // 卡片高度
                            final spacing = 8.0; // 卡片间距
                            final crossAxisCount =
                                (constraints.maxWidth / (cardWidth + spacing))
                                    .floor();
                            final actualCrossAxisCount =
                                crossAxisCount < 2 ? 2 : crossAxisCount;

                            return GridView.builder(
                              controller: _controller,
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: actualCrossAxisCount,
                                childAspectRatio: cardWidth / cardHeight,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                              ),
                              itemCount: _nodes.length,
                              itemBuilder: (context, index) {
                                final node = _nodes[index];
                                final nodeName = _getNodeName(node);
                                final nodeFlag = _getNodeFlag(node);
                                final nodeProtocol = _getNodeProtocol(node);
                                final isSelected = _selectedNode == node;

                                return SizedBox(
                                  width: cardWidth,
                                  height: cardHeight,
                                  child: Stack(
                                    children: [
                                      // 选中时的左侧绿色条
                                      if (isSelected)
                                        Positioned(
                                          left: -4,
                                          top: 8,
                                          bottom: 8,
                                          child: Container(
                                            width: 3,
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius:
                                                  BorderRadius.circular(1.5),
                                            ),
                                          ),
                                        ),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(
                                              sigmaX: 10, sigmaY: 10),
                                          child: Card(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surface
                                                .withOpacity(0.5),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : Colors.transparent,
                                                width: 1,
                                              ),
                                            ),
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _selectedNode = node;
                                                });
                                                _applySettings();
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    // 节点名称和国旗
                                                    Expanded(
                                                      flex: 3,
                                                      child: Row(
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    left: 6),
                                                            child: SizedBox(
                                                              width: 20,
                                                              height: 20,
                                                              child: Flag
                                                                  .fromString(
                                                                nodeFlag,
                                                                height: 20,
                                                                width: 20,
                                                                fit: BoxFit
                                                                    .contain,
                                                                borderRadius: 2,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      left: 6),
                                                              child: Text(
                                                                nodeName,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleMedium,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                maxLines: 1,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    // 协议显示在下部分
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  left: 6),
                                                          child: Text(
                                                            nodeProtocol,
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .onSurfaceVariant,
                                                                ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
