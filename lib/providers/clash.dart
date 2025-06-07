import 'package:flutter_riverpod/flutter_riverpod.dart';

class TunConfig {
  final bool enable;

  TunConfig({
    required this.enable,
  });

  TunConfig copyWith({
    bool? enable,
  }) {
    return TunConfig(
      enable: enable ?? this.enable,
    );
  }
}

class ClashConfig {
  final TunConfig tun;

  ClashConfig({
    required this.tun,
  });

  ClashConfig copyWith({
    TunConfig? tun,
  }) {
    return ClashConfig(
      tun: tun ?? this.tun,
    );
  }
}

final patchClashConfigProvider =
    StateNotifierProvider<ClashConfigNotifier, ClashConfig>((ref) {
  return ClashConfigNotifier();
});

class ClashConfigNotifier extends StateNotifier<ClashConfig> {
  ClashConfigNotifier() : super(ClashConfig(tun: TunConfig(enable: false)));

  void updateState(ClashConfig Function(ClashConfig) update) {
    state = update(state);
  }
}
