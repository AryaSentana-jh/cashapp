import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/transaction.dart';
import 'supabase_helper.dart';

/// Data class representing a spending notification alert
class SpendingAlert {
  final double totalSpent;
  final double spendingBudget;
  final double savingGoal;
  final double income;
  final int thresholdPercent;
  final String severity; // 'info', 'warning', 'danger', 'critical'
  final String title;
  final String message;
  final String tip;
  final DateTime createdAt;

  SpendingAlert({
    required this.totalSpent,
    required this.spendingBudget,
    required this.savingGoal,
    required this.income,
    required this.thresholdPercent,
    required this.severity,
    required this.title,
    required this.message,
    required this.tip,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'totalSpent': totalSpent,
        'spendingBudget': spendingBudget,
        'savingGoal': savingGoal,
        'income': income,
        'thresholdPercent': thresholdPercent,
        'severity': severity,
        'title': title,
        'message': message,
        'tip': tip,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SpendingAlert.fromJson(Map<String, dynamic> json) => SpendingAlert(
        totalSpent: (json['totalSpent'] as num).toDouble(),
        spendingBudget: (json['spendingBudget'] as num).toDouble(),
        savingGoal: (json['savingGoal'] as num).toDouble(),
        income: (json['income'] as num).toDouble(),
        thresholdPercent: json['thresholdPercent'] as int,
        severity: json['severity'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        tip: json['tip'] as String,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Service that monitors spending and generates alerts based on AI Planner budget
class SpendingNotifier {
  static final SpendingNotifier _instance = SpendingNotifier._internal();
  factory SpendingNotifier() => _instance;
  SpendingNotifier._internal() {
    _loadPersistedNotifications();
  }

  // Threshold levels (percentage of spending budget used)
  static const List<int> thresholds = [25, 50, 75, 90, 100];
  static const String _notifKey = 'spending_notifications_v2';
  static const String _alertKey = 'spending_alert_threshold';

  // Notification history for the bell icon — persisted
  final ValueNotifier<List<SpendingAlert>> notifications = ValueNotifier([]);

  // ─── Persistence ─────────────────────────────────────────────────────────

  Future<void> _loadPersistedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_notifKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => SpendingAlert.fromJson(e as Map<String, dynamic>))
            .toList();
        notifications.value = list;
      }
    } catch (e) {
      debugPrint('SpendingNotifier: failed to load notifications: $e');
    }
  }

  Future<void> _persistNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _notifKey,
        jsonEncode(notifications.value.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('SpendingNotifier: failed to save notifications: $e');
    }
  }

  // ─── Core check (called after every transaction save) ────────────────────

