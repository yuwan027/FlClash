class Plan {
  final int id;
  final int groupId;
  final int transferEnable;
  final String name;
  final int? deviceLimit;
  final int? speedLimit;
  final int show;
  final int sort;
  final int renew;
  final String content;
  final int? monthPrice;
  final int? quarterPrice;
  final int? halfYearPrice;
  final int? yearPrice;
  final int? twoYearPrice;
  final int? threeYearPrice;
  final int? onetimePrice;
  final int resetPrice;
  final int? resetTrafficMethod;
  final int? capacityLimit;
  final int createdAt;
  final int updatedAt;

  Plan({
    required this.id,
    required this.groupId,
    required this.transferEnable,
    required this.name,
    this.deviceLimit,
    this.speedLimit,
    required this.show,
    required this.sort,
    required this.renew,
    required this.content,
    this.monthPrice,
    this.quarterPrice,
    this.halfYearPrice,
    this.yearPrice,
    this.twoYearPrice,
    this.threeYearPrice,
    this.onetimePrice,
    required this.resetPrice,
    this.resetTrafficMethod,
    this.capacityLimit,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id'],
      groupId: json['group_id'],
      transferEnable: json['transfer_enable'],
      name: json['name'],
      deviceLimit: json['device_limit'],
      speedLimit: json['speed_limit'],
      show: json['show'],
      sort: json['sort'],
      renew: json['renew'],
      content: json['content'],
      monthPrice: json['month_price'],
      quarterPrice: json['quarter_price'],
      halfYearPrice: json['half_year_price'],
      yearPrice: json['year_price'],
      twoYearPrice: json['two_year_price'],
      threeYearPrice: json['three_year_price'],
      onetimePrice: json['onetime_price'],
      resetPrice: json['reset_price'],
      resetTrafficMethod: json['reset_traffic_method'],
      capacityLimit: json['capacity_limit'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  String get formattedTransferEnable {
    if (transferEnable >= 1024) {
      return '${(transferEnable / 1024).toStringAsFixed(1)} TB';
    }
    return '$transferEnable GB';
  }

  String get formattedMonthPrice {
    return '¥${(monthPrice ?? 0) / 100}';
  }

  String get formattedQuarterPrice {
    return '¥${(quarterPrice ?? 0) / 100}';
  }

  String get formattedHalfYearPrice {
    return '¥${(halfYearPrice ?? 0) / 100}';
  }

  String get formattedYearPrice {
    return '¥${(yearPrice ?? 0) / 100}';
  }

  String get formattedTwoYearPrice {
    return '¥${(twoYearPrice ?? 0) / 100}';
  }

  String get formattedThreeYearPrice {
    return '¥${(threeYearPrice ?? 0) / 100}';
  }

  String get formattedOnetimePrice {
    return '¥${(onetimePrice ?? 0) / 100}';
  }
}
