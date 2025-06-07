class Order {
  final int? inviteUserId;
  final int planId;
  final int? couponId;
  final int? paymentId;
  final int type;
  final String period;
  final String tradeNo;
  final String? callbackNo;
  final int totalAmount;
  final int? balanceAmount;
  final int status;
  final int commissionStatus;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? plan;

  Order({
    this.inviteUserId,
    required this.planId,
    this.couponId,
    this.paymentId,
    required this.type,
    required this.period,
    required this.tradeNo,
    this.callbackNo,
    required this.totalAmount,
    this.balanceAmount,
    required this.status,
    required this.commissionStatus,
    this.paidAt,
    required this.createdAt,
    required this.updatedAt,
    this.plan,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      inviteUserId: json['invite_user_id'],
      planId: json['plan_id'],
      couponId: json['coupon_id'],
      paymentId: json['payment_id'],
      type: json['type'],
      period: json['period'],
      tradeNo: json['trade_no'],
      callbackNo: json['callback_no'],
      totalAmount: json['total_amount'] ?? 0,
      balanceAmount: json['balance_amount'],
      status: json['status'],
      commissionStatus: json['commission_status'],
      paidAt: json['paid_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['paid_at'] * 1000)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] * 1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] * 1000),
      plan: json['plan'],
    );
  }

  String get statusText {
    switch (status) {
      case 0:
        return '待支付';
      case 1:
        return '正在开通';
      case 2:
        return '已取消';
      case 3:
        return '已完成';
      case 4:
        return '已抵扣';
      default:
        return '未知状态';
    }
  }

  String get formattedBalanceAmount {
    if (balanceAmount == null) return '0.00';
    return (balanceAmount! / 100).toStringAsFixed(2);
  }

  String get formattedTotalAmount {
    return (totalAmount / 100).toStringAsFixed(2);
  }

  String get periodText {
    switch (period) {
      case 'month_price':
        return '月付';
      case 'quarter_price':
        return '季付';
      case 'half_year_price':
        return '半年付';
      case 'year_price':
        return '年付';
      case 'two_year_price':
        return '两年付';
      case 'three_year_price':
        return '三年付';
      case 'deposit':
        return '充值';
      case 'reset_price':
        return '重置流量';
      default:
        return '未知周期';
    }
  }

  String get typeText {
    switch (type) {
      case 1:
        return '新购';
      case 2:
        return '续费';
      case 3:
        return '升级';
      case 4:
        return '抵扣/重置';
      case 9:
        return '充值';
      default:
        return '未知类型';
    }
  }

  String get planName {
    if (plan == null) return '未知套餐';
    return plan!['name'] ?? '未知套餐';
  }

  bool get isPaid => status == 3;
  bool get isPending => status == 0;
  bool get isCancelled => status == 2;
  bool get isRefunded => status == 4;
}
