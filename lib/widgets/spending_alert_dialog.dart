import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/spending_notifier.dart';
import '../main.dart';

/// Premium notification dialog that shows spending alerts
class SpendingAlertDialog extends StatefulWidget {
  final SpendingAlert alert;
  final VoidCallback? onGoToPlanner;

  const SpendingAlertDialog({
    super.key,
    required this.alert,
    this.onGoToPlanner,
  });

  /// Show the dialog with animation
  static Future<void> show(BuildContext context, SpendingAlert alert, {VoidCallback? onGoToPlanner}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SpendingAlert',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SpendingAlertDialog(alert: alert, onGoToPlanner: onGoToPlanner);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curve,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<SpendingAlertDialog> createState() => _SpendingAlertDialogState();
}

class _SpendingAlertDialogState extends State<SpendingAlertDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alert = widget.alert;
    final currency = currencyNotifier.value;
    final rate = exchangeRates[currency] ?? 1.0;

    // Colors based on severity
    final Map<String, List<Color>> gradientColors = {
      'info': [const Color(0xFF1E88E5), const Color(0xFF1565C0)],
      'warning': [const Color(0xFFFFA726), const Color(0xFFEF6C00)],
      'danger': [const Color(0xFFEF5350), const Color(0xFFC62828)],
      'critical': [const Color(0xFFD32F2F), const Color(0xFF7B1FA2)],
    };

    final Map<String, IconData> severityIcons = {
      'info': Icons.info_rounded,
      'warning': Icons.warning_amber_rounded,
      'danger': Icons.error_rounded,
      'critical': Icons.dangerous_rounded,
    };

    final colors = gradientColors[alert.severity] ?? gradientColors['info']!;
    final icon = severityIcons[alert.severity] ?? Icons.info_rounded;

    final displaySpent = alert.totalSpent * rate;
    final displayBudget = alert.spendingBudget * rate;
    final displaySaving = alert.savingGoal * rate;
    final progress = (alert.totalSpent / alert.spendingBudget).clamp(0.0, 1.5);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colors[0].withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  child: Column(
                    children: [
                      // Pulsing icon
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: Colors.white, size: 40),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        alert.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        alert.message,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Spending progress bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pengeluaran',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${alert.thresholdPercent}%',
                            style: TextStyle(
                              color: colors[0],
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress > 1.0 ? Colors.red : colors[0],
                          ),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Spending details
                      _buildDetailRow(
                        'Sudah Digunakan',
                        '$currency ${NumberFormat('#,###').format(displaySpent.round())}',
                        colors[0],
                        isDark,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Budget Tersedia',
                        '$currency ${NumberFormat('#,###').format(displayBudget.round())}',
                        isDark ? Colors.grey[400]! : Colors.grey[600]!,
                        isDark,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? colors[0].withOpacity(0.1)
                              : colors[0].withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors[0].withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.savings_rounded, color: colors[0], size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Saving Goal',
                                    style: TextStyle(
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    '$currency ${NumberFormat('#,###').format(displaySaving.round())}',
                                    style: TextStyle(
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // AI Tip
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF8F9FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💡', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                alert.tip,
                                style: TextStyle(
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(
                                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                                ),
                              ),
                              child: Text(
                                'OK, Mengerti',
                                style: TextStyle(
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onGoToPlanner?.call();
                              },
                              icon: const Icon(Icons.auto_awesome, size: 18),
                              label: const Text(
                                'AI Planner',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors[0],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
