import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_config.dart';
import '../common/http_client.dart';
import '../models/traffic_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

class TrafficLogPage extends ConsumerStatefulWidget {
  const TrafficLogPage({super.key});

  @override
  ConsumerState<TrafficLogPage> createState() => _TrafficLogPageState();
}

class _TrafficLogPageState extends ConsumerState<TrafficLogPage> {
  bool _isLoading = true;
  List<TrafficRecord> _records = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrafficLog();
  }

  Future<void> _loadTrafficLog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwtToken = prefs.getString('jwt_token');
      if (jwtToken == null) {
        setState(() {
          _error = '未登录';
          _isLoading = false;
        });
        return;
      }

      final response = await HttpClient.get(
        Uri.parse('${AppConfig.baseUrl}/api/v1/user/stat/getTrafficLog'),
        headers: {
          'Authorization': jwtToken,
          'User-Agent': AppConfig.userAgent,
        },
        timeout: const Duration(seconds: 8),
        retries: 3,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final List<dynamic> recordsJson = data['data'];
          setState(() {
            _records = recordsJson
                .map((json) => TrafficRecord.fromJson(json))
                .toList();
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = '获取数据失败';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = '获取数据失败: ${response.statusCode}';
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

  LineChartData _getLineChartData() {
    final grouped = groupedTraffic(_records);
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = sortedEntries.map((e) {
      final x = e.key.millisecondsSinceEpoch.toDouble();
      final y = e.value / 1e9; // 转 GB
      return FlSpot(x, y);
    }).toList();

    // 计算平均使用量
    double averageUsage = 0;
    if (spots.isNotEmpty) {
      averageUsage =
          spots.map((e) => e.y).reduce((a, b) => a + b) / spots.length;
    }

    // 计算Y轴间隔（平均使用量的1/10）
    final yInterval = (averageUsage / 10).toDouble();
    // 确保最小间隔为0.1
    final adjustedYInterval = yInterval < 0.1 ? 0.1 : yInterval;

    // 计算Y轴最大值（向上取整到最近的间隔）
    final maxY = spots.isEmpty
        ? 10.0
        : (spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) /
                    adjustedYInterval)
                .ceil() *
            adjustedYInterval;

    return LineChartData(
      lineBarsData: [
        LineChartBarData(
          isCurved: true,
          spots: spots,
          color: Colors.blueAccent,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: Colors.blueAccent,
                strokeWidth: 2,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                Colors.blueAccent.withOpacity(0.3),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        )
      ],
      titlesData: FlTitlesData(
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            interval: const Duration(days: 2).inMilliseconds.toDouble(),
            getTitlesWidget: (value, _) {
              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "${date.month}/${date.day}",
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 60,
            interval: adjustedYInterval,
            getTitlesWidget: (value, _) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                "${value.toStringAsFixed(1)} GB",
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: adjustedYInterval,
        verticalInterval: const Duration(days: 2).inMilliseconds.toDouble(),
      ),
      borderData: FlBorderData(show: false),
      minY: 0,
      maxY: maxY,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: Colors.blueGrey.withOpacity(0.8),
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final date =
                  DateTime.fromMillisecondsSinceEpoch(barSpot.x.toInt());
              return LineTooltipItem(
                '${date.year}/${date.month}/${date.day}\n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: '${barSpot.y.toStringAsFixed(2)} GB',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              );
            }).toList();
          },
        ),
        handleBuiltInTouches: true,
        getTouchedSpotIndicator:
            (LineChartBarData barData, List<int> spotIndexes) {
          return spotIndexes.map((spotIndex) {
            return TouchedSpotIndicatorData(
              FlLine(color: Colors.blueAccent, strokeWidth: 2),
              FlDotData(
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 6,
                    color: Colors.blueAccent,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
            );
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 设置窗口大小
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 只在初始化时设置窗口大小
      WidgetsBinding.instance.addPostFrameCallback((_) {
        windowManager.getSize().then((size) {
          if (size.width < 800) {
            windowManager.setSize(const Size(1000, 800));
          }
        });
      });
      windowManager.setMinimumSize(const Size(800, 800));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('流量记录'),
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
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '流量趋势',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: LineChart(_getLineChartData()),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
