enum TransactionType { cashIn, cashOut }

class Transaction {
  final String id;
  final TransactionType type;
  final double amount;
  final String description;
  final DateTime date;
  final String category;
  final String wallet;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
    this.category = 'Other',
    this.wallet = 'Personal',
  });

  // Convert to a Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type == TransactionType.cashIn ? 'cashIn' : 'cashOut',
      'amount': amount,
      'description': description,
      'date': date.toIso8601String(),
      'category': category,
      'wallet': wallet,
    };
  }

  // Create a Transaction from a database Map
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as String,
      type: map['type'] == 'cashIn'
          ? TransactionType.cashIn
          : TransactionType.cashOut,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String,
      date: DateTime.parse(map['date'] as String),
      category: map['category'] as String? ?? 'Other',
      wallet: map['wallet'] as String? ?? 'Personal',
    );
  }
}
