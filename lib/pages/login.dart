import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/http_client.dart';
import '../config/app_config.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final HttpClientHelper _httpHelper;

  bool _isLoading = false;
  bool _obscurePassword = true;

  // 缓存邮箱和密码
  String? _cachedEmail;
  String? _cachedPassword;

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

    _loadCachedCredentials();

    // 启动时清空 token，确保初始状态
    ref.read(jwtTokenProvider.notifier).state = null;
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

  Future<void> _saveCachedCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_email', email);
    await prefs.setString('cached_password', password);
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

        // 更新全局token状态
        ref.read(jwtTokenProvider.notifier).state = token;

        // 缓存邮箱和密码
        await _saveCachedCredentials(
          _emailController.text,
          _passwordController.text,
        );

        setState(() {
          _cachedEmail = _emailController.text;
          _cachedPassword = _passwordController.text;
        });

        if (mounted) {
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

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

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
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入邮箱';
                    if (!value.contains('@')) return '请输入有效的邮箱地址';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
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
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if (value == null || value.isEmpty) return '请输入密码';
                    if (value.length < 6) return '密码长度不能少于6位';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) {
                    if (_canSubmit && !_isLoading) {
                      _login();
                    }
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
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                      onPressed: _isLoading ? null : _quickLogin,
                      child: Text(
                        '以 $_cachedEmail 身份登录',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 12,
                        ),
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
