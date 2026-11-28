import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_limits.dart';
import 'trade_service.dart' show normalizeModelKey;

/// An error the user can read. The message is shown as-is.
class PostException implements Exception {
  const PostException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PostService {
  PostService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Creates one post for a bundle of items, with its wanted entries.
  /// Each inner list in [wantGroups] is one entry: a single name, or a bundle.
  /// Returns the new post id.
  Future<String> createPost({
    required List<String> itemIds,
    required bool acceptsOutsideWants,
    required List<List<String>> wantGroups,
  }) async {
    if (itemIds.isEmpty) {
      throw const PostException('Choose at least one item to post.');
    }
    if (itemIds.length > kMaxItemsPerPost) {
      throw PostException('A post can hold up to $kMaxItemsPerPost items.');
    }
    if (itemIds.toSet().length != itemIds.length) {
      throw const PostException('The same item was selected more than once.');
    }

    final cleanGroups = cleanWantGroups(wantGroups);
    if (cleanGroups.length > kMaxWantsPerPost) {
      throw PostException(
        'You can add up to $kMaxWantsPerPost wanted items.',
      );
    }
    if (cleanGroups.isEmpty && !acceptsOutsideWants) {
      throw const PostException(
        'Add a wanted item, or allow offers for items not listed.',
      );
    }

    try {
      final postId = await _client.rpc('create_post', params: {
        'p_item_ids': itemIds,
        'p_accepts_outside_wants': acceptsOutsideWants,
        'p_want_groups': cleanGroups,
      });
      return postId as String;
    } on PostgrestException catch (e) {
      throw PostException(_messageFor(e));
    }
  }

  /// Removes one of your posts. Its items become available again, and
  /// pending offers on it are cancelled by the database.
  Future<void> removePost(String postId) async {
    try {
      await _client.rpc('remove_post', params: {'p_post_id': postId});
    } on PostgrestException catch (e) {
      throw PostException(_messageFor(e));
    }
  }

  /// Cleans each wanted entry: trims names, drops blanks, removes repeats
  /// by model key, and drops entries with no names left. Two entries with
  /// the same items in any order count as one.
  static List<List<String>> cleanWantGroups(List<List<String>> raw) {
    final result = <List<String>>[];
    final signatures = <String>{};

    for (final group in raw) {
      final names = <String>[];
      final keys = <String>{};

      for (final entry in group) {
        final text = entry.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty) continue;

        if (text.length > kMaxWantLength) {
          throw PostException(
            'Keep each wanted item under $kMaxWantLength characters.',
          );
        }
        final key = normalizeModelKey(text);
        if (key.isEmpty) {
          throw const PostException(
            'Wanted items need at least one letter or number.',
          );
        }
        if (keys.add(key)) names.add(text);
      }

      if (names.isEmpty) continue;
      if (names.length > kMaxItemsPerWantBundle) {
        throw PostException(
          'A bundle can hold up to $kMaxItemsPerWantBundle items.',
        );
      }

      final signature = (keys.toList()..sort()).join('|');
      if (!signatures.add(signature)) {
        throw const PostException('You added the same wanted item twice.');
      }
      result.add(names);
    }
    return result;
  }

  /// Errors raised by our SQL functions (code P0001) carry readable messages.
  /// Anything else gets a generic message.
  static String _messageFor(PostgrestException e) {
    if (e.code == 'P0001' && e.message.isNotEmpty) return e.message;
    return 'Something went wrong. Please try again.';
  }
}