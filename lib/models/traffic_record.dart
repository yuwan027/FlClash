class TrafficRecord {
  final DateTime date;
  final int upload;
  final int download;
  final int total;

  TrafficRecord({
    required this.date,
    required this.upload,
    required this.download,
    required this.total,
  });

  factory TrafficRecord.fromJson(Map<String, dynamic> json) {
    // 处理不同的日期字段名称和格式
    DateTime parseDate() {
      if (json['record_at'] != null) {
        final dateValue = json['record_at'];
        if (dateValue is String) {
          return DateTime.parse(dateValue);
        } else if (dateValue is int) {
          // 如果是时间戳（秒或毫秒）
          return dateValue > 1000000000000 
              ? DateTime.fromMillisecondsSinceEpoch(dateValue)
              : DateTime.fromMillisecondsSinceEpoch(dateValue * 1000);
        }
      }
      
      // 尝试其他可能的字段名
      if (json['date'] != null) {
        final dateValue = json['date'];
        if (dateValue is String) {
          return DateTime.parse(dateValue);
        } else if (dateValue is int) {
          return dateValue > 1000000000000 
              ? DateTime.fromMillisecondsSinceEpoch(dateValue)
              : DateTime.fromMillisecondsSinceEpoch(dateValue * 1000);
        }
      }
      
      // 如果都没有，使用当前时间
      return DateTime.now();
    }
    
    // 安全地解析数值，确保返回int类型
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }
    
    final upload = parseInt(json['u'] ?? json['upload']);
    final download = parseInt(json['d'] ?? json['download']);
    
    return TrafficRecord(
      date: parseDate(),
      upload: upload,
      download: download,
      total: upload + download,
    );
  }
}

// 按日期分组流量数据
Map<DateTime, double> groupedTraffic(List<TrafficRecord> records) {
  final Map<DateTime, double> grouped = {};
  
  for (final record in records) {
    final dateOnly = DateTime(record.date.year, record.date.month, record.date.day);
    grouped[dateOnly] = (grouped[dateOnly] ?? 0) + record.total.toDouble();
  }
  
  return grouped;
} 