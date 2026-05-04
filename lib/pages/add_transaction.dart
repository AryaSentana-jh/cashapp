import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../helpers/supabase_helper.dart';
import '../helpers/spending_notifier.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  TransactionType _selectedType = TransactionType.cashOut; // Default to Expense
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  
  String _selectedCategory = 'Food';
  DateTime _selectedDate = DateTime.now();
  String _selectedWallet = '';

  String get _effectiveWallet {
    if (_selectedWallet.isNotEmpty) return _selectedWallet;
    final wallets = walletsNotifier.value;
    return wallets.isNotEmpty ? wallets.first.name : 'Personal';
  }
  
  bool _isLoading = false;
  bool _isScanning = false;

  // Budget data (loaded once from AI Planner via Supabase)
  double? _budgetSpending;     // income - saving goal = spending budget
  double _monthlySpent = 0;    // current month cashOut total (base currency)

  @override
  void initState() {
    super.initState();
    _loadBudgetData();
    // Listen to amount changes for real-time budget preview
    _amountController.addListener(() => setState(() {}));
  }

  Future<void> _loadBudgetData() async {
    try {
      final plan = await SupabaseHelper().getLatestBudgetPlan();
      if (plan == null || !mounted) return;

      final income = (plan['income'] as num).toDouble();
      final saving = (plan['saving_goal'] as num).toDouble();
      final spending = income - saving;
      if (spending <= 0) return;

      // Get current month transactions for real spent amount
      final allTx = await SupabaseHelper().getTransactions();
      final now = DateTime.now();
      final spent = allTx
          .where((t) =>
              t.type == TransactionType.cashOut &&
              t.date.year == now.year &&
              t.date.month == now.month)
          .fold(0.0, (s, t) => s + t.amount);

      if (mounted) {
        setState(() {
          _budgetSpending  = spending;
          _monthlySpent    = spent;
        });
      }
    } catch (e) {
      debugPrint('Budget load error: $e');
    }
  }

  final List<Map<String, dynamic>> _expenseCategories = [
    {'name': 'Food', 'icon': Icons.restaurant, 'color': Colors.blue},
    {'name': 'Shop', 'icon': Icons.shopping_bag_outlined, 'color': Colors.indigo},
    {'name': 'Transport', 'icon': Icons.directions_car_outlined, 'color': Colors.indigo},
    {'name': 'Health', 'icon': Icons.medical_services_outlined, 'color': Colors.indigo},
    {'name': 'Game', 'icon': Icons.sports_esports_outlined, 'color': Colors.indigo},
    {'name': 'Bills', 'icon': Icons.receipt_long_outlined, 'color': Colors.indigo},
    {'name': 'Travel', 'icon': Icons.flight_outlined, 'color': Colors.indigo},
    {'name': 'Other', 'icon': Icons.more_horiz, 'color': Colors.indigo},
  ];

  final List<Map<String, dynamic>> _incomeCategories = [
    {'name': 'Incoming Transfer', 'icon': Icons.account_balance_wallet_outlined, 'color': Colors.green},
    {'name': 'Other Income', 'icon': Icons.attach_money, 'color': Colors.green},
    {'name': 'Salary', 'icon': Icons.work_outline, 'color': Colors.green},
  ];

  List<Map<String, dynamic>> get _categories => _selectedType == TransactionType.cashOut ? _expenseCategories : _incomeCategories;

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.replaceAll(',', '');
    final amount = double.tryParse(amountText);
    
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final rate = exchangeRates[currencyNotifier.value] ?? 1.0;
      final baseAmount = amount / rate;

      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: _selectedType,
        amount: baseAmount,
        description: _noteController.text.isEmpty ? _selectedCategory : _noteController.text,
        date: _selectedDate,
        category: _selectedCategory,
        wallet: _effectiveWallet,
      );

      await SupabaseHelper().insertTransaction(transaction);
      
      // Check spending threshold for cashOut transactions
      if (_selectedType == TransactionType.cashOut) {
        final allTransactions = await SupabaseHelper().getTransactions();
        await SpendingNotifier().checkSpendingThreshold(allTransactions);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Return true to signal refresh needed
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _showWalletPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ValueListenableBuilder<List<Wallet>>(
        valueListenable: walletsNotifier,
        builder: (ctx, wallets, _) {
          final current = _effectiveWallet;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Pilih Wallet',
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF002045),
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 16),
                if (wallets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('Belum ada wallet. Buat di tab Wallet.',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                else
                  ...wallets.map((wallet) => GestureDetector(
                        onTap: () {
                          setState(() => _selectedWallet = wallet.name);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: current == wallet.name
                                ? wallet.color.withOpacity(0.1)
                                : (isDark ? Colors.grey[850] : const Color(0xFFF8F9FF)),
                            borderRadius: BorderRadius.circular(14),
                            border: current == wallet.name
                                ? Border.all(color: wallet.color, width: 1.5)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                    color: wallet.color, borderRadius: BorderRadius.circular(10)),
                                child: Icon(wallet.icon, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(wallet.name,
                                    style: TextStyle(
                                        color: isDark ? Colors.white : const Color(0xFF0D1C2E),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15)),
                              ),
                              if (current == wallet.name)
                                Icon(Icons.check_circle_rounded, color: wallet.color, size: 22),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _scanReceipt() async {
    final picker = ImagePicker();
    
    // Ask user for camera or gallery
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan Receipt'),
        content: const Text('Choose image source:'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ImageSource.camera), child: const Text('Camera')),
          TextButton(onPressed: () => Navigator.pop(context, ImageSource.gallery), child: const Text('Gallery')),
        ],
      ),
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() => _isScanning = true);

    try {
      final openRouterKey = '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';
      final bytes = await pickedFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openRouterKey',
        },
        body: jsonEncode({
          'model': 'google/gemini-2.0-flash-001',
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'Extract the final total amount from this receipt/nota. '
                    'IMPORTANT: Indonesian receipts use dots as thousand separators (e.g. 30.000 means thirty thousand, NOT thirty point zero zero zero). '
                    'Return ONLY the plain integer number without any dots, commas, currency symbols, or text. '
                    'For example: if the total is Rp 30.000,00 or Rp30.000 return just: 30000'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  }
                }
              ]
            }
          ],
          'max_tokens': 100,
          'temperature': 0.1,
        }),
      );

      String text = '';
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        text = (json['choices']?[0]?['message']?['content'] ?? '').trim();
        debugPrint('AI Scan response: $text');
      } else {
        debugPrint('AI Scan error (${response.statusCode}): ${response.body}');
        if (!mounted) return;
        try {
          final errorJson = jsonDecode(response.body);
          final errorMsg = errorJson['error']?['message'] ?? 'Unknown API error (${response.statusCode})';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('API Error: $errorMsg')));
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('API Error: ${response.statusCode}')));
        }
        return;
      }

      // Parse the amount - handle various formats
      // Indonesian: 30.000,00 or 30.000
      // US: 30,000.00 or 30000
      String cleaned = text.replaceAll(RegExp(r'[^0-9.,]'), '');
      
      if (cleaned.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not extract amount. AI response: "$text"')));
        return;
      }

      double? amount;
      
      // Check if it uses Indonesian format (dots as thousands, comma as decimal)
      // e.g. "30.000,00" or "30.000"
      if (cleaned.contains('.') && cleaned.contains(',')) {
        // Has both dot and comma - determine format
        int lastDot = cleaned.lastIndexOf('.');
        int lastComma = cleaned.lastIndexOf(',');
        if (lastComma > lastDot) {
          // Indonesian format: 30.000,00 -> 30000.00
          cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
        } else {
          // US format: 30,000.00 -> 30000.00
          cleaned = cleaned.replaceAll(',', '');
        }
      } else if (cleaned.contains('.')) {
        // Only dots - check if it's thousands separator
        // "30.000" (Indonesian for 30,000) vs "30.50" (decimal)
        final parts = cleaned.split('.');
        if (parts.length > 1 && parts.last.length == 3) {
          // Groups of 3 after dot = thousands separator (Indonesian)
          cleaned = cleaned.replaceAll('.', '');
        }
        // Otherwise keep as-is (it's a decimal point)
      } else if (cleaned.contains(',')) {
        // Only commas - likely thousands separator
        cleaned = cleaned.replaceAll(',', '');
      }
      
      amount = double.tryParse(cleaned);
      
      if (amount != null && amount > 0) {
        final formatted = NumberFormat('#,###', 'en_US').format(amount.round());
        setState(() {
          _amountController.value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Amount extracted: $formatted')));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not extract amount. AI response: "$text"')));
      }



    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryBlue = const Color(0xFF002045);
    final lightBg = const Color(0xFFF8F9FF);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : primaryBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add Transaction',
          style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveTransaction,
            child: Text(
              'Save',
              style: TextStyle(color: isDark ? Colors.blue.shade200 : primaryBlue, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Expense / Income Toggle
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F4FA),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedType != TransactionType.cashOut) {
                          setState(() {
                            _selectedType = TransactionType.cashOut;
                            _selectedCategory = _expenseCategories.first['name'];
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedType == TransactionType.cashOut ? (isDark ? Colors.grey[800] : Colors.white) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedType == TransactionType.cashOut
                              ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Expense',
                          style: TextStyle(
                            color: _selectedType == TransactionType.cashOut 
                              ? (isDark ? Colors.white : primaryBlue) 
                              : Colors.grey[500],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedType != TransactionType.cashIn) {
                          setState(() {
                            _selectedType = TransactionType.cashIn;
                            _selectedCategory = _incomeCategories.first['name'];
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedType == TransactionType.cashIn ? (isDark ? Colors.grey[800] : Colors.white) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedType == TransactionType.cashIn
                              ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Income',
                          style: TextStyle(
                            color: _selectedType == TransactionType.cashIn 
                              ? (isDark ? Colors.white : primaryBlue) 
                              : Colors.grey[500],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Amount Card
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('INSERT AMOUNT', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(width: 8),
                      if (_isScanning) 
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        GestureDetector(
                          onTap: _scanReceipt,
                          child: Icon(Icons.document_scanner, size: 18, color: primaryBlue),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: currencyNotifier,
                        builder: (context, currency, child) {
                          return DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: currency,
                              isDense: true,
                              icon: Icon(Icons.expand_more, size: 24, color: isDark ? Colors.white : primaryBlue),
                              style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 32, fontWeight: FontWeight.w600),
                              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                              items: ['₱', '\$', '€', '£', '¥', 'Rp'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (val) {
                                if (val != null) currencyNotifier.value = val;
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IntrinsicWidth(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 48, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '0.00',
                            hintStyle: TextStyle(color: Colors.grey[400]),
                          ),
                          onChanged: (val) {
                            String raw = val.replaceAll(',', '');
                            if (raw.isNotEmpty && !raw.endsWith('.')) {
                              final parts = raw.split('.');
                              if (parts.length <= 2 && parts[0].isNotEmpty) {
                                try {
                                  String formatted = NumberFormat('#,###', 'en_US').format(int.parse(parts[0]));
                                  if (parts.length == 2) {
                                    formatted += '.${parts[1]}';
                                  }
                                  if (val != formatted) {
                                    _amountController.value = TextEditingValue(
                                      text: formatted,
                                      selection: TextSelection.collapsed(offset: formatted.length),
                                    );
                                  }
                                } catch (e) {}
                              }
                            }
                            // Trigger rebuild to adjust width if necessary
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Main Details Card
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Category', style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('View All', style: TextStyle(color: const Color(0xFF1960A3), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Category Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat['name'];
                      
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat['name']),
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF6B9DFA) : (isDark ? Colors.grey[800] : const Color(0xFFE5EEFF)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                cat['icon'],
                                color: isSelected ? Colors.white : (isDark ? Colors.grey[400] : primaryBlue),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              cat['name'],
                              style: TextStyle(
                                color: isDark ? Colors.grey[300] : primaryBlue,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  Text('Write Note', style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : const Color(0xFFF0F4FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Add details about this transaction...',
                        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                      style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _selectDate(context),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[850] : const Color(0xFFF0F4FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, color: const Color(0xFF1960A3), size: 20),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('DATE', style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                                    Text(
                                      DateFormat('MMM, d yyyy').format(_selectedDate),
                                      style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showWalletPicker,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[850] : const Color(0xFFF0F4FA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                ValueListenableBuilder<List<Wallet>>(
                                  valueListenable: walletsNotifier,
                                  builder: (context, wallets, _) {
                                    final wObj = wallets.firstWhere(
                                      (w) => w.name == _effectiveWallet,
                                      orElse: () => Wallet(
                                          id: '', name: _effectiveWallet,
                                          iconName: 'wallet', colorValue: 0xFF1960A3),
                                    );
                                    return Container(
                                      width: 22, height: 22,
                                      decoration: BoxDecoration(
                                          color: wObj.color, borderRadius: BorderRadius.circular(6)),
                                      child: Icon(wObj.icon, color: Colors.white, size: 13),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('WALLET', style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold)),
                                      Text(
                                        _effectiveWallet,
                                        style: TextStyle(color: isDark ? Colors.white : primaryBlue, fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.expand_more, color: Colors.grey[500], size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            // Bottom Add Transaction Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveTransaction,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            
            const SizedBox(height: 16),
            // ── BUDGET STATUS CARD (real-time) ──────────
            ValueListenableBuilder<String>(
              valueListenable: currencyNotifier,
              builder: (context, currency, _) {
                final rate = exchangeRates[currency] ?? 1.0;

                // No budget plan set
                if (_budgetSpending == null) {
                  return Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFF1A365D),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('BUDGET STATUS', style: TextStyle(color: Colors.blue.shade200, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              const SizedBox(height: 4),
                              const Text('Set up AI Planner untuk mulai tracking budget', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Compute current values in display currency
                final budget     = _budgetSpending! * rate;
                final alreadySpent = _monthlySpent * rate;

                // How much user is about to add (in display currency)
                final rawInput = _amountController.text.replaceAll(',', '');
                final inputAmount = double.tryParse(rawInput) ?? 0.0;

                // Preview: spent after this transaction
                final previewSpent = _selectedType == TransactionType.cashOut
                    ? alreadySpent + inputAmount
                    : alreadySpent; // income doesn’t affect expense budget

                final percent       = (alreadySpent / budget * 100).clamp(0.0, 999.0);
                final previewPercent = (previewSpent / budget * 100).clamp(0.0, 999.0);
                final remaining     = budget - alreadySpent;
                final afterRemaining = budget - previewSpent;

                final bool hasInput = inputAmount > 0 && _selectedType == TransactionType.cashOut;

                Color barColor;
                List<Color> gradientColors;
                IconData statusIcon;
                String statusText;

                final displayPercent = hasInput ? previewPercent : percent;

                if (displayPercent >= 100) {
                  barColor = const Color(0xFFEF5350);
                  gradientColors = [const Color(0xFF7B1FA2), const Color(0xFFC62828)];
                  statusIcon = Icons.dangerous_rounded;
                  statusText = hasInput
                      ? '⚠️ Setelah ini: Budget terlampaui!'
                      : '🚨 Budget sudah terlampaui!';
                } else if (displayPercent >= 75) {
                  barColor = const Color(0xFFFFA726);
                  gradientColors = [const Color(0xFFE65100), const Color(0xFFF57C00)];
                  statusIcon = Icons.warning_amber_rounded;
                  statusText = hasInput
                      ? '⚠️ Setelah ini: ${previewPercent.toStringAsFixed(0)}% terpakai'
                      : '🔶 ${percent.toStringAsFixed(0)}% budget terpakai';
                } else if (displayPercent >= 50) {
                  barColor = const Color(0xFFFFCA28);
                  gradientColors = [const Color(0xFF1A365D), const Color(0xFF1565C0)];
                  statusIcon = Icons.info_rounded;
                  statusText = hasInput
                      ? '📅 Setelah ini: ${previewPercent.toStringAsFixed(0)}% terpakai'
                      : '📅 ${percent.toStringAsFixed(0)}% budget terpakai';
                } else {
                  barColor = const Color(0xFF66BB6A);
                  gradientColors = [const Color(0xFF1A365D), const Color(0xFF0D47A1)];
                  statusIcon = Icons.trending_up;
                  statusText = hasInput
                      ? '✅ Setelah ini: ${previewPercent.toStringAsFixed(0)}% terpakai'
                      : '✅ ${percent.toStringAsFixed(0)}% budget terpakai — on track!';
                }

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.last.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(statusIcon, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('BUDGET STATUS',
                                    style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                const SizedBox(height: 2),
                                Text(statusText,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Progress bar: current + preview overlay
                      Stack(
                        children: [
                          // Background track
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: 1.0,
                              backgroundColor: Colors.white.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.08)),
                              minHeight: 10,
                            ),
                          ),
                          // Already spent bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: (percent / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(barColor),
                              minHeight: 10,
                            ),
                          ),
                          // Preview delta bar (lighter, dashed feel)
                          if (hasInput && previewPercent > percent)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: (previewPercent / 100).clamp(0.0, 1.0),
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.45)),
                                minHeight: 10,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Numbers row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left: spent (+ preview)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$currency ${NumberFormat('#,###').format(alreadySpent.round())} spent',
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                              ),
                              if (hasInput)
                                Text(
                                  '+ $currency ${NumberFormat('#,###').format(inputAmount.round())} ini',
                                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 10),
                                ),
                            ],
                          ),
                          // Right: remaining / budget
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$currency ${NumberFormat('#,###').format(budget.round())} budget',
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                              ),
                              Text(
                                hasInput
                                    ? 'Sisa: $currency ${NumberFormat('#,###').format(afterRemaining.round())}'
                                    : 'Sisa: $currency ${NumberFormat('#,###').format(remaining.round())}',
                                style: TextStyle(
                                  color: afterRemaining < 0 ? Colors.red.shade200 : Colors.greenAccent.shade200,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
