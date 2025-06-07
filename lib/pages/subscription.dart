import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../l10n/l10n.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadSubscriptionInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfoStr = prefs.getString('user_info');
    if (userInfoStr != null) {
      setState(() {
        _userInfo = jsonDecode(userInfoStr);
      });
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwt_token');
    if (jwtToken == null) return;

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/getSubscribe'),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          setState(() {
            _subscriptionInfo = data['data'];
          });
        }
      }
    } catch (e) {
      print('获取订阅信息失败: $e');
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

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/transfer'),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'transfer_amount': (amount * 100).toInt(),
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).transferSuccess)),
        );
        _transferAmountController.clear();
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).subscriptionInfo),
        actions: [
          PopupMenuButton<String>(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage:
                        NetworkImage(_userInfo!['avatar_url'] ?? ''),
                  ),
                  const SizedBox(width: 8),
                  Text(_userInfo!['email'] ?? ''),
                ],
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Text(AppLocalizations.of(context).yourBalance(
                  _formatBalance(_userInfo!['balance']),
                )),
              ),
              PopupMenuItem(
                child: Text(AppLocalizations.of(context).yourCommission(
                  _formatBalance(_userInfo!['commission_balance']),
                )),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppLocalizations.of(context).totalTraffic}: ${_formatBytes(_userInfo!['transfer_enable'])}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_subscriptionInfo != null) ...[
                      const SizedBox(height: 16),
                      Text(
                          '${AppLocalizations.of(context).usedUpload}: ${_formatBytes(_subscriptionInfo!['u'])}'),
                      Text(
                          '${AppLocalizations.of(context).usedDownload}: ${_formatBytes(_subscriptionInfo!['d'])}'),
                      if (_subscriptionInfo!['plan'] != null) ...[
                        const SizedBox(height: 16),
                        Text(
                            '${AppLocalizations.of(context).currentPlan}: ${_subscriptionInfo!['plan']['name']}'),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).balanceTransfer,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _transferAmountController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).unitYuan,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _transferBalance,
                          child: _isLoading
                              ? const CircularProgressIndicator()
                              : Text(AppLocalizations.of(context).transfer),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
