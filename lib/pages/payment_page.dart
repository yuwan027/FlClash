import 'package:flutter/material.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class PaymentPage extends StatefulWidget {
  final String paymentUrl;
  final String tradeNo;

  const PaymentPage({
    super.key,
    required this.paymentUrl,
    required this.tradeNo,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool _hasLaunched = false;

  @override
  void initState() {
    super.initState();
    _launchPaymentUrl();
  }

  Future<void> _launchPaymentUrl() async {
    // 修正支付链接中的多余斜杠（不影响协议头）
    String fixedUrl = widget.paymentUrl.replaceAll(RegExp(r'(?<!:)/{2,}'), '/');
    // 还原协议头的双斜杠
    if (fixedUrl.startsWith('http:/') && !fixedUrl.startsWith('http://')) {
      fixedUrl = fixedUrl.replaceFirst('http:/', 'http://');
    } else if (fixedUrl.startsWith('https:/') &&
        !fixedUrl.startsWith('https://')) {
      fixedUrl = fixedUrl.replaceFirst('https:/', 'https://');
    }

    if (await canLaunchUrl(Uri.parse(fixedUrl))) {
      await launchUrl(Uri.parse(fixedUrl),
          mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开支付链接，请检查系统浏览器设置。')),
        );
      }
    }
    if (mounted) {
      setState(() {
        _hasLaunched = true;
      });
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('支付'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_hasLaunched) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('正在打开支付页面...'),
            ] else ...[
              const Text('支付页面已尝试打开。如果未跳转，请手动返回。'),
            ],
          ],
        ),
      ),
    );
  }
}
