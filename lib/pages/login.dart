import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';
import '../l10n/l10n.dart';
import 'subscription.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WindowListener {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = true;
  String _loginStatus = '';
  static const int _timeoutSeconds = 30;
  String? _cachedEmail;
  String? _cachedPassword;
  String? _cachedAvatar;

  @override
  void initState() {
    super.initState();
    // 设置窗口样式
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setSize(const Size(340, 500));
      windowManager.setResizable(false);
    }
    _loadCachedCredentials();
    _loadLoginInfo();
  }

  @override
  void dispose() {
    // 恢复窗口样式
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
      windowManager.setResizable(true);
    }
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedCredentials() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedEmail = prefs.getString('cached_email');
      _cachedPassword = prefs.getString('cached_password');
      _cachedAvatar = prefs.getString('cached_avatar');
    });
  }

  Future<void> _clearCredentials() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_email');
    await prefs.remove('cached_password');
    await prefs.remove('cached_avatar');

    setState(() {
      _cachedEmail = null;
      _cachedPassword = null;
      _cachedAvatar = null;
    });
  }

  Future<void> _quickLogin() async {
    if (!mounted || _cachedEmail == null || _cachedPassword == null) return;

    _emailController.text = _cachedEmail!;
    _passwordController.text = _cachedPassword!;
    await _login();
  }

  void _handleLogin() {
    if (!mounted) return;

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱和密码')),
      );
      return;
    }
    _login();
  }

  Future<void> _loadLoginInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('cached_email');
    final password = prefs.getString('cached_password');

    if (email != null && password != null) {
      setState(() {
        _emailController.text = email;
        _passwordController.text = password;
      });
    }
  }

  Future<void> _saveLoginInfo(
      String email, String password, String avatarUrl) async {
    if (!_rememberMe) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_email', email);
    await prefs.setString('cached_password', password);
    await prefs.setString('cached_avatar', avatarUrl);
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱和密码')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await HttpClient.post(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/login'),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', data['data']['token']);
          await prefs.setString('user_info', jsonEncode(data['data']));

          // 保存登录信息到缓存
          await _saveLoginInfo(
            _emailController.text,
            _passwordController.text,
            data['data']['avatar_url'] ?? '',
          );

          // 检查并导入订阅
          if (data['data']['subscribe_url'] != null) {
            final subscribeUrl = data['data']['subscribe_url'] as String;
            final uri = Uri.parse(subscribeUrl);
            final token = uri.queryParameters['token'];

            if (token != null) {
              final cachedToken = prefs.getString('last_subscribe_token');
              if (cachedToken != token) {
                // 新订阅或需要更新
                await prefs.setString('last_subscribe_token', token);
                // TODO: 调用订阅导入功能
                // 这里需要调用其他页面的订阅导入功能
              }
            }
          }

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SubscriptionPage()),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录失败，请检查账号密码')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录失败，请检查网络连接')),
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

  Future<void> _getUserInfo(String jwtToken) async {
    try {
      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/info'),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Authorization': jwtToken,
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_info', jsonEncode(data['data']));
          await prefs.setString('jwt_token', jwtToken);
          // 缓存头像和登录信息，但不立即显示
          if (data['data']['avatar_url'] != null) {
            await prefs.setString('cached_avatar', data['data']['avatar_url']);
            await prefs.setString('cached_email', _emailController.text);
            await prefs.setString('cached_password', _passwordController.text);
          }
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
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: '邮箱',
                  prefixIcon: Icon(Icons.email, color: colorScheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (_) {
                  if (_passwordController.text.isNotEmpty) {
                    _handleLogin();
                  } else {
                    FocusScope.of(context).nextFocus();
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock, color: colorScheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                obscureText: true,
                onSubmitted: (_) {
                  if (_emailController.text.isNotEmpty) {
                    _handleLogin();
                  } else {
                    FocusScope.of(context).previousFocus();
                  }
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
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
              if (_cachedEmail != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_cachedAvatar != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundImage: NetworkImage(_cachedAvatar!),
                        ),
                      ),
                    TextButton(
                      onPressed: _isLoading ? null : _quickLogin,
                      child: Text(
                        '使用 $_cachedEmail 登录',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: _isLoading ? null : _clearCredentials,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.grey,
                    ),
                  ],
                ),
              ],
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
