import 'package:flutter/material.dart';

import '../screens/home_screen.dart'; // kOmniInk, kOmniMuted

enum OmniTab { home, browse, inventory, trades }

/// Bottom navigation shared by the main screens.
/// The yellow + button is a docked FloatingActionButton, so each screen
/// sets it on its own Scaffold.
class OmniBottomBar extends StatelessWidget {
  const OmniBottomBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final OmniTab selected;
  final ValueChanged<OmniTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _OmniNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isSelected: selected == OmniTab.home,
            onTap: () => onSelect(OmniTab.home),
          ),
          _OmniNavItem(
            icon: Icons.grid_view_rounded,
            label: 'Browse',
            isSelected: selected == OmniTab.browse,
            onTap: () => onSelect(OmniTab.browse),
          ),
          const SizedBox(width: 56), // space for the docked + button
          _OmniNavItem(
            icon: Icons.shopping_cart_outlined,
            label: 'Inventory',
            isSelected: selected == OmniTab.inventory,
            onTap: () => onSelect(OmniTab.inventory),
          ),
          _OmniNavItem(
            icon: Icons.swap_horiz_rounded,
            label: 'Trades',
            isSelected: selected == OmniTab.trades,
            onTap: () => onSelect(OmniTab.trades),
          ),
        ],
      ),
    );
  }
}

class _OmniNavItem extends StatelessWidget {
  const _OmniNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? kOmniInk : kOmniMuted;

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
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}