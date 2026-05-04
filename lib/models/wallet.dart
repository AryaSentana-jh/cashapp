import 'package:flutter/material.dart';

class Wallet {
  final String id;
  final String name;
  final String iconName;
  final int colorValue;

  const Wallet({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconName': iconName,
        'colorValue': colorValue,
      };

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: json['id'] as String,
        name: json['name'] as String,
        iconName: json['iconName'] as String? ?? 'wallet',
        colorValue: json['colorValue'] as int? ?? 0xFF1960A3,
      );

  IconData get icon => walletIconMap[iconName] ?? Icons.account_balance_wallet_rounded;
  Color get color => Color(colorValue);
}

const Map<String, IconData> walletIconMap = {
  'wallet':       Icons.account_balance_wallet_rounded,
  'credit_card':  Icons.credit_card_rounded,
  'phone':        Icons.phone_android_rounded,
  'savings':      Icons.savings_rounded,
  'bank':         Icons.account_balance_rounded,
  'store':        Icons.store_rounded,
  'cash':         Icons.payments_rounded,
  'shopping':     Icons.shopping_bag_rounded,
  'business':     Icons.business_center_rounded,
  'star':         Icons.star_rounded,
  'home':         Icons.home_rounded,
  'work':         Icons.work_rounded,
  'travel':       Icons.flight_rounded,
  'food':         Icons.restaurant_rounded,
  'health':       Icons.local_hospital_rounded,
  'education':    Icons.school_rounded,
  'game':         Icons.sports_esports_rounded,
  'gift':         Icons.card_giftcard_rounded,
};
