import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
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
  final _controller = WebviewController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    // 修正支付链接中的多余斜杠（不影响协议头）
    String fixedUrl = widget.paymentUrl.replaceAll(RegExp(r'(?<!:)/{2,}'), '/');
    // 还原协议头的双斜杠
    if (fixedUrl.startsWith('http:/') && !fixedUrl.startsWith('http://')) {
      fixedUrl = fixedUrl.replaceFirst('http:/', 'http://');
    } else if (fixedUrl.startsWith('https:/') &&
        !fixedUrl.startsWith('https://')) {
      fixedUrl = fixedUrl.replaceFirst('https:/', 'https://');
    }

    try {
      await _controller.initialize();
      // 提取原始的 return_url
      Uri initialUri = Uri.parse(fixedUrl);
      String? originalReturnUrlEncoded =
          initialUri.queryParameters['return_url'];
      String? originalReturnUrl;
      if (originalReturnUrlEncoded != null) {
        originalReturnUrl = Uri.decodeComponent(originalReturnUrlEncoded);
      }

      _controller.url.listen((url) {
        // 只有当当前URL与原始的return_url匹配时才返回
        if (originalReturnUrl != null && url.startsWith(originalReturnUrl)) {
          Navigator.pop(context);
        }
      });

      _controller.loadingState.listen((state) {
        setState(() {
          isLoading = state == LoadingState.loading;
        });
      });

      await _controller.loadUrl(fixedUrl);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WebView 初始化失败: $e')),
        );
        Navigator.pop(context); // 初始化失败，返回上一页
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      body: Stack(
        children: [
          Webview(
            _controller,
          ),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
