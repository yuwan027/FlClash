import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_html/flutter_html.dart';
import '../l10n/l10n.dart';
import 'login.dart';
import 'subscription.dart';
import '../utils/subscription_importer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/providers/app.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      // 从本地存储加载节点列表
      final nodesStr = prefs.getString('nodes');
      if (nodesStr != null) {
        final List<dynamic> decodedNodes = jsonDecode(nodesStr);
        setState(() {
          _nodes = decodedNodes.cast<String>();
        });
      }

      // 加载已保存的设置
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

  void _applySettings() async {
    if (_selectedNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个节点')),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('proxy_mode', _selectedMode.toString());
      await prefs.setString('selected_node', _selectedNode!);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    } catch (e) {
      print('保存设置失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存设置失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 设置窗口大小
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setSize(const Size(800, 700));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('节点选择'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const SubscriptionPage(),
              ),
            );
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
                      : ListView.builder(
                          itemCount: _nodes.length,
                          itemBuilder: (context, index) {
                            final node = _nodes[index];
                            return ListTile(
                              title: Text(node.split('@')[1].split('#')[0]),
                              subtitle: Text(node.split('@')[0]),
                              trailing: Radio<String>(
                                value: node,
                                groupValue: _selectedNode,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedNode = value;
                                  });
                                },
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedNode = node;
                                });
                              },
                            );
                          },
                        ),
                ),
                // 应用按钮
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _applySettings,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('应用设置'),
                  ),
                ),
              ],
            ),
    );
  }
}
