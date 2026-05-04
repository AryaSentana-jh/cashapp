import 'package:supabase_flutter/supabase_flutter.dart' hide Transaction;
import 'package:flutter/foundation.dart';
import '../models/transaction.dart';

class SupabaseHelper {
  static final SupabaseHelper _instance = SupabaseHelper._internal();
  factory SupabaseHelper() => _instance;
  SupabaseHelper._internal();

  final _client = Supabase.instance.client;

  // Insert a new transaction
  Future<void> insertTransaction(Transaction transaction) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      final map = transaction.toMap();
      map['user_id'] = userId; // Associate with the logged-in user

      await _client.from('transactions').insert(map);
    } catch (e) {
      debugPrint('Error inserting transaction: $e');
      rethrow; // Rethrow to let the UI show an error if needed
    }
  }

  // Get all transactions (newest first)
  Future<List<Transaction>> getTransactions() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final data = await _client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('date', ascending: false);

      return (data as List).map((map) => Transaction.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error getting transactions: $e');
      return [];
    }
  }

  // Delete a transaction by id
  Future<void> deleteTransaction(String id) async {
    try {
      await _client.from('transactions').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      rethrow;
    }
  }

  // Delete all transactions for the current user
  Future<void> deleteAllTransactions() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;
      await _client.from('transactions').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('Error deleting all transactions: $e');
      rethrow;
    }
  }

  // Budget Plans Methods
  Future<void> insertBudgetPlan(double income, double savingGoal, String recommendation) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      debugPrint('Saving budget plan: userId=$userId, income=$income, saving=$savingGoal, rec=${recommendation.substring(0, recommendation.length > 50 ? 50 : recommendation.length)}...');

      await _client.from('budget_plans').upsert({
        'user_id': userId,
        'income': income,
        'saving_goal': savingGoal,
        'recommendation': recommendation,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      debugPrint('Budget plan saved successfully!');
    } catch (e) {
      debugPrint('Error inserting budget plan to Supabase: $e');
      rethrow;
    }
  }


  Future<Map<String, dynamic>?> getLatestBudgetPlan() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final data = await _client
          .from('budget_plans')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      return data;
    } catch (e) {
      debugPrint('Error getting latest budget plan from Supabase: $e');
      return null;
    }
  }
}

