import 'package:supabase_flutter/supabase_flutter.dart';

/// An error the user can read. The message is shown as-is.
class OfferException implements Exception {
  const OfferException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OfferService {
  OfferService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Sends one offer for a whole post, giving [itemIds] from your inventory.
  /// The database checks everything again (ownership, availability and the
  /// post owner's wants). Returns the new offer id.
  Future<String> createOffer({
    required String postId,
    required List<String> itemIds,
  }) async {
    if (itemIds.isEmpty) {
      throw const OfferException('Choose at least one item to offer.');
    }

    try {
      final offerId = await _client.rpc('create_offer', params: {
        'p_post_id': postId,
        'p_item_ids': itemIds,
      });
      return offerId as String;
    } on PostgrestException catch (e) {
      throw OfferException(_messageFor(e));
    }
  }

  /// Errors raised by our SQL function (code P0001) carry readable messages.
  static String _messageFor(PostgrestException e) {
    if (e.code == 'P0001' && e.message.isNotEmpty) return e.message;
    if (e.code == '23505') {
      return 'You already have a pending offer on this post.';
    }
    return 'Something went wrong. Please try again.';
  }
}