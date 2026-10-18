import 'package:flutter/material.dart';

const _icons = <String, IconData>{
  'restaurant': Icons.restaurant_rounded,
  'directions_bus': Icons.directions_bus_rounded,
  'home': Icons.home_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'health': Icons.favorite_rounded,
  'school': Icons.school_rounded,
  'celebration': Icons.celebration_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'savings': Icons.savings_rounded,
  'pets': Icons.pets_rounded,
  'category': Icons.category_rounded,
};

IconData iconFor(String? name) => _icons[name] ?? Icons.category_rounded;

Color colorFromHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return const Color(0xFF78909C);
  return Color(int.parse(hex.replaceFirst('#', '0xFF')));
}
