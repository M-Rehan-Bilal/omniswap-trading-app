import 'package:flutter/material.dart';

import '../models/post_listing.dart';
import '../services/trade_service.dart';

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
  Map<String, List<PostListing>> _matchesByItemId = {};
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

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadListings() async {
    setState(() => _loadingListings = true);
    try {
      final posts = await _service.fetchMyActivePosts();
      final wanting = await _service.fetchPostsWantingModels(
        posts.map((p) => p.modelKey).toSet(),
      );

      final matches = <String, List<PostListing>>{};
      for (final post in posts) {
        matches[post.itemId] = wanting[post.modelKey] ?? [];
      }

      if (!mounted) return;
      setState(() {
        _myPosts = posts;
        _matchesByItemId = matches;
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

  void _showMatchesFor(PostListing item) {
    setState(() {
      _selectedItemId = item.itemId;
      _results = _matchesByItemId[item.itemId] ?? [];
      _resultsTitle = 'People who want your ${item.modelName}';
      _hasSearched = true;
    });
  }

  void _swapFields() {
    final currentItem = _selectedItem;
    final typedWant = normalizeModelKey(_wantController.text);

    String? newSelectedId;
    for (final item in _myItems) {
      if (item.modelKey == typedWant) {
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

  void _openOffer(PostListing post) {
    Navigator.pushNamed(context, '/make-offer', arguments: post);
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
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: kOmniInk),
            onPressed: () => Navigator.pushNamed(context, '/profile'),
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
                child: Text(item.modelName, overflow: TextOverflow.ellipsis),
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
        ..._results.map(
              (post) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ResultCard(post: post, onTap: () => _openOffer(post)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Matches for my listings (horizontal cards)
  // ---------------------------------------------------------------------------

  Widget _buildMyMatches() {
    if (_loadingListings && _myItems.isEmpty) {
      return const SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_myItems.isEmpty) {
      return const _EmptyBox(
        icon: Icons.inventory_2_outlined,
        message: 'Post an item to see who wants it.',
      );
    }

    final items = _myItems;
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final count = _matchesByItemId[item.itemId]?.length ?? 0;
          return _ListingMatchCard(
            item: item,
            matchCount: count,
            onTap: () => _showMatchesFor(item),
          );
        },
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
  if (key.contains('iphone') || key.contains('phone') || key.contains('galaxy')) {
    return Icons.phone_iphone;
  }
  if (key.contains('ipad') || key.contains('tablet')) return Icons.tablet_mac;
  if (key.contains('laptop') || key.contains('macbook')) {
    return Icons.laptop_mac;
  }
  return Icons.inventory_2_outlined;
}

String _prettyCondition(String condition) {
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
    required this.item,
    required this.matchCount,
    required this.onTap,
  });

  final PostListing item;
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
                  child: Icon(_iconFor(item.modelName), color: kOmniInk),
                ),
                const Spacer(),
                Text(
                  item.title,
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
        : 'Wants: ${post.wantNames.join(', ')}';

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
                child: Icon(_iconFor(post.modelName), color: kOmniInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kOmniInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Condition: ${_prettyCondition(post.condition)}',
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