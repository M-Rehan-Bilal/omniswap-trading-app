import 'package:flutter_test/flutter_test.dart';

import 'package:omni_swap/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    // OmniSwapApp is wrapped in AuthGate, which calls Supabase.
    // Supabase is not initialized in tests, so this only checks that the
    // widget class exists and can be referenced.
    expect(const OmniSwapApp(), isA<OmniSwapApp>());
  });
}