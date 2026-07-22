import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared bottom navigation bar used across all Worker screens.
// The parent screen provides [activeIndex], [unreadAlerts], and an [onTap] 
// callback so navigation logic stays in the screen, not the widget.
// ─────────────────────────────────────────────────────────────────────────────
class WorkerBottomNav extends StatelessWidget {
  const WorkerBottomNav({
    super.key,
    required this.activeIndex,
    required this.onTap,
    this.unreadAlerts = 0, // NEW: Defaults to 0, Parent screen will provide real count
  });

  final int activeIndex;
  final ValueChanged<int> onTap;
  final int unreadAlerts; // NEW: Added variable to hold dynamic alert data

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavTile(
                index: 0,
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: 'Chat',
                activeIndex: activeIndex,
                onTap: onTap,
              ),
              _NavTile(
                index: 1,
                icon: Icons.description_outlined,
                activeIcon: Icons.description,
                label: 'Documents',
                activeIndex: activeIndex,
                onTap: onTap,
              ),
              _NavBadgeTile(
                index: 2,
                icon: Icons.notifications_outlined,
                activeIcon: Icons.notifications,
                label: 'Alerts',
                badgeCount: unreadAlerts, // NEW: Passes dynamic alert count
                activeIndex: activeIndex,
                onTap: onTap,
              ),
              _NavTile(
                index: 3,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                activeIndex: activeIndex,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Simple nav tile ───────────────────────────────────────────────────────────
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.activeIndex,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bool isActive = activeIndex == index;
    const Color active = Color(0xFF163E75);
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isActive ? activeIcon : icon,
              size: 24, color: isActive ? active : Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isActive ? active : Colors.grey.shade500,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal)),
        ],
      ),
    );
  }
}

// ── Nav tile with a dynamic red badge ─────────────────────────────────────────
class _NavBadgeTile extends StatelessWidget {
  const _NavBadgeTile({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.badgeCount, // Changed from String to int for real data
    required this.activeIndex,
    required this.onTap,
  });

  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bool isActive = activeIndex == index;
    const Color active = Color(0xFF163E75);
    
    // Limits the badge text to "99+" to prevent UI overflow if alerts are too many
    final displayBadge = badgeCount > 99 ? '99+' : badgeCount.toString();

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(isActive ? activeIcon : icon,
                  size: 24, color: isActive ? active : Colors.grey.shade500),
              
              // Only shows the red badge if there is actual dynamic data > 0
              if (badgeCount > 0)
                Positioned(
                  top: -4,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(displayBadge,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isActive ? active : Colors.grey.shade500,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal)),
        ],
      ),
    );
  }
}