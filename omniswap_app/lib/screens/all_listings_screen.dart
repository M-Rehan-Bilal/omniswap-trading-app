import 'package:flutter/material.dart';

import '../models/post_listing.dart';
import '../theme/omni_colors.dart';
import '../widgets/listing_card.dart';

/// Full list for one home section ("Matches for you", "Offers for you").
class AllListingsScreen extends StatelessWidget {
  const AllListingsScreen({
    super.key,
    required this.title,
    required this.posts,
    required this.urlFor,
    required this.onPostTap,
  });

  final String title;
  final List<PostListing> posts;

  /// Looks up the signed URL for a post's cover photo.
  final String? Function(PostListing post) urlFor;

  final ValueChanged<PostListing> onPostTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: posts.isEmpty
          ? const _NothingHere()
          : CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${posts.length} ${posts.length == 1 ? 'listing' : 'listings'}',
                style: const TextStyle(
                  color: kOmniMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return ListingCard(
                  post: post,
                  imageUrl: urlFor(post),
                  onTap: () => onPostTap(post),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingHere extends StatelessWidget {
  const _NothingHere();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: kOmniMuted),
          SizedBox(height: 8),
          Text(
            'Nothing to show yet.',
            style: TextStyle(color: kOmniMuted),
          ),
        ],
      ),
    );
  }
}