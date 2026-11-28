import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/omni_colors.dart';
import '../widgets/item_photo.dart';
import 'verify_item_screen.dart';

/// The trade page: shows my trade code and the items in the trade.
class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key, required this.tradeId});

  final String tradeId;

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  _TradeData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = _client.auth.currentUser?.id ?? '';

      // 1. The trade status.
      final trade = await _client
          .from('trades')
          .select('status')
          .eq('id', widget.tradeId)
          .single();

      // 2. My own row. RLS only lets me read my own code.
      final mine = await _client
          .from('trade_participants')
          .select('verification_code, received_verified_at')
          .eq('trade_id', widget.tradeId)
          .eq('user_id', me)
          .maybeSingle();

      // 3. The items in this trade, with who gives them to whom.
      final rows = await _client
          .from('trade_items')
          .select('giver_user_id, receiver_user_id, '
          'items(title, item_images(position, storage_key))')
          .eq('trade_id', widget.tradeId);

      final itemRows = [for (final r in rows) r as Map<String, dynamic>];

      // 4. Display names for everyone involved.
      final userIds = <String>{
        for (final r in itemRows) ...[
          r['giver_user_id'] as String,
          r['receiver_user_id'] as String,
        ],
      };
      final names = await _loadNames(userIds);

      // 5. One exchange per item, with a signed photo URL.
      final exchanges = <_Exchange>[];
      for (final row in itemRows) {
        final item = row['items'] as Map<String, dynamic>;
        exchanges.add(_Exchange(
          title: item['title'] as String,
          url: await _coverUrl(item),
          fromName: names[row['giver_user_id']] ?? 'Unknown',
          toName: names[row['receiver_user_id']] ?? 'Unknown',
          receiverId: row['receiver_user_id'] as String,
        ));
      }

      if (!mounted) return;
      setState(() {
        _data = _TradeData(
          status: trade['status'] as String,
          myId: me,
          code: (mine?['verification_code'] as String?) ?? '',
          iVerified: mine?['received_verified_at'] != null,
          exchanges: exchanges,
        );
      });
    } catch (e) {
      debugPrint('Trade load failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Could not load this trade.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Display names for the given user ids.
  Future<Map<String, String>> _loadNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('public_profiles')
        .select('id, display_name')
        .inFilter('id', ids.toList());

    return {
      for (final row in rows)
        row['id'] as String: row['display_name'] as String,
    };
  }

  /// Signed URL for the item's first photo, or null if it has none.
  Future<String?> _coverUrl(Map<String, dynamic> item) async {
    final images = [
      for (final raw in (item['item_images'] as List<dynamic>? ?? const []))
        raw as Map<String, dynamic>,
    ]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    if (images.isEmpty) return null;
    try {
      return await _client.storage
          .from('item-images')
          .createSignedUrl(images.first['storage_key'] as String, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  /// Opens the verify screen for the items I receive. Reloads when it closes.
  Future<void> _openVerify(_TradeData data) async {
    final incoming = data.incoming;
    if (incoming.isEmpty) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VerifyItemScreen(
          tradeId: widget.tradeId,
          itemTitles: [for (final e in incoming) e.title],
          itemPhotoUrl: incoming.first.url,
          fromName: incoming.first.fromName,
        ),
      ),
    );
    if (changed == true) _load();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final data = _data;

    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: kOmniSurface,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: const Text(
          'Trade',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: _buildBody(data),
      bottomNavigationBar:
      data != null && data.canVerify ? _buildVerifyBar(data) : null,
    );
  }

  Widget _buildBody(_TradeData? data) {
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: kOmniMuted)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (data == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildHeader(data),
          const SizedBox(height: 16),
          _buildAcceptedBanner(),
          const SizedBox(height: 16),
          _buildCodeCard(data.code),
          const SizedBox(height: 24),
          const Text(
            'Exchanges tracked one by one',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kOmniInk,
            ),
          ),
          const SizedBox(height: 12),
          for (final exchange in data.exchanges) ...[
            _buildExchangeCard(exchange, data),
            const SizedBox(height: 10),
          ],
          if (data.isActive && data.iVerified)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'You have verified your items. Waiting for the other person.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kOmniMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// "Trade #3F2A" heading and the status pill.
  Widget _buildHeader(_TradeData data) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Trade #${widget.tradeId.substring(0, 4).toUpperCase()}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kOmniInk,
            ),
          ),
        ),
        _StatusPill(
          label: _statusText(data.status),
          background: kOmniSelectedBg,
          foreground: kOmniBlue,
        ),
      ],
    );
  }

  Widget _buildAcceptedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kOmniSelectedBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: kOmniBlue),
          SizedBox(width: 10),
          Text(
            'Offer Accepted',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: kOmniInk,
            ),
          ),
        ],
      ),
    );
  }

  /// My six-character code, one box per character.
  Widget _buildCodeCard(String code) {
    final chars = code.isEmpty ? List.filled(6, '-') : code.split('');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardBox,
      child: Column(
        children: [
          const Text(
            'TRADE CODE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kOmniMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final ch in chars)
                Container(
                  width: 40,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kOmniSelectedBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kOmniBorder),
                  ),
                  child: Text(
                    ch.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kOmniBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Show this code at meetup',
            style: TextStyle(fontSize: 12, color: kOmniMuted),
          ),
        ],
      ),
    );
  }

  /// One item in the trade, with who gives it to whom and its state.
  Widget _buildExchangeCard(_Exchange exchange, _TradeData data) {
    final state = _exchangeState(exchange, data);
    final done = state != 'Waiting';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardBox,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ItemPhoto(url: exchange.url, iconSize: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exchange.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${exchange.fromName} to ${exchange.toName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kOmniMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          done
              ? _StatusPill(
            label: state,
            background: kOmniSelectedBg,
            foreground: kOmniBlue,
          )
              : _StatusPill(
            label: state,
            background: kOmniYellow,
            foreground: kOmniInk,
          ),
        ],
      ),
    );
  }

  /// The yellow "Meet and Verify" button pinned to the bottom.
  Widget _buildVerifyBar(_TradeData data) {
    return Container(
      color: kOmniSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _openVerify(data),
              style: ElevatedButton.styleFrom(
                backgroundColor: kOmniYellow,
                foregroundColor: kOmniInk,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Meet and Verify',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Waiting until the trade completes. An item I receive shows Received
  /// once I have verified it.
  static String _exchangeState(_Exchange exchange, _TradeData data) {
    if (data.status == 'completed') return 'Done';
    if (exchange.receiverId == data.myId && data.iVerified) return 'Received';
    return 'Waiting';
  }

  static String _statusText(String status) {
    switch (status) {
      case 'proposed':
      case 'pending':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }
}

// -----------------------------------------------------------------------------
// Data holders and small widgets
// -----------------------------------------------------------------------------

/// Everything the screen shows, loaded once.
class _TradeData {
  const _TradeData({
    required this.status,
    required this.myId,
    required this.code,
    required this.iVerified,
    required this.exchanges,
  });

  final String status;
  final String myId;

  /// My own verification code.
  final String code;

  /// True once I have verified that my items arrived.
  final bool iVerified;

  final List<_Exchange> exchanges;

  /// The trade is still open (not completed, cancelled or expired).
  bool get isActive => status == 'pending' || status == 'proposed';

  /// Items I receive.
  List<_Exchange> get incoming =>
      [for (final e in exchanges) if (e.receiverId == myId) e];

  /// Show Meet and Verify only while the trade is open and I have items to receive.
  bool get canVerify => isActive && !iVerified && incoming.isNotEmpty;
}

/// One item moving from one person to the other.
class _Exchange {
  const _Exchange({
    required this.title,
    required this.url,
    required this.fromName,
    required this.toName,
    required this.receiverId,
  });

  final String title;
  final String? url;
  final String fromName;
  final String toName;
  final String receiverId;
}

/// Small rounded label used for the trade status and each exchange state.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

const BoxDecoration _cardBox = BoxDecoration(
  color: kOmniSurface,
  borderRadius: BorderRadius.all(Radius.circular(16)),
  border: Border.fromBorderSide(BorderSide(color: kOmniBorder)),
);