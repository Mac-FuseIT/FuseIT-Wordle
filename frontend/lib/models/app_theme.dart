import 'package:flutter/material.dart';

class AppTheme {
  final String name;
  final Color background;
  final Color correct;
  final Color present;
  final Color absent;
  final Color tileEmpty;
  final Color keyDefault;
  final Color textColor;

  const AppTheme({
    required this.name,
    required this.background,
    required this.correct,
    required this.present,
    required this.absent,
    required this.tileEmpty,
    required this.keyDefault,
    required this.textColor,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'background': background.value,
    'correct': correct.value,
    'present': present.value,
    'absent': absent.value,
    'tileEmpty': tileEmpty.value,
    'keyDefault': keyDefault.value,
    'textColor': textColor.value,
  };

  factory AppTheme.fromJson(Map<String, dynamic> json) => AppTheme(
    name: json['name'] ?? 'default',
    background: Color(json['background']),
    correct: Color(json['correct']),
    present: Color(json['present']),
    absent: Color(json['absent']),
    tileEmpty: Color(json['tileEmpty']),
    keyDefault: Color(json['keyDefault']),
    textColor: Color(json['textColor']),
  );

  static const defaultTheme = AppTheme(
    name: 'Default Dark',
    background: Color(0xFF121213),
    correct: Color(0xFF6AAA64),
    present: Color(0xFFC9B458),
    absent: Color(0xFF3A3A3C),
    tileEmpty: Color(0xFF121213),
    keyDefault: Color(0xFF818384),
    textColor: Color(0xFFFFFFFF),
  );

  static const oceanTheme = AppTheme(
    name: 'Ocean',
    background: Color(0xFF0A1929),
    correct: Color(0xFF00BCD4),
    present: Color(0xFFFF9800),
    absent: Color(0xFF1E3A5F),
    tileEmpty: Color(0xFF0A1929),
    keyDefault: Color(0xFF5C7A99),
    textColor: Color(0xFFE0F7FA),
  );

  static const forestTheme = AppTheme(
    name: 'Forest',
    background: Color(0xFF1B2D1B),
    correct: Color(0xFF4CAF50),
    present: Color(0xFFFFEB3B),
    absent: Color(0xFF2E4A2E),
    tileEmpty: Color(0xFF1B2D1B),
    keyDefault: Color(0xFF6B8E6B),
    textColor: Color(0xFFE8F5E9),
  );

  static const sunsetTheme = AppTheme(
    name: 'Sunset',
    background: Color(0xFF1A0A2E),
    correct: Color(0xFFE91E63),
    present: Color(0xFFFF5722),
    absent: Color(0xFF2D1B4E),
    tileEmpty: Color(0xFF1A0A2E),
    keyDefault: Color(0xFF7B5EA7),
    textColor: Color(0xFFF3E5F5),
  );

  static const lightTheme = AppTheme(
    name: 'Light',
    background: Color(0xFFF5F5F5),
    correct: Color(0xFF6AAA64),
    present: Color(0xFFC9B458),
    absent: Color(0xFF787C7E),
    tileEmpty: Color(0xFFFFFFFF),
    keyDefault: Color(0xFFD3D6DA),
    textColor: Color(0xFF1A1A1B),
  );

  static const hackerTheme = AppTheme(
    name: 'Hacker',
    background: Color(0xFF0D0D0D),
    correct: Color(0xFF00FF00),
    present: Color(0xFF00CC00),
    absent: Color(0xFF1A1A1A),
    tileEmpty: Color(0xFF0D0D0D),
    keyDefault: Color(0xFF333333),
    textColor: Color(0xFF00FF00),
  );

  static const allThemes = [defaultTheme, oceanTheme, forestTheme, sunsetTheme, lightTheme, hackerTheme];
}
