import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../helpers/supabase_helper.dart';
import '../helpers/spending_notifier.dart';
import '../widgets/report_chart_card.dart';
import '../widgets/spending_alert_dialog.dart';
import '../main.dart';
import 'package:intl/intl.dart';
import 'setting.dart';
import 'add_transaction.dart';
import 'add_wallet.dart';
import 'ai_planner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _filters = ['All', 'Daily', 'Weekly', 'Monthly', 'Yearly'];
  int _selectedFilterIndex = 0;
  final List<Transaction> _transactions = [];
  final SupabaseHelper _dbHelper = SupabaseHelper();
  bool _isLoading = true;
  bool _isBalanceHidden = false;
  String _selectedWalletFilter = 'All';

  int _bottomNavIndex = 0;
  final SpendingNotifier _spendingNotifier = SpendingNotifier();

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final transactions = await _dbHelper.getTransactions();
    if (!mounted) return;
    setState(() {
      _transactions.clear();
      _transactions.addAll(transactions);
      _isLoading = false;
    });
    // Check spending alert AFTER transactions are loaded into state
    _checkSpendingAlert();
  }

  Future<void> _checkSpendingAlert() async {
    final alert = await _spendingNotifier.checkSpendingThreshold(_transactions);
    if (alert != null && mounted) {
      // Small delay to let the UI settle
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      SpendingAlertDialog.show(
        context,
        alert,
        onGoToPlanner: () {
          setState(() => _bottomNavIndex = 3); // Navigate to AI Planner tab
        },
      );
    }
  }

  void _showNotificationPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currency = currencyNotifier.value;
    final rate = exchangeRates[currency] ?? 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ValueListenableBuilder<List<SpendingAlert>>(
        valueListenable: _spendingNotifier.notifications,
        builder: (ctx, alerts, _) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Notifikasi Budget',
                        style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        // Reset & re-check button
                        IconButton(
                          tooltip: 'Cek ulang budget sekarang',
                          icon: Icon(Icons.refresh_rounded,
                              color: const Color(0xFF1960A3), size: 22),
                          onPressed: () async {
                            await _spendingNotifier.resetMonthlyThreshold();
                            final alert = await _spendingNotifier.checkSpendingThreshold(_transactions);
                            if (!mounted) return;
                            Navigator.pop(ctx);
                            if (alert != null) {
                              SpendingAlertDialog.show(context, alert,
                                  onGoToPlanner: () => setState(() => _bottomNavIndex = 3));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Spending masih di bawah threshold atau AI Planner belum di-set.'),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          },
                        ),
                        if (alerts.isNotEmpty)
                          TextButton(
                            onPressed: () => _spendingNotifier.clearNotifications(),
                            child: const Text('Hapus', style: TextStyle(color: Color(0xFF1960A3))),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (alerts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : const Color(0xFFF0F4FA),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.notifications_off_rounded, size: 36, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 16),
                      Text('Belum ada notifikasi',
                          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Notifikasi muncul saat budget\nmencapai 25%, 50%, 75%, 90%, 100%+',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[500], fontSize: 12)),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: alerts.length,
                    itemBuilder: (ctx2, i) {
                      final alert = alerts[i];
                      final colorMap = {
                        'info': const Color(0xFF1E88E5),
                        'warning': const Color(0xFFFFA726),
                        'danger': const Color(0xFFEF5350),
                        'critical': const Color(0xFFD32F2F),
                      };
                      final color = colorMap[alert.severity] ?? Colors.blue;
                      final displaySpent  = alert.totalSpent * rate;
                      final displayBudget = alert.spendingBudget * rate;
                      final diff = DateTime.now().difference(alert.createdAt);
                      final timeStr = diff.inMinutes < 1 ? 'Baru saja'
                          : diff.inHours < 1 ? '${diff.inMinutes}m lalu'
                          : diff.inHours < 24 ? '${diff.inHours}j lalu'
                          : DateFormat('d MMM').format(alert.createdAt);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF8F9FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: color.withOpacity(0.25)),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(
                                        color: color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12)),
                                    child: Icon(
                                      alert.thresholdPercent >= 100 ? Icons.dangerous_rounded
                                          : alert.thresholdPercent >= 75 ? Icons.error_rounded
                                          : alert.thresholdPercent >= 50 ? Icons.warning_amber_rounded
                                          : Icons.info_rounded,
                                      color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(child: Text(alert.title,
                                                style: TextStyle(
                                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                    fontWeight: FontWeight.bold, fontSize: 13))),
                                            Text(timeStr, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$currency ${NumberFormat('#,###').format(displaySpent.round())} / ${NumberFormat('#,###').format(displayBudget.round())}',
                                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20)),
                                    child: Text('${alert.thresholdPercent}%',
                                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                              child: LinearProgressIndicator(
                                value: (alert.thresholdPercent / 100).clamp(0.0, 1.0),
                                backgroundColor: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    final currency = currencyNotifier.value;
    final rate = exchangeRates[currency] ?? 1.0;
    double converted = amount * rate;
    
    final formatter = NumberFormat('#,##0.00', 'en_US');
    if (converted == converted.toInt().toDouble()) {
      final intFormatter = NumberFormat('#,##0', 'en_US');
      return '$currency ${intFormatter.format(converted.toInt())}';
    }
    return '$currency ${formatter.format(converted)}';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  List<Transaction> get _filteredTransactions {
    final now = DateTime.now();
    List<Transaction> result;
    switch (_selectedFilterIndex) {
      case 1: // Daily
        result = _transactions.where((t) =>
            t.date.year == now.year &&
            t.date.month == now.month &&
            t.date.day == now.day).toList();
        break;
      case 2: // Weekly
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        result = _transactions.where((t) => t.date.isAfter(weekStartDate.subtract(const Duration(seconds: 1)))).toList();
        break;
      case 3: // Monthly
        result = _transactions.where((t) =>
            t.date.year == now.year && t.date.month == now.month).toList();
        break;
      case 4: // Yearly
        result = _transactions.where((t) => t.date.year == now.year).toList();
        break;
      default: // All
        result = List.from(_transactions);
    }
    // Apply wallet filter
    if (_selectedWalletFilter != 'All') {
      result = result.where((t) => t.wallet == _selectedWalletFilter).toList();
    }
    return result;
  }

  void _showDeleteConfirmation(Transaction transaction) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Transaction', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text(
          'Delete "${transaction.description}" — ${_formatAmount(transaction.amount)}?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _dbHelper.deleteTransaction(transaction.id);
              if (!mounted) return;
              setState(() {
                _transactions.removeWhere((t) => t.id == transaction.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Transaction deleted'),
                  backgroundColor: Colors.grey[700],
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredTransactions;
    final currency = currencyNotifier.value;
    
    // Filter transaksi hanya dari wallet yang terdaftar saat "All" dipilih
    // Ini mencegah transaksi lama (wallet "Personal"/orphan) merusak total balance
    final knownWalletNames = walletsNotifier.value.map((w) => w.name).toSet();
    final effectiveTransactions = _selectedWalletFilter == 'All'
        ? _filteredTransactions.where((t) => knownWalletNames.contains(t.wallet)).toList()
        : _filteredTransactions;

    final filteredCashIn  = effectiveTransactions.where((t) => t.type == TransactionType.cashIn).fold(0.0, (s, t) => s + t.amount);
    final filteredCashOut = effectiveTransactions.where((t) => t.type == TransactionType.cashOut).fold(0.0, (s, t) => s + t.amount);
    final filteredBalance = filteredCashIn - filteredCashOut;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // BALANCE CARD
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A365D), Color(0xFF00477F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                if (!isDark) BoxShadow(color: const Color(0xFF00477F).withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL NET WORTH',
                      style: TextStyle(color: Colors.blue.shade200, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _isBalanceHidden = !_isBalanceHidden),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Icon(
                          _isBalanceHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          key: ValueKey(_isBalanceHidden),
                          color: Colors.blue.shade200,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _isBalanceHidden
                      ? Text(
                          '••••••',
                          key: const ValueKey('hidden'),
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4),
                        )
                      : Text(
                          _formatAmount(filteredBalance),
                          key: const ValueKey('visible'),
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: -1),
                        ),
                ),
                // Sub-info: income/expense mini row
                if (!_isBalanceHidden) ...
                  [
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.arrow_upward, color: Colors.greenAccent.shade200, size: 14),
                        const SizedBox(width: 4),
                        Text(_formatAmount(filteredCashIn),
                            style: TextStyle(color: Colors.greenAccent.shade200, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 16),
                        Icon(Icons.arrow_downward, color: Colors.red.shade200, size: 14),
                        const SizedBox(width: 4),
                        Text(_formatAmount(filteredCashOut),
                            style: TextStyle(color: Colors.red.shade200, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const TransactionPage()));
                      if (result == true) _loadTransactions();
                    },
                    icon: const Icon(Icons.add, color: Color(0xFF1960A3)),
                    label: const Text('Add Transaction', style: TextStyle(color: Color(0xFF1960A3), fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // WALLET FILTER CHIPS
          ValueListenableBuilder<List<Wallet>>(
            valueListenable: walletsNotifier,
            builder: (context, wallets, _) {
              final options = ['All', ...wallets.map((w) => w.name)];
              return SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final label = options[i];
                    final isSelected = _selectedWalletFilter == label;
                    Wallet? wObj;
                    if (i > 0) {
                      wObj = wallets.firstWhere((w) => w.name == label, orElse: () => wallets.first);
                    }
                    return GestureDetector(
                      onTap: () => setState(() => _selectedWalletFilter = label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (wObj != null ? wObj.color : const Color(0xFF1960A3))
                              : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : (isDark ? Colors.grey[800]! : const Color(0xFFE0E0E0)),
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(
                                  color: (wObj != null ? wObj.color : const Color(0xFF1960A3)).withOpacity(0.3),
                                  blurRadius: 8, offset: const Offset(0, 3))]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (wObj != null) ...
                              [
                                Icon(wObj.icon,
                                    color: isSelected ? Colors.white : wObj.color,
                                    size: 14),
                                const SizedBox(width: 6),
                              ],
                            if (i == 0 && isSelected)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.wallet, color: Colors.white, size: 14),
                              ),
                            Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.grey[300] : const Color(0xFF43474E)),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          
          // STATS BENTO GRID
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFF1960A3)),
                      const SizedBox(height: 8),
                      Text(
                        _selectedWalletFilter == 'All' ? 'Income' : '${_selectedWalletFilter} In',
                        style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isBalanceHidden ? '••••' : '+${_formatAmount(filteredCashIn)}',
                        style: const TextStyle(color: Color(0xFF1960A3), fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.trending_down, color: Color(0xFFBA1A1A)),
                      const SizedBox(height: 8),
                      Text(
                        _selectedWalletFilter == 'All' ? 'Expenses' : '${_selectedWalletFilter} Out',
                        style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isBalanceHidden ? '••••' : '-${_formatAmount(filteredCashOut)}',
                        style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // CHART SECTION
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Spending Insights', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Performance overview', style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 14)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1960A3).withOpacity(0.2) : const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedFilterIndex,
                          isDense: true,
                          icon: const Icon(Icons.expand_more, size: 16, color: Color(0xFF1960A3)),
                          style: const TextStyle(color: Color(0xFF1960A3), fontSize: 12, fontWeight: FontWeight.bold),
                          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          items: _filters.asMap().entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                          onChanged: (val) { if (val != null) setState(() => _selectedFilterIndex = val); },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 220,
                  decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(16)),
                  child: ReportChartCard(transactions: filtered),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // TOP CATEGORIES
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Top Categories', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 18, fontWeight: FontWeight.w600)),
              TextButton(onPressed: () {}, child: const Text('See All', style: TextStyle(color: Color(0xFF1960A3), fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(32.0), child: Text('No transactions found', style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]))))
          else
            ...filtered.take(5).map((t) {
              final isCashIn = t.type == TransactionType.cashIn;
              double percentage = 0.0;
              if (isCashIn && filteredCashIn > 0) {
                percentage = t.amount / filteredCashIn;
              } else if (!isCashIn && filteredCashOut > 0) {
                percentage = t.amount / filteredCashOut;
              }
              if (percentage > 1.0) percentage = 1.0;
              
              return GestureDetector(
                onLongPress: () => _showDeleteConfirmation(t),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: isCashIn ? const Color(0xFFFFDDBA) : const Color(0xFFD3E4FF), borderRadius: BorderRadius.circular(12)),
                        child: Icon(isCashIn ? Icons.restaurant : Icons.home_rounded, color: isCashIn ? const Color(0xFF321B00) : const Color(0xFF1960A3)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.description, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Stack(
                              children: [
                                Container(height: 6, decoration: BoxDecoration(color: isDark ? Colors.grey[800] : const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(3))),
                                Container(height: 6, width: MediaQuery.of(context).size.width * 0.4 * percentage, decoration: BoxDecoration(color: const Color(0xFF1960A3), borderRadius: BorderRadius.circular(3))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatAmount(t.amount), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('${(percentage * 100).toInt()}% of ${isCashIn ? 'Income' : 'Expenses'}', style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildWalletTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<List<Wallet>>(
      valueListenable: walletsNotifier,
      builder: (context, wallets, _) {
        // Hanya hitung transaksi dari wallet yang terdaftar
        // Transaksi orphan (wallet lama) tidak ikut dihitung
        final knownWalletNames = wallets.map((w) => w.name).toSet();
        final Map<String, double> walletBalances = {for (var w in wallets) w.name: 0.0};
        for (var t in _transactions) {
          if (!knownWalletNames.contains(t.wallet)) continue; // skip orphan
          final delta = t.type == TransactionType.cashIn ? t.amount : -t.amount;
          walletBalances[t.wallet] = (walletBalances[t.wallet] ?? 0) + delta;
        }
        // Total hanya dari wallet yang terdaftar (konsisten dengan overview "All")
        final totalBalance = wallets.fold(0.0, (s, w) => s + (walletBalances[w.name] ?? 0));

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── HEADER ──────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('My Wallets',
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0D1C2E),
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  ValueListenableBuilder<String>(
                    valueListenable: currencyNotifier,
                    builder: (context, currency, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1960A3).withOpacity(0.2) : const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currency,
                          isDense: true,
                          icon: const Icon(Icons.expand_more, size: 16, color: Color(0xFF1960A3)),
                          style: const TextStyle(color: Color(0xFF1960A3), fontSize: 16, fontWeight: FontWeight.bold),
                          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          items: ['₱', '\$', '€', '£', '¥', 'Rp']
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (val) { if (val != null) currencyNotifier.value = val; },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── TOTAL BALANCE CARD ───────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1A365D), Color(0xFF00477F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(color: const Color(0xFF00477F).withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL SALDO',
                        style: TextStyle(color: Colors.blue.shade200, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    Text(_formatAmount(totalBalance),
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('${wallets.length} wallet aktif',
                        style: TextStyle(color: Colors.blue.shade200, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text('Semua Wallet',
                  style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0D1C2E),
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              // ── DAFTAR WALLET ─────────────────────────────
              if (wallets.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 56, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text('Belum ada wallet',
                            style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400], fontSize: 16)),
                        const SizedBox(height: 6),
                        Text('Tap "+" untuk tambah wallet baru',
                            style: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[500], fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else
                ...wallets.map((wallet) {
                  final balance = walletBalances[wallet.name] ?? 0;
                  final txCount = _transactions.where((t) => t.wallet == wallet.name).length;
                  return GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => AddWalletPage(wallet: wallet)));
                      if (result == true) setState(() {});
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                                color: wallet.color, borderRadius: BorderRadius.circular(16)),
                            child: Icon(wallet.icon, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(wallet.name,
                                    style: TextStyle(
                                        color: isDark ? Colors.white : const Color(0xFF0D1C2E),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('$txCount transaksi',
                                    style: TextStyle(
                                        color: isDark ? Colors.grey[500] : const Color(0xFF43474E),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatAmount(balance),
                                style: TextStyle(
                                    color: balance >= 0
                                        ? (isDark ? Colors.white : const Color(0xFF0D1C2E))
                                        : Colors.red,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: wallet.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text('Edit',
                                    style: TextStyle(
                                        color: wallet.color, fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInsightsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currency = currencyNotifier.value;
    final Map<String, double> categoryExpenses = {};
    double totalExpense = 0;
    
    for (var t in _filteredTransactions.where((t) => t.type == TransactionType.cashOut)) {
      categoryExpenses[t.category] = (categoryExpenses[t.category] ?? 0) + t.amount;
      totalExpense += t.amount;
    }

    final sortedCategories = categoryExpenses.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Insights', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 24, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: isDark ? const Color(0xFF1960A3).withOpacity(0.2) : const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedFilterIndex,
                    isDense: true,
                    icon: const Icon(Icons.expand_more, size: 16, color: Color(0xFF1960A3)),
                    style: const TextStyle(color: Color(0xFF1960A3), fontSize: 12, fontWeight: FontWeight.bold),
                    dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    items: _filters.asMap().entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                    onChanged: (val) { if (val != null) setState(() => _selectedFilterIndex = val); },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('Total Expenses', style: TextStyle(color: isDark ? Colors.grey[400] : const Color(0xFF43474E), fontSize: 14)),
                const SizedBox(height: 8),
                Text(_formatAmount(totalExpense), style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                if (sortedCategories.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: sortedCategories.map((e) {
                        final colors = [const Color(0xFF1960A3), const Color(0xFF6B9DFA), const Color(0xFF8FCDFF), const Color(0xFFBA1A1A), const Color(0xFFFF897D), Colors.grey];
                        final index = sortedCategories.indexOf(e);
                        return Expanded(
                          flex: (e.value / totalExpense * 100).toInt() > 0 ? (e.value / totalExpense * 100).toInt() : 1,
                          child: Container(height: 12, color: colors[index % colors.length]),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...sortedCategories.map((e) {
                    final colors = [const Color(0xFF1960A3), const Color(0xFF6B9DFA), const Color(0xFF8FCDFF), const Color(0xFFBA1A1A), const Color(0xFFFF897D), Colors.grey];
                    final index = sortedCategories.indexOf(e);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[index % colors.length], shape: BoxShape.circle)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(e.key, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontWeight: FontWeight.w500))),
                          Text(_formatAmount(e.value), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }),
                ] else
                  Padding(padding: const EdgeInsets.all(16), child: Text('No expenses to analyze', style: TextStyle(color: Colors.grey[500]))),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'User';
    
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profile', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: isDark ? Colors.grey[800] : const Color(0xFFD3E4FF),
                  radius: 40,
                  child: Icon(Icons.person, size: 40, color: isDark ? Colors.blue.shade200 : const Color(0xFF1960A3)),
                ),
                const SizedBox(height: 16),
                Text(email, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Pro Member', style: TextStyle(color: Color(0xFF1960A3), fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildProfileOption(Icons.settings, 'Settings', () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingPage()));
          }),
          _buildProfileOption(Icons.help_outline, 'Help & Support', () {}),
          _buildProfileOption(Icons.security, 'Security', () {}),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
            },
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildProfileOption(IconData icon, String title, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: isDark ? Colors.grey[800] : const Color(0xFFF0F4FA), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: isDark ? Colors.grey[300] : const Color(0xFF43474E), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0D1C2E), fontSize: 16, fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right, color: isDark ? Colors.grey[600] : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: currencyNotifier,
      builder: (context, currencyValue, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        String displayName = 'WealthTrack';
        final currentUserEmail = Supabase.instance.client.auth.currentUser?.email;
        if (currentUserEmail != null && currentUserEmail.contains('@')) {
          final namePart = currentUserEmail.split('@')[0];
          if (namePart.isNotEmpty) {
            displayName = namePart[0].toUpperCase() + namePart.substring(1);
          }
        }

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FF),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(color: Color(0xFF1960A3)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 30,
                        child: Icon(Icons.person, size: 35, color: Color(0xFF1960A3)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        Supabase.instance.client.auth.currentUser?.email ?? 'User',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingPage()));
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
                  },
                ),
              ],
            ),
          ),
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF121212).withOpacity(0.8) : Colors.white.withOpacity(0.8),
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
            leading: Builder(
              builder: (context) => GestureDetector(
                onTap: () => Scaffold.of(context).openDrawer(),
                child: Container(
                  margin: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD3E4FF), width: 2),
                    color: const Color(0xFFD6E3FF),
                  ),
                  child: const Icon(Icons.person, color: Color(0xFF1960A3)),
                ),
              ),
            ),
            title: Text(
              displayName,
              style: TextStyle(
                color: isDark ? Colors.blue.shade200 : const Color(0xFF002045),
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
            actions: [
              ValueListenableBuilder<List<SpendingAlert>>(
                valueListenable: _spendingNotifier.notifications,
                builder: (context, alerts, _) {
                  return Stack(
                    children: [
                      IconButton(
                        icon: Icon(Icons.notifications_none, color: isDark ? Colors.blue.shade200 : const Color(0xFF002045)),
                        onPressed: _showNotificationPanel,
                      ),
                      if (alerts.isNotEmpty)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5350),
                              shape: BoxShape.circle,
                              border: Border.all(color: isDark ? const Color(0xFF121212) : Colors.white, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                alerts.length > 9 ? '9+' : '${alerts.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          floatingActionButton: _bottomNavIndex == 1
              ? FloatingActionButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const AddWalletPage()));
                    if (result == true) setState(() {});
                  },
                  backgroundColor: const Color(0xFF1960A3),
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
          body: SafeArea(
            child: IndexedStack(
              index: _bottomNavIndex,
              children: [
                _buildOverviewTab(),
                _buildWalletTab(),
                _buildInsightsTab(),
                const AiPlannerTab(),
                _buildProfileTab(),
              ],
            ),
          ),
          extendBody: true,
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: BottomNavigationBar(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  type: BottomNavigationBarType.fixed,
                  currentIndex: _bottomNavIndex,
                  selectedItemColor: const Color(0xFF1960A3),
                  unselectedItemColor: isDark ? Colors.grey[600] : Colors.grey[400],
                  selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
                  onTap: (index) => setState(() => _bottomNavIndex = index),
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
                    BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
                    BottomNavigationBarItem(icon: Icon(Icons.analytics_rounded), label: 'Insights'),
                    BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'AI Planner'),
                    BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
