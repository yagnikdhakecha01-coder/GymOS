import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/admin_theme.dart';
import '../theme/responsive.dart';
import '../providers/navigation_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

/// Menu item definition
class SidebarMenuItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const SidebarMenuItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// All sidebar menu items
const List<SidebarMenuItem> sidebarMenuItems = [
  SidebarMenuItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: 'Dashboard'),
  SidebarMenuItem(icon: Icons.fitness_center_outlined, activeIcon: Icons.fitness_center_rounded, label: 'Gyms'),
  SidebarMenuItem(icon: Icons.card_membership_outlined, activeIcon: Icons.card_membership_rounded, label: 'Subscriptions'),
  SidebarMenuItem(icon: Icons.attach_money_outlined, activeIcon: Icons.attach_money_rounded, label: 'Revenue'),
  SidebarMenuItem(icon: Icons.payment_outlined, activeIcon: Icons.payment_rounded, label: 'Payments'),
  SidebarMenuItem(icon: Icons.system_update_outlined, activeIcon: Icons.system_update_rounded, label: 'App Versions'),
  SidebarMenuItem(icon: Icons.toggle_on_outlined, activeIcon: Icons.toggle_on_rounded, label: 'Feature Control'),
  SidebarMenuItem(icon: Icons.notifications_outlined, activeIcon: Icons.notifications_rounded, label: 'Notifications'),
  SidebarMenuItem(icon: Icons.support_agent_outlined, activeIcon: Icons.support_agent_rounded, label: 'Support'),
  SidebarMenuItem(icon: Icons.content_copy_outlined, activeIcon: Icons.content_copy_rounded, label: 'Duplicates'),
  SidebarMenuItem(icon: Icons.analytics_outlined, activeIcon: Icons.analytics_rounded, label: 'Analytics'),
  SidebarMenuItem(icon: Icons.storage_outlined, activeIcon: Icons.storage_rounded, label: 'Database'),
  SidebarMenuItem(icon: Icons.history_outlined, activeIcon: Icons.history_rounded, label: 'Audit Logs'),
  SidebarMenuItem(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings'),
  SidebarMenuItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Admin Profile'),
];

class AdminScaffold extends StatelessWidget {
  final List<Widget> pages;

  const AdminScaffold({super.key, required this.pages});

