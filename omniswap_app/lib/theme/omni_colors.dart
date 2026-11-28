import 'package:flutter/material.dart';

// Shared colours for the light OmniSwap design. Screens import these through
// home_screen.dart (which re-exports this file), so existing imports still work.
const Color kOmniYellow = Color(0xFFFFE01B);
const Color kOmniInk = Color(0xFF1B2433);
const Color kOmniMuted = Color(0xFF8A94A6);
const Color kOmniBg = Color(0xFFF4F7FB);

// Summer Sky accents, used for card borders and photo placeholders.
const Color kOmniBlue = Color(0xFF1F5CFF);
const Color kOmniGold = Color(0xFFF2C94C);

// Surfaces and outlines. Use these instead of Colors.white or raw hex values.
const Color kOmniSurface = Color(0xFFFFFFFF);
const Color kOmniBorder = Color(0xFFD9E0EA);

// Selected state for pickable cards (e.g. items chosen for an offer).
const Color kOmniSelectedBg = Color(0xFFE6EEFF);

// Small pills such as the condition chip.
const Color kOmniChipBg = Color(0xFFE3EAF3);

// Error states (e.g. "this user isn't accepting that offer").
const Color kOmniError = Color(0xFFD64545);
const Color kOmniErrorBg = Color(0xFFFDECEC);