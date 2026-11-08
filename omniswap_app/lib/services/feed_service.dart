import '../main.dart' show supabase;

/// Active posts, with their item, images, and wanted models.
Future<List<Map<String, dynamic>>> fetchActivePosts() async {
  final rows = await supabase
      .from('posts')
      .select(
    'id, owner_id, accepts_outside_wants, created_at, '
        'items(id, title, description, model_name, item_condition, '
        'item_images(storage_key, position)), '
        'wants(model_name)',
  )
      .eq('status', 'active')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
}

/// Display names and ratings for a list of user IDs.
Future<Map<String, Map<String, dynamic>>> fetchProfiles(List<String> ids) async {
  if (ids.isEmpty) return {};
  final rows = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url, rating')
      .inFilter('id', ids);
  return {for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)};
}