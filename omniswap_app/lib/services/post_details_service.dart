import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item_condition.dart';
import '../models/post_details.dart';
import '../models/post_listing.dart';

class PostDetailsService {
  PostDetailsService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _imageBucket = 'item-images';
  static const int _signedUrlSeconds = 60 * 60;

  // `wants` carries group_id so single wants and bundles can be told apart.
  static const String _postSelect = 'id, owner_id, accepts_outside_wants, '
      'items(id, title, description, item_condition, manufacture_year, '
      'item_images(position, storage_key)), '
      'wants(group_id, model_name, model_key)';

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Loads one active post with all its items, photos, wanted entries and
  /// owner. Returns null if the post does not exist or is no longer active.
  Future<PostDetails?> fetchPost(String postId) async {
    final row = await _client
        .from('posts')
        .select(_postSelect)
        .eq('id', postId)
        .eq('status', 'active')
        .maybeSingle();
    if (row == null) return null;

    // Same rule as the rest of the app: items sorted by title.
    final rawItems = _maps(row['items'])
      ..sort((a, b) => _lower(a['title']).compareTo(_lower(b['title'])));
    if (rawItems.isEmpty) return null;

    // Load every item, and all of its photos, at the same time.
    final items = await Future.wait(rawItems.map(_toItem));

    // Single wants and bundles, sorted by label.
    final bundles = WantBundle.fromRows(_maps(row['wants']));

    // public_profiles hides the phone number and email.
    final ownerId = row['owner_id'] as String;
    final ownerRow = await _client
        .from('public_profiles')
        .select('display_name, avatar_url, rating, country, area, city')
        .eq('id', ownerId)
        .single();

    // The phone number comes from a function that only returns it for
    // active posts, to signed-in users, or to a trade partner.
    // The owner does not need their own contact number, so skip the call.
    final isOwner = ownerId == currentUserId;
    final String? phone = isOwner
        ? null
        : (await _client.rpc(
      'get_post_contact',
      params: {'p_post_id': postId},
    )) as String?;

    return PostDetails(
      postId: row['id'] as String,
      ownerId: ownerId,
      owner: PostOwner(
        name: ownerRow['display_name'] as String,
        avatarUrl: ownerRow['avatar_url'] as String?,
        rating: (ownerRow['rating'] as num).toDouble(),
        country: ownerRow['country'] as String,
        area: ownerRow['area'] as String,
        city: ownerRow['city'] as String,
        phone: phone,
      ),
      acceptsOutsideWants: row['accepts_outside_wants'] as bool,
      items: items,
      wants: [for (final bundle in bundles) bundle.label],
      wantGroups: [for (final bundle in bundles) bundle.names],
    );
  }

  Future<PostDetailItem> _toItem(Map<String, dynamic> raw) async {
    final images = _maps(raw['item_images'])
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    final urls = await Future.wait(
      images.map((image) => _signPath(image['storage_key'] as String)),
    );

    return PostDetailItem(
      id: raw['id'] as String,
      title: raw['title'] as String,
      description: raw['description'] as String,
      condition: ItemCondition.fromDb(raw['item_condition'] as String),
      manufactureYear: raw['manufacture_year'] as int?,
      // Skip any photo whose signed URL failed.
      photoUrls: [for (final url in urls) if (url != null) url],
    );
  }

  /// Signed URL for one private photo, or null if signing fails.
  Future<String?> _signPath(String path) async {
    try {
      return await _client.storage
          .from(_imageBucket)
          .createSignedUrl(path, _signedUrlSeconds);
    } catch (_) {
      return null;
    }
  }
}

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final e in (value as List<dynamic>? ?? const <dynamic>[]))
    e as Map<String, dynamic>,
];

String _lower(Object? value) => (value as String).toLowerCase();