  /// Checks spending against budget. Returns an alert if a NEW threshold
  /// is crossed since the last time we showed one for this % band.
  Future<SpendingAlert?> checkSpendingThreshold(
      List<Transaction> transactions) async {
    try {
      // 1. Get budget plan
      final plan = await SupabaseHelper().getLatestBudgetPlan();
      if (plan == null) {
        debugPrint('SpendingNotifier: No budget plan found');
        return null;
      }

      final double income = (plan['income'] as num).toDouble();
      final double savingGoal = (plan['saving_goal'] as num).toDouble();
      final double spendingBudget = income - savingGoal;
      if (spendingBudget <= 0) return null;

      // 2. Calculate current month cashOut
      final now = DateTime.now();
      final monthlyExpenses = transactions
          .where((t) =>
              t.type == TransactionType.cashOut &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold(0.0, (sum, t) => sum + t.amount);

      final double percentUsed = (monthlyExpenses / spendingBudget) * 100;

      // 3. Determine which threshold band we are in (5 bands: 0-25, 25-50, 50-75, 75-90, 90-100, 100+)
      //    We re-trigger when spending crosses a new 10% step ABOVE any previous threshold.
      //    This uses a "last-notified-percent" approach with 10% steps so it can fire
      //    multiple times once past 100%.
      final prefs = await SharedPreferences.getInstance();
      final monthKey = '${_alertKey}_${now.year}_${now.month}';
      final lastNotifiedPercent = prefs.getInt(monthKey) ?? 0;

      // Find next 10%-multiple above lastNotifiedPercent that we've crossed
      // Min step is 10 so we don't spam
      int? newTrigger;
      // Check standard thresholds first (25, 50, 75, 90, 100)
      for (final t in thresholds) {
        if (percentUsed >= t && lastNotifiedPercent < t) {
          newTrigger = t;
        }
      }
      // After 100% — trigger every extra 25% over budget
      if (percentUsed >= 100) {
        final extra = ((percentUsed - 100) / 25).floor() * 25 + 100;
        if (extra > lastNotifiedPercent) {
          newTrigger = extra;
        }
      }

      if (newTrigger == null) return null;

      // 4. Save the new high watermark
      await prefs.setInt(monthKey, newTrigger);

      // 5. Build and store alert
      final alert = _buildAlert(
        totalSpent: monthlyExpenses,
        spendingBudget: spendingBudget,
        savingGoal: savingGoal,
        income: income,
        thresholdPercent: newTrigger > 100 ? newTrigger : newTrigger,
        overBudgetPercent: newTrigger,
      );

      final current = List<SpendingAlert>.from(notifications.value);
      current.insert(0, alert);
      if (current.length > 20) current.removeLast();
      notifications.value = current;
      await _persistNotifications();

      return alert;
    } catch (e) {
      debugPrint('SpendingNotifier error: $e');
      return null;
    }
  }

  /// Get current spending status (for budget status card)
  Future<Map<String, double>?> getSpendingStatus(
      List<Transaction> transactions) async {
    try {
      final plan = await SupabaseHelper().getLatestBudgetPlan();
      if (plan == null) return null;

      final double income = (plan['income'] as num).toDouble();
      final double savingGoal = (plan['saving_goal'] as num).toDouble();
      final double spendingBudget = income - savingGoal;
      if (spendingBudget <= 0) return null;

      final now = DateTime.now();
      final monthlyExpenses = transactions
          .where((t) =>
              t.type == TransactionType.cashOut &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold(0.0, (sum, t) => sum + t.amount);

      return {
        'spent': monthlyExpenses,
        'budget': spendingBudget,
        'saving_goal': savingGoal,
        'income': income,
        'percent': (monthlyExpenses / spendingBudget * 100).clamp(0, 9999),
      };
    } catch (e) {
      debugPrint('SpendingNotifier status error: $e');
      return null;
    }
  }

  /// Reset threshold history for current month (for testing / manual reset)
  Future<void> resetMonthlyThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.remove('${_alertKey}_${now.year}_${now.month}');
  }

  /// Clear notification history (bell icon)
  Future<void> clearNotifications() async {
    notifications.value = [];
    await _persistNotifications();
  }

  // ─── Alert builder ────────────────────────────────────────────────────────

  SpendingAlert _buildAlert({
    required double totalSpent,
    required double spendingBudget,
    required double savingGoal,
    required double income,
    required int thresholdPercent,
    required int overBudgetPercent,
  }) {
    String severity;
    String title;
    String message;
    String tip;

    if (overBudgetPercent > 100) {
      final overshoot = overBudgetPercent - 100;
      severity = 'critical';
      title = '🚨 Over Budget +$overshoot%!';
      message = 'Pengeluaranmu sudah $overBudgetPercent% dari budget bulanan!';
      tip = 'Saving goal tidak tercapai. Tinjau pengeluaranmu di AI Planner dan potong pengeluaran yang tidak penting. 💡';
    } else {
      switch (thresholdPercent) {
        case 25:
          severity = 'info';
          title = '📊 25% Budget Terpakai';
          message = 'Kamu sudah menggunakan 25% dari budget bulananmu.';
          tip = 'Awal yang baik! Tetap jaga pengeluaranmu. Saving goal masih aman. 💪';
          break;
        case 50:
          severity = 'warning';
          title = '⚠️ Setengah Budget Terpakai!';
          message = 'Kamu sudah menggunakan 50% dari budget bulananmu.';
          tip = 'Ingat saving goal kamu! Coba kurangi pengeluaran yang tidak perlu. 🎯';
          break;
        case 75:
          severity = 'warning';
          title = '🔶 Budget Hampir Habis!';
          message = 'Kamu sudah menggunakan 75% dari budget bulananmu!';
          tip = 'Hati-hati! Sisa budget tinggal sedikit. Prioritaskan kebutuhan penting saja. ⚡';
          break;
        case 90:
          severity = 'danger';
          title = '🔴 Budget Kritis!';
          message = 'Kamu sudah menggunakan 90% dari budget bulananmu!';
          tip = 'Saving goal kamu terancam! Hindari pengeluaran tambahan kecuali darurat. 🚨';
          break;
        case 100:
        default:
          severity = 'critical';
          title = '🚨 Budget Terlampaui!';
          message = 'Kamu sudah melebihi budget bulananmu!';
          tip = 'Saving goal kamu tidak tercapai bulan ini. Evaluasi pengeluaranmu di AI Planner! 💡';
      }
    }

    return SpendingAlert(
      totalSpent: totalSpent,
      spendingBudget: spendingBudget,
      savingGoal: savingGoal,
      income: income,
      thresholdPercent: thresholdPercent,
      severity: severity,
      title: title,
      message: message,
      tip: tip,
    );
  }
}
