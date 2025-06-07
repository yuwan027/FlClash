class PaymentMethod {
  final int id;
  final String name;
  final String payment;
  final String? icon;
  final int? handlingFeeFixed;
  final int? handlingFeePercent;

  PaymentMethod({
    required this.id,
    required this.name,
    required this.payment,
    this.icon,
    this.handlingFeeFixed,
    this.handlingFeePercent,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'],
      name: json['name'],
      payment: json['payment'],
      icon: json['icon'],
      handlingFeeFixed: json['handling_fee_fixed'],
      handlingFeePercent: json['handling_fee_percent'],
    );
  }
}
