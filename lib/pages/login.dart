import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../config/app_config.dart';
import 'subscription.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WindowListener {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String _loginStatus = '';
  static const int _timeoutSeconds = 30;

  @override
  void initState() {
    super.initState();
    // 设置窗口样式
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setSize(const Size(340, 500));
      windowManager.setResizable(false);
    }
  }

  @override
  void dispose() {
    // 恢复窗口样式
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
      windowManager.setResizable(true);
    }
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _loginStatus = '正在发送登录请求...';
    });

    final email = _emailController.text;
    final password = _passwordController.text;

    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/v1/passport/auth/login'),
            headers: {
              'User-Agent': AppConfig.userAgent,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data']['auth_data'] != null) {
          final jwtToken = data['data']['auth_data'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', jwtToken);
          await prefs.setString('email', email);

          setState(() {
            _loginStatus = '登录成功，正在获取用户信息...';
          });

          // 获取用户信息
          try {
            await _getUserInfo(jwtToken);

            if (mounted) {
              setState(() {
                _loginStatus = '正在跳转...';
              });

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const SubscriptionPage()),
              );
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _loginStatus = '获取用户信息失败';
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('获取用户信息失败，请重试')),
              );
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _loginStatus = '登录失败，请检查账号密码';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录失败，请检查邮箱和密码')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loginStatus = '登录失败，网络问题';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录超时，请重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getUserInfo(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_info', jsonEncode(data['data']));
          await prefs.setString('jwt_token', token);
        } else {
          throw Exception('用户信息为空');
        }
      } else {
        throw Exception('获取用户信息失败: ${response.statusCode}');
      }
    } catch (e) {
      print('获取用户信息失败: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: '邮箱',
                  prefixIcon: Icon(Icons.email, color: colorScheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock, color: colorScheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  minimumSize: const Size(double.infinity, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('登录'),
              ),
              const SizedBox(height: 10),
              Text(
                _loginStatus,
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
