import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';

class ReportChartCard extends StatelessWidget {
  final List<Transaction> transactions;

  const ReportChartCard({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // We will show a 7-day performance curve like the design
    List<FlSpot> spots = [];
    double maxY = 0.0;
    double minY = 0.0;
    
    // Group transactions by date
    Map<String, double> netFlowByDate = {};
    for (var t in transactions) {
      String dateKey = DateFormat('yyyy-MM-dd').format(t.date);
      netFlowByDate[dateKey] = (netFlowByDate[dateKey] ?? 0) + (t.type == TransactionType.cashIn ? t.amount : -t.amount);
    }

    var sortedDates = netFlowByDate.keys.toList()..sort();
    
    if (sortedDates.isEmpty) {
      // Dummy data to exactly match the design's beautiful curve
      spots = const [
        FlSpot(0, 20), FlSpot(1, 25), FlSpot(2, 22), FlSpot(3, 45),
        FlSpot(4, 75), FlSpot(5, 30), FlSpot(6, 80),
      ];
      maxY = 100;
      minY = 0;
    } else {
      double currentBalance = 0;
      for (int i = 0; i < sortedDates.length; i++) {
        currentBalance += netFlowByDate[sortedDates[i]]!;
        spots.add(FlSpot(i.toDouble(), currentBalance));
      }
      
      // If only one day of data, add a start point to make a line
      if (spots.length == 1) {
        spots.insert(0, FlSpot(-1, 0));
        sortedDates.insert(0, DateFormat('yyyy-MM-dd').format(DateTime.parse(sortedDates[0]).subtract(const Duration(days: 1))));
      }

      maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      if (maxY == minY) {
        maxY += 100;
        minY -= 100;
      }
    }

    final color = const Color(0xFF1960A3);

    return LineChart(
      LineChartData(
        clipData: const FlClipData.none(),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (sortedDates.isEmpty) {
                  // Fallback for dummy data
                  if (index < 0 || index > 6) return const SizedBox();
                  DateTime date = now.subtract(Duration(days: 6 - index));
                  return Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: Text(DateFormat('EEE').format(date), style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 12)),
                  );
                }

                if (index < 0 || index >= sortedDates.length) return const SizedBox();
                
                // Show at most 4 labels to prevent overlapping
                if (sortedDates.length > 5) {
                  if (index != 0 && index != sortedDates.length - 1 && index != sortedDates.length ~/ 2) {
                    return const SizedBox();
                  }
                }
                
                DateTime date = DateTime.parse(sortedDates[index]);
                String label = sortedDates.length > 7 ? DateFormat('MMM d').format(date) : DateFormat('EEE').format(date);
                
                return Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(
                    label,
                    style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: spots.first.x,
        maxX: spots.last.x,
        minY: minY < 0 ? minY * 1.2 : 0,
        maxY: maxY > 0 ? maxY * 1.2 : 100,
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.2),
                  color.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
