import 'package:flutter/material.dart';

/// Palette "Summer Sky". The app uses only these colours.
abstract final class AppColors {
  /// Swatch 1: deep blue. Buttons, links, focus, headings, header.
  static const Color primary = Color(0xFF0A27C8);

  /// Swatch 4: yellow. Logo circle, header divider, badges.
  static const Color accent = Color(0xFFFCF300);

  /// Text and icons placed on [primary].
  static const Color onPrimary = Colors.white;
}