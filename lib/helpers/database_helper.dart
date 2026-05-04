import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/transaction.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database?> get database async {
    if (_database != null) return _database!;
    try {
      _database = await _initDatabase();
    } catch (e) {
      debugPrint('Database not supported on this platform. Falling back to memory-only.');
    }
    return _database;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'cashapp.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions(
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            description TEXT NOT NULL,
            date TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE budget_plans(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            income REAL NOT NULL,
            saving_goal REAL NOT NULL,
            recommendation TEXT NOT NULL,
            date TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE budget_plans(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              income REAL NOT NULL,
              saving_goal REAL NOT NULL,
              recommendation TEXT NOT NULL,
              date TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  // Budget Plans Methods
  Future<void> insertBudgetPlan(double income, double savingGoal, String recommendation) async {
    try {
      final db = await database;
      if (db == null) return;
      await db.insert(
        'budget_plans',
        {
          'income': income,
          'saving_goal': savingGoal,
          'recommendation': recommendation,
          'date': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error inserting budget plan: $e');
    }
  }

  Future<Map<String, dynamic>?> getLatestBudgetPlan() async {
    try {
      final db = await database;
      if (db == null) return null;
      final maps = await db.query(
        'budget_plans',
        orderBy: 'date DESC',
        limit: 1,
      );
      if (maps.isNotEmpty) return maps.first;
      return null;
    } catch (e) {
      debugPrint('Error getting latest budget plan: $e');
      return null;
    }
  }

  // Insert a new transaction
  Future<void> insertTransaction(Transaction transaction) async {
    try {
      final db = await database;
      if (db == null) return;
      await db.insert(
        'transactions',
        transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error inserting transaction: $e');
    }
  }

  // Get all transactions (newest first)
  Future<List<Transaction>> getTransactions() async {
    try {
      final db = await database;
      if (db == null) return [];
      final maps = await db.query(
        'transactions',
        orderBy: 'date DESC',
      );
      return maps.map((map) => Transaction.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error getting transactions: $e');
      return [];
    }
  }

  // Delete a transaction by id
  Future<void> deleteTransaction(String id) async {
    try {
      final db = await database;
      if (db == null) return;
      await db.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
    }
  }

  // Delete all transactions
  Future<void> deleteAllTransactions() async {
    try {
      final db = await database;
      if (db == null) return;
      await db.delete('transactions');
    } catch (e) {
      debugPrint('Error deleting all transactions: $e');
    }
  }
}
