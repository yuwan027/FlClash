import 'package:flutter_riverpod/flutter_riverpod.dart';

// 用户信息 Provider
final userInfoProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// JWT Token Provider
final jwtTokenProvider = StateProvider<String?>((ref) => null);

// 数据加载状态 Provider，用于控制 loadInitialData 的调用
final dataLoadedProvider = StateProvider<bool>((ref) => false);
