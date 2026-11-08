import '../main.dart' show supabase;

/// Creates a post for one of your items, plus the models you want in return.
Future<String> createPost({
  required String itemId,
  required List<String> wantedModels,
  bool acceptsOutsideWants = false,
}) async {
  final me = supabase.auth.currentUser!.id;

  final post = await supabase
      .from('posts')
      .insert({
    'item_id': itemId,
    'owner_id': me,
    'accepts_outside_wants': acceptsOutsideWants,
  })
      .select()
      .single();

  final postId = post['id'] as String;

  if (wantedModels.isNotEmpty) {
    await supabase.from('wants').insert([
      for (final model in wantedModels) {'post_id': postId, 'model_name': model},
    ]);
  }

  return postId;
}