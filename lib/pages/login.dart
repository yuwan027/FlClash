import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/http_client.dart';
import '../config/app_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final HttpClientHelper _httpHelper = HttpClientHelper();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // 缓存邮箱和密码
  String? _cachedEmail;
  String? _cachedPassword;

  @override
  void initState() {
    super.initState();
    _loadCachedCredentials(); // 只加载缓存，不预填充输入框
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _httpHelper.close();
    super.dispose();
  }

  Future<void> _loadCachedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedEmail = prefs.getString('cached_email');
      _cachedPassword = prefs.getString('cached_password');
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final responseData = await _httpHelper.postJson(
        Uri.parse('${AppConfig.baseUrl}/api/v1/passport/auth/login'),
        {
          'email': _emailController.text,
          'password': _passwordController.text,
        },
      );

      if (responseData['data'] != null &&
          responseData['data']['token'] != null) {
        final token = responseData['data']['token'] as String;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);

        // **保存邮箱和密码缓存**
        await prefs.setString('cached_email', _emailController.text);
        await prefs.setString('cached_password', _passwordController.text);

        if (mounted) {
          // 登录成功，跳转到首页
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        _showError('登录失败：无效的响应数据');
      }
    } catch (e) {
      _showError('登录失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _quickLogin() {
    if (_cachedEmail != null && _cachedPassword != null) {
      _emailController.text = _cachedEmail!;
      _passwordController.text = _cachedPassword!;
      _login();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('登录'), automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.account_circle, size: 100, color: Colors.blue),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入邮箱';
                    if (!value.contains('@')) return '请输入有效的邮箱地址';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入密码';
                    if (value.length < 6) return '密码长度不能少于6位';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
                if (_cachedEmail != null)
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
