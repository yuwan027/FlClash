import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../common/http_client.dart' hide jwtTokenProvider;
import '../models/traffic_record.dart';
import '../providers/auth_provider.dart';
import 'dart:math' as math;

// 流量数据点
// 流量数据点
class TrafficDataPoint {
  final DateTime date;
  final double bytes;

  TrafficDataPoint(this.date, this.bytes);
}

// 每日流量详细数据
class DailyTrafficData {
  int upload;
  int download;

  DailyTrafficData({required this.upload, required this.download});
}

// 自定义绘制趋势图
class TrendChartPainter extends CustomPainter {
  final List<TrafficDataPoint> data;
  final String Function(double) formatBytes;

  TrendChartPainter(this.data, this.formatBytes);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // 计算数据范围
    final minDate = data.first.date;
    final maxDate = data.last.date;
    final dateRange = maxDate.difference(minDate).inDays.toDouble();
    
    final maxBytes = data.map((e) => e.bytes).reduce(math.max);
    final minBytes = data.map((e) => e.bytes).reduce(math.min);
    final bytesRange = maxBytes - minBytes;

    // 绘制区域
    const padding = 60.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;

    // 绘制网格和坐标轴标签
    _drawGrid(canvas, size, padding, chartWidth, chartHeight, gridPaint, textPainter, 
              minDate, maxDate, minBytes, maxBytes, dateRange, bytesRange);

    // 绘制数据线和填充区域
    _drawDataLine(canvas, padding, chartWidth, chartHeight, paint, fillPaint,
                  minDate, minBytes, dateRange, bytesRange);
  }

  void _drawGrid(Canvas canvas, Size size, double padding, double chartWidth, double chartHeight,
                 Paint gridPaint, TextPainter textPainter, DateTime minDate, DateTime maxDate,
                 double minBytes, double maxBytes, double dateRange, double bytesRange) {
    
    // 绘制5条垂直网格线 (时间轴)
    for (int i = 0; i <= 5; i++) {
      final x = padding + (chartWidth / 5) * i;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, size.height - padding),
        gridPaint,
      );

      // 时间标签
      if (dateRange > 0) {
        final dayOffset = (dateRange / 5) * i;
        final labelDate = minDate.add(Duration(days: dayOffset.round()));
        final labelText = '${labelDate.month}/${labelDate.day}';
        
        textPainter.text = TextSpan(
          text: labelText,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height - padding + 10),
        );
      }
    }

    // 绘制5条水平网格线 (流量轴)
    for (int i = 0; i <= 5; i++) {
      final y = padding + (chartHeight / 5) * i;
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );

      // 流量标签
      if (bytesRange > 0) {
        final bytesValue = maxBytes - (bytesRange / 5) * i;
        final labelText = formatBytes(bytesValue);
        
        textPainter.text = TextSpan(
          text: labelText,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(padding - textPainter.width - 10, y - textPainter.height / 2),
        );
      }
    }
  }

  void _drawDataLine(Canvas canvas, double padding, double chartWidth, double chartHeight,
                     Paint paint, Paint fillPaint, DateTime minDate, double minBytes,
                     double dateRange, double bytesRange) {
    
    if (data.length < 2) return;

    final path = Path();
    final fillPath = Path();
    bool firstPoint = true;

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final daysSinceMin = point.date.difference(minDate).inDays.toDouble();
      
      final x = padding + (dateRange > 0 ? (daysSinceMin / dateRange) * chartWidth : 0);
      final y = padding + chartHeight - (bytesRange > 0 ? ((point.bytes - minBytes) / bytesRange) * chartHeight : 0);

      if (firstPoint) {
        path.moveTo(x, y);
        fillPath.moveTo(x, padding + chartHeight);
        fillPath.lineTo(x, y);
        firstPoint = false;
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      // 绘制数据点
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.blue..style = PaintingStyle.fill);
    }

    // 完成填充路径
    final lastPoint = data.last;
    final lastDaysSinceMin = lastPoint.date.difference(minDate).inDays.toDouble();
    final lastX = padding + (dateRange > 0 ? (lastDaysSinceMin / dateRange) * chartWidth : 0);
    fillPath.lineTo(lastX, padding + chartHeight);
    fillPath.close();

    // 绘制填充区域和线条
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TrafficLogPage extends ConsumerStatefulWidget {
  const TrafficLogPage({super.key});

  @override
  ConsumerState<TrafficLogPage> createState() => _TrafficLogPageState();
}

