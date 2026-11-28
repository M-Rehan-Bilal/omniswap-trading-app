import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/trade_action_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/item_photo.dart';

/// Reasons for cancelling a trade. The keys match the cancel_reason enum in the database.
const Map<String, String> _cancelReasons = {
  'changed_mind': 'Changed my mind',
  'item_unavailable': 'Item not available',
  'no_show': 'Other person did not show up',
  'verification_failed': 'Code or item did not match',
  'other': 'Other',
};

/// Where I check the items I receive and enter the other person's code.
class VerifyItemScreen extends StatefulWidget {
  const VerifyItemScreen({
    super.key,
    required this.tradeId,
    required this.itemTitles,
    required this.itemPhotoUrl,
    required this.fromName,
  });

  final String tradeId;

  /// The items I am receiving.
  final List<String> itemTitles;
  final String? itemPhotoUrl;

  /// The person who gives me the items.
  final String fromName;

  @override
  State<VerifyItemScreen> createState() => _VerifyItemScreenState();
}

class _VerifyItemScreenState extends State<VerifyItemScreen> {
  final TradeActionService _service = TradeActionService();
  final TextEditingController _codeController = TextEditingController();

  bool _matchesDescription = false;
  bool _matchesCondition = false;
  bool _busy = false;

  String get _code => _codeController.text.toUpperCase();

  bool get _canComplete =>
      !_busy && _code.length == 6 && _matchesDescription && _matchesCondition;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so the boxes and the button stay in sync.
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Sends the code to the database. The database checks it against the other
  /// person's code, and completes the trade when both sides have verified.
  Future<void> _completeTrade() async {
    if (!_canComplete) return;
    setState(() => _busy = true);

    final navigator = Navigator.of(context);
    try {
      await _service.verifyReceipt(tradeId: widget.tradeId, code: _code);
      navigator.pop(true); // Trade screen reloads
    } on TradeActionException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for a reason, then cancels the trade. The reason is required.
  Future<void> _rejectAndCancel() async {
    if (_busy) return;

    final reason = await _pickCancelReason();
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      await _service.cancelTrade(tradeId: widget.tradeId, reason: reason);
      navigator.pop(true); // Trade screen reloads
    } on TradeActionException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the reason list. Returns the chosen key, or null if the user backs out.
  Future<String?> _pickCancelReason() {
    String? reason;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cancel this trade?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose a reason. It is required.'),
              const SizedBox(height: 8),
              for (final entry in _cancelReasons.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(entry.value),
                  trailing: reason == entry.key
                      ? const Icon(Icons.check_circle, color: kOmniBlue)
                      : const Icon(Icons.circle_outlined, color: kOmniBorder),
                  onTap: () => setDialogState(() => reason = entry.key),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep trade'),
            ),
            TextButton(
              onPressed: reason == null
                  ? null
                  : () => Navigator.pop(dialogContext, reason),
              child: Text(
                'Cancel trade',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: kOmniSurface,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: const Text(
          'Verify Item',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildReceivingCard(),
          const SizedBox(height: 24),
          Text(
            "${widget.fromName}'s trade code",
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kOmniInk,
            ),
          ),
          const SizedBox(height: 12),
          _buildCodeInput(),
          const SizedBox(height: 24),
          const Text(
            'Check what you received',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kOmniInk,
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _matchesDescription,
            onChanged: _busy
                ? null
                : (value) => setState(() => _matchesDescription = value ?? false),
            title: const Text('Matches the description'),
            activeColor: kOmniBlue,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _matchesCondition,
            onChanged: _busy
                ? null
                : (value) => setState(() => _matchesCondition = value ?? false),
            title: const Text('Matches the condition'),
            activeColor: kOmniBlue,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _canComplete ? _completeTrade : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kOmniYellow,
                foregroundColor: kOmniInk,
                disabledBackgroundColor: kOmniYellow.withOpacity(0.45),
                disabledForegroundColor: kOmniInk.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: kOmniInk,
                ),
              )
                  : const Text(
                'Complete Trade',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _rejectAndCancel,
              style: TextButton.styleFrom(foregroundColor: kOmniMuted),
              child: const Text(
                'Reject and Cancel trade',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
          ),
          const Center(
            child: Text(
              'Reason required',
              style: TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// The items I am receiving and who gives them to me.
  Widget _buildReceivingCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardBox,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Receiving',
                  style: TextStyle(color: kOmniMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.itemTitles.join(' + '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'from ${widget.fromName}',
                  style: const TextStyle(color: kOmniMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: kOmniSelectedBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ItemPhoto(url: widget.itemPhotoUrl, iconSize: 22),
            ),
          ),
        ],
      ),
    );
  }

  /// Six boxes that show the typed code. One hidden text field sits on top,
  /// so tapping the boxes opens the keyboard.
  Widget _buildCodeInput() {
    final code = _code;

    return Stack(
      children: [
        IgnorePointer(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 6; i++)
                _CodeBox(text: i < code.length ? code[i] : ''),
            ],
          ),
        ),
        Positioned.fill(
          child: TextField(
            controller: _codeController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(6),
            ],
            // Hide the typed text and caret, because the boxes show the code.
            style: const TextStyle(color: Colors.transparent),
            cursorColor: Colors.transparent,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  static final BoxDecoration _cardBox = BoxDecoration(
    color: kOmniSurface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: kOmniBorder),
  );
}

/// One box of the trade code.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kOmniSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOmniBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: kOmniBlue,
        ),
      ),
    );
  }
}