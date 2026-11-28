import 'package:supabase_flutter/supabase_flutter.dart';

/// An error the user can read. The message is shown as-is.
class TradeActionException implements Exception {
  const TradeActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Actions on offers and trades. Each one calls a database function,
/// and the database checks the rules again on its side.
class TradeActionService {
  TradeActionService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Accepts an offer made to me. Returns the new trade id.
  Future<String> acceptOffer(String offerId) async {
    try {
      final tradeId = await _client.rpc(
        'accept_offer',
        params: {'p_offer_id': offerId},
      );
      return tradeId as String;
    } on PostgrestException catch (e) {
      throw TradeActionException(_messageFor(e));
    }
  }

  /// I received my items. Checks the other person's code and records my verification.
  /// Throws a readable error if the code is wrong.
  Future<void> verifyReceipt({
    required String tradeId,
    required String code,
  }) async {
    try {
      final matched = await _client.rpc('verify_trade_receipt', params: {
        'p_trade_id': tradeId,
        'p_code': code,
      });
      if (matched != true) {
        throw const TradeActionException(
          'That code does not match. Check it with the other person.',
        );
      }
    } on PostgrestException catch (e) {
      throw TradeActionException(_messageFor(e));
    }
  }

  /// Cancels an in-progress trade. [reason] must be a cancel_reason value.
  Future<void> cancelTrade({
    required String tradeId,
    required String reason,
  }) async {
    try {
      await _client.rpc('cancel_trade', params: {
        'p_trade_id': tradeId,
        'p_reason': reason,
      });
    } on PostgrestException catch (e) {
      throw TradeActionException(_messageFor(e));
    }
  }

  /// Errors raised by our SQL functions (code P0001) carry readable messages.
  static String _messageFor(PostgrestException e) {
    if (e.code == 'P0001' && e.message.isNotEmpty) return e.message;
    return 'Something went wrong. Please try again.';
  }
}