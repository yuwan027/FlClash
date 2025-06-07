class TrafficRecord {
  final int u;
  final int d;
  final DateTime recordAt;
  final double serverRate;

  TrafficRecord({
    required this.u,
    required this.d,
    required this.recordAt,
    required this.serverRate,
  });

  factory TrafficRecord.fromJson(Map<String, dynamic> json) {
    return TrafficRecord(
      u: json['u'],
      d: json['d'],
      recordAt: DateTime.fromMillisecondsSinceEpoch(json['record_at'] * 1000),
      serverRate: double.parse(json['server_rate']),
    );
  }

  double get cost => (u + d) * serverRate;
}

Map<DateTime, double> groupedTraffic(List<TrafficRecord> records) {
  final map = <DateTime, double>{};
  for (var r in records) {
    final day = DateTime(r.recordAt.year, r.recordAt.month, r.recordAt.day);
    map[day] = (map[day] ?? 0) + r.cost;
  }
  return map;
}
