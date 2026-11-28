import 'package:flutter/material.dart';

import '../models/post_listing.dart';
import '../services/profile_service.dart';
import '../services/trade_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/listing_card.dart';
import 'all_listings_screen.dart';
import 'post_details_screen.dart';

// Other screens import the kOmni* colours from this file, so re-export them.
export '../theme/omni_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TradeService _service = TradeService();
  final ProfileService _profileService = ProfileService();
  final TextEditingController _wantController = TextEditingController();

  // Listings
  List<PostListing> _myPosts = [];
  Map<String, List<PostListing>> _matchesByItemId = {};
  bool _loadingListings = true;

  // Signed photo URLs, keyed by storage path.
  final Map<String, String> _urlByPath = {};

  // Find Trade
  String? _selectedItemId;
  bool _searching = false;
  bool _hasSearched = false;
  String _resultsTitle = '';
  List<PostListing> _results = [];

  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadAvatar();
  }

  @override
  void dispose() {
    _wantController.dispose();
    super.dispose();
  }

  Future<void> _loadAvatar() async {
    try {
      final profile = await _profileService.fetchMyProfile();
      if (!mounted) return;
      setState(() => _avatarUrl = profile.avatarUrl);
    } catch (_) {
      // Keep the default icon if the profile can't be loaded.
    }
  }

  // ---------------------------------------------------------------------------
  // Derived data
  // ---------------------------------------------------------------------------

  /// Unique inventory items (one item can be posted in several places).
  List<PostListing> get _myItems {
    final seen = <String>{};
    return _myPosts.where((p) => seen.add(p.itemId)).toList();
  }

  PostListing? get _selectedItem {
    for (final item in _myItems) {
      if (item.itemId == _selectedItemId) return item;
    }
    return null;
  }

  /// Every unique post that wants one of my items.
  List<PostListing> get _matchPosts {
    final seen = <String>{};
    final out = <PostListing>[];
    for (final list in _matchesByItemId.values) {
      for (final post in list) {
        if (seen.add(post.postId)) out.add(post);
      }
    }
    return out;
  }

  String? _urlFor(PostListing post) {
    final path = post.coverPath;
    return path == null ? null : _urlByPath[path];
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadListings() async {
    setState(() => _loadingListings = true);
    try {
      final posts = await _service.fetchMyActivePosts();

      // Every item in every post counts, not only each post's cover item.
      final candidates = await _service.fetchCandidatePosts(
        {for (final post in posts) ...post.itemKeys},
      );

      final matches = <String, List<PostListing>>{};
      for (final post in posts) {
        // A post matches when one of its wanted entries is fully covered by
        // this post's items. A bundle needs every one of its items.
        matches[post.itemId] = [
          for (final other in candidates)
            if (other.wantsCoveredBy(post.itemKeys)) other,
        ];
      }

      if (!mounted) return;
      setState(() {
        _myPosts = posts;
        _matchesByItemId = matches;
        // Clear the selection if the selected item is no longer listed.
        if (_selectedItem == null) _selectedItemId = null;
      });

      await _signCovers(_matchPosts);
    } catch (_) {
      _showMessage('Could not load your listings. Pull down to retry.');
    } finally {
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  /// Signs the cover photo of each post and stores the URLs for the cards.
  /// A failure here only leaves placeholders, so it is not reported as a
  /// listings error.
  Future<void> _signCovers(Iterable<PostListing> posts) async {
    final paths = {
      for (final post in posts)
        if (post.coverPath != null) post.coverPath!,
    };
    if (paths.isEmpty) return;

    try {
      final urls = await _service.signPaths(paths);
      if (!mounted) return;
      setState(() => _urlByPath.addAll(urls));
    } catch (_) {
      // Cards keep their placeholder images.
    }
  }

  Future<void> _findTrade() async {
    final item = _selectedItem;
    final want = _wantController.text.trim();

    if (item == null) {
      _showMessage('Choose an item you have.');
      return;
    }
    if (want.isEmpty || normalizeModelKey(want).isEmpty) {
      _showMessage('Type the item you want.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      // Pass every item in the post, so a bundle matches through any of its items.
      final results = await _service.findDirectTrades(
        haveModelKeys: item.itemKeys,
        wantText: want,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _resultsTitle = 'Trades for ${item.displayTitle} → $want';
        _hasSearched = true;
      });
      await _signCovers(results);
    } catch (_) {
      _showMessage('Search failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _swapFields() {
    final currentItem = _selectedItem;
    final typedWant = normalizeModelKey(_wantController.text);

    String? newSelectedId;
    for (final item in _myItems) {
      if (item.itemKeys.contains(typedWant)) {
        newSelectedId = item.itemId;
        break;
      }
    }

    if (newSelectedId == null && typedWant.isNotEmpty) {
      _showMessage(
        'That item is not one of your posted items, so I HAVE was cleared.',
      );
    }

    setState(() {
      _selectedItemId = newSelectedId;
      _wantController.text = currentItem?.modelName ?? '';
      _results = [];
      _hasSearched = false;
    });
  }

  /// Opens the product page of the post. Making an offer happens there.
  void _openPost(PostListing post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailsScreen(postId: post.postId),
      ),
    );
  }

  void _openSeeAll(String title, List<PostListing> posts) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AllListingsScreen(
          title: title,
          posts: posts,
          urlFor: _urlFor,
          onPostTap: _openPost,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'OmniSwap',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: kOmniInk),
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () =>
                Navigator.pushNamed(context, '/profile').then((_) => _loadAvatar()),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: kOmniBg,
              backgroundImage:
              _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
              child: _avatarUrl == null
                  ? const Icon(Icons.account_circle_outlined, color: kOmniInk)
                  : null,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadListings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSwapCard(),

              // Results appear only after Find Trade has run.
              if (_hasSearched) ...[
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'Results',
                  subtitle: _resultsTitle,
                ),
                const SizedBox(height: 12),
                _CardRow(
                  posts: _results,
                  emptyText: 'No direct trades found right now.',
                  loading: false,
                  urlFor: _urlFor,
                  onTap: _openPost,
                ),
              ],

              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Matches for you',
                onSeeAll: () => _openSeeAll('Matches for you', _matchPosts),
              ),
              const SizedBox(height: 12),
              _CardRow(
                posts: _matchPosts,
                emptyText: _myItems.isEmpty
                    ? 'Post an item to see who wants it.'
                    : 'No matches for your listings yet.',
                loading: _loadingListings && _matchPosts.isEmpty,
                urlFor: _urlFor,
                onTap: _openPost,
              ),

              // Offers sent to you are not built yet, so this section stays
              // empty rather than showing unrelated listings.
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Offers for you'),
              const SizedBox(height: 12),
              const _EmptyRow(text: 'Offers sent to you will appear here.'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kOmniYellow,
        elevation: 2,
        onPressed: () =>
            Navigator.pushNamed(context, '/add-item').then((_) => _loadListings()),
        child: const Icon(Icons.add, color: kOmniInk, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ---------------------------------------------------------------------------
  // Swap card: I HAVE / I WANT / swap / Find Trade
  // ---------------------------------------------------------------------------

  Widget _buildSwapCard() {
    final items = _myItems;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you want to swap?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kOmniInk,
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel('I HAVE'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _selectedItem?.itemId,
            isExpanded: true,
            decoration: _inputDecoration(
              hint: _loadingListings
                  ? 'Loading your items...'
                  : items.isEmpty
                  ? 'Post an item first'
                  : 'Select an item',
            ),
            items: items
                .map(
                  (item) => DropdownMenuItem<String>(
                value: item.itemId,
                child: Text(
                  item.displayTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
                .toList(),
            onChanged: items.isEmpty
                ? null
                : (value) => setState(() => _selectedItemId = value),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('I WANT'),
          const SizedBox(height: 6),
          TextField(
            controller: _wantController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _findTrade(),
            decoration: _inputDecoration(hint: 'Search a model, e.g. iPhone')
                .copyWith(
              prefixIcon: const Icon(Icons.search, color: kOmniMuted),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: IconButton(
              tooltip: 'Swap',
              onPressed: _swapFields,
              icon: const Icon(Icons.swap_vert_rounded, color: kOmniInk),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kOmniYellow,
                foregroundColor: kOmniInk,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _searching ? null : _findTrade,
              child: _searching
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: kOmniInk,
                ),
              )
                  : const Text(
                'Find Trade',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom navigation (Post button is the docked yellow FAB)
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: true,
            onTap: () {},
          ),
          _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'Browse',
            onTap: () => Navigator.pushNamed(context, '/browse'),
          ),
          const SizedBox(width: 56), // space for the docked FAB
          _NavItem(
            icon: Icons.shopping_cart_outlined,
            label: 'Inventory',
            onTap: () => Navigator.pushNamed(context, '/inventory'),
          ),
          _NavItem(
            icon: Icons.swap_horiz_rounded,
            label: 'Trades',
            onTap: () => Navigator.pushNamed(context, '/trades'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers and widgets
// -----------------------------------------------------------------------------

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

InputDecoration _inputDecoration({required String hint}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: kOmniBg,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: kOmniInk, width: 1.2),
  ),
);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.onSeeAll});

  final String title;
  final String? subtitle;

  /// When set, a "See all" button is shown on the right.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kOmniInk,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: kOmniBlue,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'See all',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: kOmniMuted,
      ),
    );
  }
}

/// A horizontal row of listing cards, with loading and empty states.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.posts,
    required this.emptyText,
    required this.loading,
    required this.urlFor,
    required this.onTap,
  });

  final List<PostListing> posts;
  final String emptyText;
  final bool loading;
  final String? Function(PostListing post) urlFor;
  final ValueChanged<PostListing> onTap;

  static const double _height = 200;
  static const double _cardWidth = 165;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: _height,
        child: Center(child: CircularProgressIndicator(color: kOmniBlue)),
      );
    }
    if (posts.isEmpty) {
      return _EmptyRow(text: emptyText);
    }

    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: posts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final post = posts[index];
          return ListingCard(
            post: post,
            imageUrl: urlFor(post),
            width: _cardWidth,
            onTap: () => onTap(post),
          );
        },
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 110,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOmniBlue.withOpacity(0.3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: kOmniMuted, fontSize: 13),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? kOmniInk : kOmniMuted;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}