import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkSettings {
  final bool systemProxy;

  NetworkSettings({
    required this.systemProxy,
  });

  NetworkSettings copyWith({
    bool? systemProxy,
  }) {
    return NetworkSettings(
      systemProxy: systemProxy ?? this.systemProxy,
    );
  }
}

final networkSettingProvider =
    StateNotifierProvider<NetworkSettingsNotifier, NetworkSettings>((ref) {
  return NetworkSettingsNotifier();
});

class NetworkSettingsNotifier extends StateNotifier<NetworkSettings> {
  NetworkSettingsNotifier() : super(NetworkSettings(systemProxy: false));

  void toggleSystemProxy() {
    state = state.copyWith(systemProxy: !state.systemProxy);
  }
}
