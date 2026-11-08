import '../main.dart' show supabase;

/// Offers your items on someone else's post. Returns the new offer ID.
Future<String> makeOffer({
  required String postId,
  required List<String> myItemIds,
}) async {
  final offerId = await supabase.rpc('create_offer', params: {
    'p_post_id': postId,
    'p_item_ids': myItemIds,
  });
  return offerId as String;
}

/// Post owner accepts an offer. Returns the new trade ID.
Future<String> acceptOffer(String offerId) async {
  final tradeId = await supabase.rpc('accept_offer', params: {
    'p_offer_id': offerId,
  });
  return tradeId as String;
}

/// Post owner declines a pending offer.
Future<void> declineOffer(String offerId) async {
  await supabase.from('offers').update({
    'status': 'declined',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', offerId);
}

/// Offerer cancels their own pending offer.
Future<void> cancelOffer(String offerId) async {
  await supabase.from('offers').update({
    'status': 'cancelled',
    'responded_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', offerId);
}