class _TrafficLogPageState extends ConsumerState<TrafficLogPage> {
  bool _isLoading = true;
  List<TrafficRecord> _records = [];
  String? _error;
  late HttpClientHelper _httpHelper;

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
    _loadTrafficLog();
  }

  @override
  void dispose() {
    _httpHelper.close();
    super.dispose();
  }

  Future<void> _loadTrafficLog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = ref.read(jwtTokenProvider);
      if (token == null) {
        setState(() {
          _error = '未登录';
          _isLoading = false;
        });
        return;
      }

      final responseData = await _httpHelper.getJson(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/stat/getTrafficLog'),
      );

      if (responseData != null && responseData['data'] != null) {
        final List<dynamic> recordsJson = responseData['data'];
        print('获取到流量记录数据: ${recordsJson.length} 条');
        print('第一条数据示例: ${recordsJson.isNotEmpty ? recordsJson.first : 'N/A'}');
        
        try {
          final records = recordsJson
              .map((json) => TrafficRecord.fromJson(json))
              .toList();
          setState(() {
            _records = records;
            _isLoading = false;
          });
          print('成功解析 ${records.length} 条流量记录');
        } catch (e) {
          print('解析流量记录失败: $e');
          setState(() {
            _error = '数据解析失败: $e';
            _isLoading = false;
          });
          return;
        }
      } else {
        setState(() {
          _error = '获取数据失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  // 按天合并流量数据
  Map<DateTime, int> _groupTrafficByDay() {
    final Map<DateTime, int> grouped = {};
    
    for (final record in _records) {
      final dateOnly = DateTime(record.date.year, record.date.month, record.date.day);
      grouped[dateOnly] = (grouped[dateOnly] ?? 0) + record.total;
    }
    
    return grouped;
  }

  // 获取趋势图数据点
  List<TrafficDataPoint> _getTrendData() {
    final grouped = _groupTrafficByDay();
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    return sortedEntries.map((entry) => 
      TrafficDataPoint(entry.key, entry.value.toDouble())
    ).toList();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  String _formatBytesFromDouble(double bytes) {
    return _formatBytes(bytes.toInt());
  }

  // 自适应趋势图组件
  Widget _buildTrendChart() {
    final trendData = _getTrendData();
    if (trendData.isEmpty) {
      return const Center(
        child: Text('暂无趋势数据', style: TextStyle(color: Colors.grey)),
      );
    }

    return CustomPaint(
      painter: TrendChartPainter(trendData, _formatBytesFromDouble),
      child: Container(),
    );
  }

  // 按天合并的流量记录列表
  Widget _buildDailyTrafficList() {
    final dailyTraffic = _groupTrafficByDay();
    final sortedEntries = dailyTraffic.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // 按日期倒序排列

    if (sortedEntries.isEmpty) {
      return const Center(
        child: Text('暂无流量记录', style: TextStyle(color: Colors.grey)),
      );
    }

    // 计算每天的上传和下载分别合并
    final Map<DateTime, DailyTrafficData> dailyDetails = {};
    for (final record in _records) {
      final dateOnly = DateTime(record.date.year, record.date.month, record.date.day);
      if (dailyDetails.containsKey(dateOnly)) {
        dailyDetails[dateOnly]!.upload += record.upload;
        dailyDetails[dateOnly]!.download += record.download;
      } else {
        dailyDetails[dateOnly] = DailyTrafficData(
          upload: record.upload,
          download: record.download,
        );
      }
    }

    return ListView.builder(
      itemCount: sortedEntries.length,
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];
        final date = entry.key;
        final totalBytes = entry.value;
        final details = dailyDetails[date];

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 1,
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              child: Icon(
                Icons.data_usage,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              '${date.year}/${date.month}/${date.day}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            subtitle: details != null ? Row(
              children: [
                Expanded(
                  child: Text(
                    '↑${_formatBytes(details.upload)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '↓${_formatBytes(details.download)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ) : null,
            trailing: Text(
              _formatBytes(totalBytes),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('流量趋势'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTrafficLog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadTrafficLog,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _records.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('暂无流量数据', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                                : Column(
                  children: [
                    // 上方1/2空间：趋势图
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.trending_up, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  '流量趋势图',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_groupTrafficByDay().length} 天数据',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _buildTrendChart(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // 下方1/2空间：流量记录列表
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 8.0),
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.list, color: Theme.of(context).colorScheme.secondary),
                                const SizedBox(width: 8),
                                Text(
                                  '流量记录',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.secondary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_groupTrafficByDay().length} 天记录',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _buildDailyTrafficList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
} 