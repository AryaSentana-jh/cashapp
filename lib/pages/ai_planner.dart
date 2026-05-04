import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../main.dart';
import '../helpers/supabase_helper.dart';
import 'dart:convert';

class AiPlannerTab extends StatefulWidget {
  const AiPlannerTab({super.key});

  @override
  State<AiPlannerTab> createState() => _AiPlannerTabState();
}

class _AiPlannerTabState extends State<AiPlannerTab> {
  final TextEditingController _incomeController = TextEditingController();
  final TextEditingController _savingController = TextEditingController();
  
  String _aiRecommendation = '';
  double _lastIncome = 0;
  double _lastSaving = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLatestPlan();
    currencyNotifier.addListener(_onCurrencyChanged);
  }

  @override
  void dispose() {
    currencyNotifier.removeListener(_onCurrencyChanged);
    _incomeController.dispose();
    _savingController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    final currency = currencyNotifier.value;
    final rate = exchangeRates[currency] ?? 1.0;
    setState(() {
      _incomeController.text = NumberFormat('#,###').format((_lastIncome * rate).round());
      _savingController.text = NumberFormat('#,###').format((_lastSaving * rate).round());
    });
  }

  Map<String, dynamic> _getParsedRecommendation() {
    if (_aiRecommendation.isEmpty || _aiRecommendation == 'DEMO') return {};
    try {
      String cleanJson = _aiRecommendation;
      // Extract everything between the first '{' and the last '}'
      int firstBracket = cleanJson.indexOf('{');
      int lastBracket = cleanJson.lastIndexOf('}');
      if (firstBracket != -1 && lastBracket != -1) {
        cleanJson = cleanJson.substring(firstBracket, lastBracket + 1);
      } else if (cleanJson.contains('```json')) {
        cleanJson = cleanJson.split('```json')[1].split('```')[0];
      } else if (cleanJson.contains('```')) {
        cleanJson = cleanJson.split('```')[1].split('```')[0];
      }
      return jsonDecode(cleanJson.trim());
    } catch (e) {
      debugPrint('Error parsing AI recommendation: $e');
      return {};
    }
  }

  final String _openRouterKey = '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';
  final String _googleApiKey = 'AIzaSyAaH7fYpmBHbEA1A4swsHJhb_zOjF0HFEw';



  Future<void> _loadLatestPlan() async {
    final plan = await SupabaseHelper().getLatestBudgetPlan();
    if (plan != null) {
      final currency = currencyNotifier.value;
      final rate = exchangeRates[currency] ?? 1.0;

      setState(() {
        _lastIncome = (plan['income'] as num).toDouble();
        _lastSaving = (plan['saving_goal'] as num).toDouble();
        _aiRecommendation = plan['recommendation'];
        _incomeController.text = NumberFormat('#,###').format((_lastIncome * rate).round());
        _savingController.text = NumberFormat('#,###').format((_lastSaving * rate).round());
      });
    }
  }

  Future<void> _generatePlan() async {
    final currency = currencyNotifier.value;
    final rate = exchangeRates[currency] ?? 1.0;

    final incomeStr = _incomeController.text.replaceAll(',', '');
    final savingStr = _savingController.text.replaceAll(',', '');
    
    // Convert current currency input back to base (PHP)
    final income = (double.tryParse(incomeStr) ?? 0) / rate;
    final saving = (double.tryParse(savingStr) ?? 0) / rate;

    if (income <= 0 || saving < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid income and saving goals.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

      final prompt = 'I have a monthly income of $currency${_incomeController.text} and my goal is to save $currency${_savingController.text} this month. '
          'Please give me a detailed, practical budget breakdown for the remaining amount. '
          'Return ONLY a valid JSON object. Do not include markdown formatting, code blocks, or extra text. '
          'JSON Keys: "food_percent", "food_tips", "transport_percent", "transport_tips", "others_percent", "others_tips". '
          'Ensure percentages add up to 100.';

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openRouterKey',
        },
        body: jsonEncode({
          'model': 'deepseek/deepseek-chat-v3-0324',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'max_tokens': 512,
          'temperature': 0.7,
        }),
      );

      String text = '';
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        text = json['choices']?[0]?['message']?['content'] ?? '';
        debugPrint('AI Planner raw response: $text');
      } else {
        debugPrint('AI Planner API error (${response.statusCode}): ${response.body}');
      }

      // If API fails or returns invalid, we use our Demo logic
      if (text.isEmpty || text.contains('not found')) {
        text = 'DEMO';
      }

      // Clean the response: extract JSON from markdown code blocks if present
      if (text != 'DEMO') {
        int firstBrace = text.indexOf('{');
        int lastBrace = text.lastIndexOf('}');
        if (firstBrace != -1 && lastBrace != -1) {
          text = text.substring(firstBrace, lastBrace + 1);
        }
        debugPrint('AI Planner cleaned JSON: $text');
      }

      try {
        await SupabaseHelper().insertBudgetPlan(income, saving, text);
        debugPrint('AI Planner saved to Supabase: income=$income, saving=$saving');
      } catch (saveError) {
        debugPrint('Failed to save to Supabase: $saveError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Warning: Strategy generated but failed to save: $saveError')));
        }
      }
      
      setState(() {
        _lastIncome = income;
        _lastSaving = saving;
        _aiRecommendation = text;
      });
    } catch (e) {
      // Use Demo Mode on error
      debugPrint('AI Planner error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Error: $e')));
      }
      setState(() {
        _lastIncome = income;
        _lastSaving = saving;
        _aiRecommendation = 'DEMO';
      });

    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  Widget _buildSummaryHeader(bool isDark, String currency, double rate) {
    final remain = (_lastIncome - _lastSaving) * rate;
    final progress = _lastIncome > 0 ? (_lastSaving / _lastIncome) : 0.0;
    final displayIncome = _lastIncome * rate;
    final displaySaving = _lastSaving * rate;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? [const Color(0xFF1A365D), const Color(0xFF0F172A)] : [const Color(0xFF1E40AF), const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DAILY ALLOWANCE', style: TextStyle(color: Colors.blue.shade100, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Text('$currency ${NumberFormat('#,###').format((remain / 30).round())}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text('Savings Goal: ${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSimpleStat('Income', '$currency ${NumberFormat('#,###').format(displayIncome.round())}'),
              _buildSimpleStat('Goal', '$currency ${NumberFormat('#,###').format(displaySaving.round())}'),
              _buildSimpleStat('Spending', '$currency ${NumberFormat('#,###').format(remain.round())}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.blue.shade100, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildBreakdownCard(String title, double amount, String tips, IconData icon, Color color, bool isDark, String currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('$currency ${NumberFormat('#,###').format(amount)}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(tips, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<String>(
      valueListenable: currencyNotifier,
      builder: (context, currencyValue, child) {
        final rate = exchangeRates[currencyValue] ?? 1.0;
        final remain = (_lastIncome - _lastSaving) * rate;

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget Planner', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('AI-powered financial assistant', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                      const SizedBox(height: 24),
                      _buildSummaryHeader(isDark, currencyValue, rate),
                      const SizedBox(height: 32),
                      
                      // Input Form
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _incomeController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Monthly Income',
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                              ),
                              onChanged: (val) {
                                String raw = val.replaceAll(',', '');
                                if (raw.isNotEmpty) {
                                  try {
                                    String formatted = NumberFormat('#,###').format(int.parse(raw));
                                    if (val != formatted) {
                                      _incomeController.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                                    }
                                  } catch (e) {}
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _savingController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Saving Goal',
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                              ),
                              onChanged: (val) {
                                String raw = val.replaceAll(',', '');
                                if (raw.isNotEmpty) {
                                  try {
                                    String formatted = NumberFormat('#,###').format(int.parse(raw));
                                    if (val != formatted) {
                                      _savingController.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                                    }
                                  } catch (e) {}
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _generatePlan,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Generate New Strategy', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      Text('DAILY STRATEGY', style: TextStyle(color: isDark ? Colors.blue.shade200 : Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 16),
                      
                      if (remain > 0) ...[
                        (() {
                          final parsed = _getParsedRecommendation();
                          
                          // AI returns percentages like 40, 20, 40
                          // If it returns fractions like 0.4, 0.2, 0.4, we handle that too
                          double getMultiplier(dynamic val, double fallback) {
                            if (val == null) return fallback;
                            double v = (val as num).toDouble();
                            if (v > 1) return v / 100;
                            return v;
                          }

                          final foodMult = getMultiplier(parsed['food_percent'], 0.4);
                          final foodTips = parsed['food_tips'] as String? ?? 'Cook at home, limit eating out.';
                          
                          final transportMult = getMultiplier(parsed['transport_percent'], 0.2);
                          final transportTips = parsed['transport_tips'] as String? ?? 'Use public transport or carpool.';
                          
                          final othersMult = getMultiplier(parsed['others_percent'], 0.4);
                          final othersTips = parsed['others_tips'] as String? ?? 'Bills, emergency fund, and utilities.';

                          return Column(
                            children: [
                              _buildBreakdownCard('Food & Drinks', remain * foodMult, foodTips, Icons.restaurant, Colors.orange, isDark, currencyValue),
                              _buildBreakdownCard('Transport', remain * transportMult, transportTips, Icons.directions_bus, Colors.blue, isDark, currencyValue),
                              _buildBreakdownCard('Essentials', remain * othersMult, othersTips, Icons.shopping_bag, Colors.green, isDark, currencyValue),
                            ],
                          );
                        })(),
                      ] else ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 48, color: Colors.amber[600]),
                                const SizedBox(height: 16),
                                Text('Input your income and savings goal to generate a strategy.', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
