import 'package:flutter/material.dart';

import '../models/post_listing.dart';
import '../services/trade_service.dart';
import '../widgets/omni_bottom_bar.dart';

const Color kOmniYellow = Color(0xFFFFE01B);
const Color kOmniInk = Color(0xFF1B2433);
const Color kOmniMuted = Color(0xFF8A94A6);
const Color kOmniBg = Color(0xFFF4F7FB);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TradeService _service = TradeService();
  final TextEditingController _wantController = TextEditingController();

  // Listings and matches
  List<PostListing> _myPosts = [];
  Map<String, List<PostListing>> _matchesByPostId = {};
  bool _loadingListings = true;

  // Find Trade
  String? _selectedItemId;
  bool _searching = false;
  bool _hasSearched = false;
  String _resultsTitle = '';
  List<PostListing> _results = [];

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _wantController.dispose();
    super.dispose();
  }

  /// Every item in my active posts. An item is in at most one post.
  List<PostedItem> get _myItems {
    final seen = <String>{};
    return [
      for (final post in _myPosts)
        for (final item in post.items)
          if (seen.add(item.id)) item,
    ];
  }

  PostedItem? get _selectedItem {
    for (final item in _myItems) {
      if (item.id == _selectedItemId) return item;
    }
    return null;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Opens a route, then reloads listings when the user comes back.
  Future<void> _openRoute(String route, {Object? arguments}) async {
    await Navigator.pushNamed(context, route, arguments: arguments);
    if (mounted) _loadListings();
  }

  Future<void> _loadListings() async {
    setState(() => _loadingListings = true);
    try {
      final posts = await _service.fetchMyActivePosts();
      final keys = {for (final post in posts) ...post.itemKeys};
      final wanting = await _service.fetchPostsWantingModels(keys);

      // A post matches if it wants any item in my bundle. Each post appears once.
      final matches = <String, List<PostListing>>{};
      for (final post in posts) {
        final seen = <String>{};
        final found = <PostListing>[];
        for (final key in post.itemKeys) {
          for (final other in wanting[key] ?? const <PostListing>[]) {
            if (seen.add(other.postId)) found.add(other);
          }
        }
        matches[post.postId] = found;
      }

      if (!mounted) return;
      setState(() {
        _myPosts = posts;
        _matchesByPostId = matches;
        if (_selectedItem == null) _selectedItemId = null;
      });
    } catch (_) {
      _showMessage('Could not load your listings. Pull down to retry.');
    } finally {
      if (mounted) setState(() => _loadingListings = false);
    }
  }

  Future<void> _findTrade() async {
    final item = _selectedItem;
    final want = _wantController.text.trim();

    if (item == null) {
      _showMessage('Choose an item you have.');
      return;
    }
    if (want.isEmpty) {
      _showMessage('Type the item you want.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final results = await _service.findDirectTrades(
        haveModelKey: item.modelKey,
        wantText: want,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _resultsTitle = 'Trades for ${item.modelName} → $want';
        _hasSearched = true;
      });
    } catch (_) {
      _showMessage('Search failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _showMatchesFor(PostListing post) {
    setState(() {
      _selectedItemId = post.cover?.id;
      _results = _matchesByPostId[post.postId] ?? [];
      _resultsTitle = 'People who want ${post.displayTitle}';
      _hasSearched = true;
    });
  }

  void _swapFields() {
    final currentItem = _selectedItem;
    final typedWant = normalizeModelKey(_wantController.text);

    String? newSelectedId;
    for (final item in _myItems) {
      if (item.modelKey == typedWant) {
        newSelectedId = item.id;
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

  void _openOffer(PostListing post) {
    _openRoute('/make-offer', arguments: post);
  }

  void _onTab(OmniTab tab) {
    switch (tab) {
      case OmniTab.home:
        break;
      case OmniTab.browse:
        _openRoute('/browse');
        break;
      case OmniTab.inventory:
        _openRoute('/inventory');
        break;
      case OmniTab.trades:
        _openRoute('/trades');
        break;
    }
  }

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
            onPressed: () => _openRoute('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: kOmniInk),
            onPressed: () => _openRoute('/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadListings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSwapCard(),
              const SizedBox(height: 24),
              const _SectionTitle('Results'),
              const SizedBox(height: 8),
              _buildResults(),
              const SizedBox(height: 24),
              const _SectionTitle('Matches for my listings'),
              const SizedBox(height: 8),
              _buildMyMatches(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kOmniYellow,
        elevation: 2,
        onPressed: () => _openRoute('/add-item'),
        child: const Icon(Icons.add, color: kOmniInk, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: OmniBottomBar(
        selected: OmniTab.home,
        onSelect: _onTab,
      ),
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
            value: _selectedItem?.id,
            isExpanded: true,
            decoration: _inputDecoration(
              hint: _loadingListings
                  ? 'Loading your items...'
                  : items.isEmpty
                  ? 'Post an item first'
                  : 'Select an item',
            ),
            items: [
              for (final item in items)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.modelName, overflow: TextOverflow.ellipsis),
                ),
            ],
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
  // Results
  // ---------------------------------------------------------------------------

  Widget _buildResults() {
    if (!_hasSearched) {
      return const _EmptyBox(
        icon: Icons.search,
        message: 'Results will appear here',
      );
    }
    if (_results.isEmpty) {
      return const _EmptyBox(
        icon: Icons.sync_alt,
        message: 'No direct trades found right now.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _resultsTitle,
            style: const TextStyle(color: kOmniMuted, fontSize: 13),
          ),
        ),
        for (final post in _results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ResultCard(post: post, onTap: () => _openOffer(post)),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Matches for my listings: one card per post
  // ---------------------------------------------------------------------------

  Widget _buildMyMatches() {
    if (_loadingListings && _myPosts.isEmpty) {
      return const SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_myPosts.isEmpty) {
      return const _EmptyBox(
        icon: Icons.inventory_2_outlined,
        message: 'Post an item to see who wants it.',
      );
    }

    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _myPosts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final post = _myPosts[index];
          return _ListingMatchCard(
            post: post,
            matchCount: _matchesByPostId[post.postId]?.length ?? 0,
            onTap: () => _showMatchesFor(post),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small reusable widgets and helpers
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

IconData _iconFor(String modelName) {
  final key = normalizeModelKey(modelName);
  if (key.contains('ps') || key.contains('xbox') || key.contains('switch')) {
    return Icons.sports_esports_outlined;
  }
  if (key.contains('watch')) return Icons.watch_outlined;
  if (key.contains('iphone') ||
      key.contains('phone') ||
      key.contains('galaxy')) {
    return Icons.phone_iphone;
  }
  if (key.contains('ipad') || key.contains('tablet')) return Icons.tablet_mac;
  if (key.contains('laptop') || key.contains('macbook')) {
    return Icons.laptop_mac;
  }
  return Icons.inventory_2_outlined;
}

String _prettyCondition(String condition) {
  if (condition.isEmpty) return condition;
  final text = condition.replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: kOmniInk,
      ),
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

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: kOmniMuted),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kOmniMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ListingMatchCard extends StatelessWidget {
  const _ListingMatchCard({
    required this.post,
    required this.matchCount,
    required this.onTap,
  });

  final PostListing post;
  final int matchCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = matchCount == 0
        ? 'No matches yet'
        : '$matchCount ${matchCount == 1 ? 'match' : 'matches'}';

    return SizedBox(
      width: 160,
      height: 130,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: kOmniBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(post.cover?.modelName ?? ''),
                    color: kOmniInk,
                  ),
                ),
                const Spacer(),
                Text(
                  post.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: kOmniMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.post, required this.onTap});

  final PostListing post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wantsLine = post.acceptsOutsideWants
        ? 'Open to any item'
        : post.wantNames.isEmpty
        ? 'Open to offers'
        : 'Wants: ${post.wantNames.join(', ')}';

    final detailLine = post.items.length == 1
        ? 'Condition: ${_prettyCondition(post.items.first.condition)}'
        : '${post.items.length} items in this post';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kOmniBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(post.cover?.modelName ?? ''),
                  color: kOmniInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kOmniInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detailLine,
                      style: const TextStyle(color: kOmniMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      wantsLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kOmniMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kOmniMuted),
            ],
          ),
        ),
      ),
    );
  }
}