  @override
  Widget build(BuildContext context) {
    final isMobile = AdminResponsive.isMobile(context);
    final navProvider = context.watch<NavigationProvider>();

    if (isMobile) {
      return Scaffold(
        appBar: _buildMobileAppBar(context),
        drawer: _buildDrawer(context),
        body: AnimatedSwitcher(
          duration: AdminTheme.animPage,
          child: pages[navProvider.selectedIndex],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _AdminSidebar(isExpanded: navProvider.isExpanded),
          Expanded(
            child: Column(
              children: [
                _AdminTopBar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AdminTheme.animPage,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey(navProvider.selectedIndex),
                      child: pages[navProvider.selectedIndex],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    return AppBar(
      title: Text(
        sidebarMenuItems[navProvider.selectedIndex].label,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      actions: [
        _ThemeToggle(),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: _AdminSidebar(isExpanded: true, isDrawer: true),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  final bool isExpanded;
  final bool isDrawer;

  const _AdminSidebar({required this.isExpanded, this.isDrawer = false});

  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final width = isExpanded ? AdminTheme.sidebarExpanded : AdminTheme.sidebarCollapsed;

    return AnimatedContainer(
      duration: AdminTheme.animNormal,
      curve: AdminTheme.animCurve,
      width: isDrawer ? AdminTheme.sidebarExpanded : width,
      decoration: BoxDecoration(
        color: AdminTheme.sidebarColor(context),
        border: isDrawer ? null : Border(
          right: BorderSide(color: AdminTheme.borderColor(context), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Logo area
          _buildLogo(context),
          const SizedBox(height: 8),
          // Menu items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded || isDrawer ? 12 : 8,
                vertical: 4,
              ),
              itemCount: sidebarMenuItems.length,
              itemBuilder: (ctx, i) {
                // Add section dividers
                if (i == 5 || i == 9 || i == 13) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        child: Divider(color: AdminTheme.borderColor(context), height: 1),
                      ),
                      _buildMenuItem(context, i, navProvider.selectedIndex == i),
                    ],
                  );
                }
                return _buildMenuItem(context, i, navProvider.selectedIndex == i);
              },
            ),
          ),
          // Collapse toggle (desktop only)
          if (!isDrawer)
            _buildCollapseButton(context),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final showFull = isExpanded || isDrawer;
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: showFull ? 20 : 0),
      alignment: showFull ? Alignment.centerLeft : Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AdminTheme.borderColor(context), width: 1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AdminTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
            ),
            child: const Center(
              child: Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ),
          if (showFull) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Gym OS',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textColor(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, int index, bool isSelected) {
    final item = sidebarMenuItems[index];
    final showFull = isExpanded || isDrawer;
    final isDark = AdminTheme.isDark(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
          onTap: () {
            context.read<NavigationProvider>().setIndex(index);
            if (isDrawer) Navigator.of(context).pop();
          },
          child: AnimatedContainer(
            duration: AdminTheme.animFast,
            padding: EdgeInsets.symmetric(
              horizontal: showFull ? 12 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AdminTheme.primary.withValues(alpha: isDark ? 0.15 : 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
            ),
            child: showFull
                ? Row(
                    children: [
                      Icon(
                        isSelected ? item.activeIcon : item.icon,
                        size: 20,
                        color: isSelected ? AdminTheme.primary : AdminTheme.secondaryTextColor(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.label,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  color: isSelected ? AdminTheme.primary : AdminTheme.secondaryTextColor(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.label == 'Support')
                              _buildSupportBadge(context),
                          ],
                        ),
                      ),
                    ],
                  )
                : Tooltip(
                    message: item.label,
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            size: 22,
                            color: isSelected ? AdminTheme.primary : AdminTheme.secondaryTextColor(context),
                          ),
                          if (item.label == 'Support')
                            Positioned(
                              top: -4,
                              right: -4,
                              child: _buildSupportBadge(context, isMini: true),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupportBadge(BuildContext context, {bool isMini = false}) {
    if (!AdminSupabaseService.isInitialized) return const SizedBox.shrink();
    return FutureBuilder<int>(
      future: AdminSupabaseService.client
          .from('support_tickets')
          .select('id')
          .eq('status', 'Open')
          .then((value) => value.length),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data! > 0) {
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMini ? 4 : 6,
              vertical: isMini ? 1 : 2,
            ),
            decoration: BoxDecoration(
              color: AdminTheme.danger,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${snapshot.data}',
              style: GoogleFonts.inter(
                fontSize: isMini ? 8 : 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildCollapseButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AdminTheme.borderColor(context), width: 1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        onTap: () => context.read<NavigationProvider>().toggleSidebar(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Icon(
            isExpanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            size: 22,
            color: AdminTheme.secondaryTextColor(context),
          ),
        ),
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final navProvider = context.watch<NavigationProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        border: Border(
          bottom: BorderSide(color: AdminTheme.borderColor(context), width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            sidebarMenuItems[navProvider.selectedIndex].label,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textColor(context),
            ),
          ),
          const Spacer(),
          // Search
          Container(
            width: 240,
            height: 38,
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search_rounded, size: 18, color: AdminTheme.mutedTextColor(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _ThemeToggle(),
          const SizedBox(width: 8),
          // Notifications bell
          _TopBarIconButton(
            icon: Icons.notifications_none_rounded,
            badge: '3',
            onTap: () {},
          ),
          const SizedBox(width: 8),
          // Profile
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusCard)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AdminTheme.primary,
                  child: Text(
                    (authProvider.userEmail ?? 'A')[0].toUpperCase(),
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.expand_more_rounded, size: 18, color: AdminTheme.secondaryTextColor(context)),
              ],
            ),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Super Admin', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
                    Text(authProvider.userEmail ?? '', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text('Profile', style: GoogleFonts.inter(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text('Settings', style: GoogleFonts.inter(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, size: 18, color: AdminTheme.danger),
                    const SizedBox(width: 8),
                    Text('Logout', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.danger)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                authProvider.logout();
              } else if (value == 'profile') {
                context.read<NavigationProvider>().setIndex(14);
              } else if (value == 'settings') {
                context.read<NavigationProvider>().setIndex(13);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final String? badge;
  final VoidCallback onTap;

  const _TopBarIconButton({required this.icon, this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 22, color: AdminTheme.secondaryTextColor(context)),
            if (badge != null)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AdminTheme.danger,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return InkWell(
      borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
      onTap: () => themeProvider.toggle(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        ),
        child: Icon(
          themeProvider.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          size: 20,
          color: AdminTheme.secondaryTextColor(context),
        ),
      ),
    );
  }
}
