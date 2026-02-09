import 'package:flutter/material.dart';

class FinanceAlert {
  const FinanceAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
}
