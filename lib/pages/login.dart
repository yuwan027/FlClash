import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../common/http_client.dart' hide jwtTokenProvider;
import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import 'dart:convert';

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
    _loadCachedUserInfo();

    // 启动时清空 JWT，确保初始状态
    ref.read(jwtTokenProvider.notifier).state = null;
    ref.read(dataLoadedProvider.notifier).state = false;
    
    // 只清理JWT，保留其他缓存信息
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('jwt_token');
      } catch (e) {
        print('清理JWT失败: $e');
      }
    });
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

  Future<void> _loadCachedUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString('user_info');
      
      // 无论是否有JWT token都加载缓存的用户信息用于显示头像
      if (userInfoStr != null) {
        final userInfo = jsonDecode(userInfoStr);
        ref.read(userInfoProvider.notifier).state = userInfo;
      }
    } catch (e) {
      print('加载缓存用户信息失败: $e');
    }
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
          responseData['data']['auth_data'] != null) {
        final authData = responseData['data']['auth_data'] as String;

        // 更新全局auth_data状态
        ref.read(jwtTokenProvider.notifier).state = authData;

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
    final userInfo = ref.watch(userInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('登录'), automaticallyImplyLeading: false),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 优先显示用户头像，否则显示默认图标
                  Builder(
                    builder: (context) {
                      // 检查用户信息和头像URL的有效性
                      if (userInfo != null && 
                          userInfo['avatar_url'] != null && 
                          userInfo['avatar_url'].toString().trim().isNotEmpty) {
                        return Container(
                          width: 80,
                          height: 80,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.grey[200],
                            child: ClipOval(
                              child: SizedBox(
                                width: 80,
                                height: 80,
                                child: Image.network(
                                  userInfo['avatar_url'],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    print('登录页头像加载失败: $error');
                                    return const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.white,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        // 没有有效用户信息或头像URL时显示默认图标
                        return const Icon(Icons.account_circle, size: 80, color: Colors.blue);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 左侧小头像
                            userInfo != null && 
                            userInfo['avatar_url'] != null && 
                            userInfo['avatar_url'].toString().trim().isNotEmpty
                                ? CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.grey[300],
                                    backgroundImage: NetworkImage(
                                      userInfo['avatar_url'],
                                    ),
                                    onBackgroundImageError: (exception, stackTrace) {
                                      print('快速登录头像加载失败: $exception');
                                    },
                                  )
                                : CircleAvatar(
                                    radius: 10,
                                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                                    child: Icon(
                                      Icons.person,
                                      size: 12,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                            const SizedBox(width: 8),
                            Text(
                              '以 $_cachedEmail 身份登录',
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
