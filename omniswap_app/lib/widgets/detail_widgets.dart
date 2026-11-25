import 'package:flutter/material.dart';

import '../screens/home_screen.dart'; // kOmniYellow, kOmniInk, kOmniMuted

/// Small pill that shows an item's condition.
class ConditionChip extends StatelessWidget {
  const ConditionChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE3EAF3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: kOmniInk,
        ),
      ),
    );
  }
}

/// Small uppercase heading used above a section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: kOmniMuted,
      ),
    );
  }
}

/// Dots under a photo carousel. The current page is a wider, dark dot.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? kOmniInk : const Color(0xFFB8C4D6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A centered message, with an optional retry button.
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({super.key, required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kOmniMuted),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// The bottom "Make an Offer" bar. Offers always cover the whole post,
/// so a bundle gets a note that says so.
class MakeOfferBar extends StatelessWidget {
  const MakeOfferBar({
    super.key,
    required this.itemCount,
    required this.onPressed,
  });

  final int itemCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isBundle = itemCount > 1;

    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBundle)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Offers are for the whole bundle.',
                    style: TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOmniYellow,
                    foregroundColor: kOmniInk,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onPressed,
                  child: Text(
                    isBundle
                        ? 'Make an Offer for all $itemCount items'
                        : 'Make an Offer',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}