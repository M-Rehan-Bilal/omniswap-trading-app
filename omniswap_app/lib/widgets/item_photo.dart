import 'package:flutter/material.dart';

import '../screens/home_screen.dart'; // kOmniBg, kOmniMuted

/// Shows an item photo from a signed URL, or a placeholder if there is none.
/// It fills its parent, so wrap it in a widget with a set size.
class ItemPhoto extends StatelessWidget {
  const ItemPhoto({super.key, required this.url, this.iconSize = 36});

  final String? url;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: kOmniBg,
      child: Center(
        child: Icon(Icons.image_outlined, size: iconSize, color: kOmniMuted),
      ),
    );

    final imageUrl = url;
    if (imageUrl == null) return placeholder;

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) =>
      progress == null ? child : placeholder,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}