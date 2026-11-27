import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post_listing.dart';
import '../services/browse_service.dart';
import '../services/profile_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/listing_card.dart';
import '../widgets/omni_bottom_bar.dart';
import 'post_details_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const _border = Color(0xFFD9E0EA);

  final BrowseService _service = BrowseService();
  final ProfileService _profileService = ProfileService();
  final TextEditingController _searchController = TextEditingController();

  List<PostListing> _posts = [];

  // Signed photo URLs, keyed by storage path. Same approach as home.
  final Map<String, String> _urlByPath = {};

  bool _loading = true;
  String? _error;
  bool _newestFirst = true;
  Timer? _debounce;
  int _requestId = 0;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAvatar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final id = ++_requestId;
    if (showSpinner) setState(() => _loading = true);

    try {
      final posts = await _service.fetchPosts(
        search: _searchController.text,
        newestFirst: _newestFirst,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _posts = posts;
        _error = null;
        _loading = false;
      });

      // Cards show immediately as placeholders, then photos fill in.
      final urls = await _service.signCovers(posts);
      if (!mounted || id != _requestId) return;
      setState(() => _urlByPath.addAll(urls));
    } catch (e) {
      debugPrint('Browse load failed: $e');
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = 'Could not load items.';
        _loading = false;
      });
    }
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

  String? _urlFor(PostListing post) {
    final path = post.coverPath;
    return path == null ? null : _urlByPath[path];
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {});
    _load();
  }

  void _onSortChanged(bool? value) {
    if (value == null || value == _newestFirst) return;
    setState(() => _newestFirst = value);
    _load();
  }

  void _openPost(PostListing post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailsScreen(postId: post.postId),
      ),
    );
  }

  void _onTab(OmniTab tab) {
    switch (tab) {
      case OmniTab.home:
        Navigator.popUntil(context, (route) => route.isFirst);
        break;
      case OmniTab.browse:
        break;
      case OmniTab.inventory:
        Navigator.pushReplacementNamed(context, '/inventory');
        break;
      case OmniTab.trades:
        Navigator.pushReplacementNamed(context, '/trades');
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
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: const Text(
          'Browse',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {}, // TODO: notifications
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => Navigator.pushNamed(context, '/profile')
                .then((_) => _loadAvatar()),
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
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildSearchField(),
          _buildSortRow(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(showSpinner: false),
              child: _buildContent(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kOmniYellow,
        elevation: 2,
        onPressed: () => Navigator.pushNamed(context, '/add-item'),
        child: const Icon(Icons.add, color: kOmniInk, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: OmniBottomBar(
        selected: OmniTab.browse,
        onSelect: _onTab,
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        onSubmitted: (_) {
          _debounce?.cancel();
          _load();
        },
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          hintText: 'Search items',
          hintStyle: const TextStyle(color: kOmniMuted),
          prefixIcon: const Icon(Icons.search, color: kOmniMuted),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
            icon: const Icon(Icons.close, color: kOmniMuted),
            onPressed: _clearSearch,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kOmniInk),
          ),
        ),
      ),
    );
  }

  Widget _buildSortRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          const Text(
            'Sort:',
            style: TextStyle(color: kOmniMuted, fontSize: 13),
          ),
          const SizedBox(width: 6),
          DropdownButton<bool>(
            value: _newestFirst,
            underline: const SizedBox(),
            isDense: true,
            icon: const Icon(Icons.keyboard_arrow_down, color: kOmniInk),
            style: const TextStyle(
              color: kOmniInk,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            items: const [
              DropdownMenuItem(value: true, child: Text('Newest')),
              DropdownMenuItem(value: false, child: Text('Oldest')),
            ],
            onChanged: _onSortChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _posts.isEmpty) {
      return _scrollableMessage(
        const CircularProgressIndicator(),
      );
    }

    if (_error != null && _posts.isEmpty) {
      return _scrollableMessage(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: kOmniMuted)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return _scrollableMessage(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 40, color: kOmniMuted),
            const SizedBox(height: 8),
            Text(
              searching ? 'No items match your search' : 'No items posted yet',
              style: const TextStyle(color: kOmniMuted),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: _posts.length,
            itemBuilder: (_, i) {
              final post = _posts[i];
              return ListingCard(
                post: post,
                imageUrl: _urlFor(post),
                onTap: () => _openPost(post),
              );
            },
          ),
        ),
      ],
    );
  }

  /// A centered message that still supports pull-to-refresh.
  Widget _scrollableMessage(Widget child) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: child),
        ),
      ],
    );
  }
}