import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import '../widgets/member_activity_heatmap_widget.dart';
import '../widgets/member_muscle_map_widget.dart';

class MemberAchievementsScreen extends StatefulWidget {
  const MemberAchievementsScreen({super.key});

  @override
  State<MemberAchievementsScreen> createState() => _MemberAchievementsScreenState();
}

class _MemberAchievementsScreenState extends State<MemberAchievementsScreen> with TickerProviderStateMixin {
  String _selectedFilter = 'All'; // All | Unlocked | Locked
  bool _showLevelUpCelebration = false;
  int _celebratedLevel = 1;
  String _celebratedTitle = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLevelUp();
    });
  }

  Future<void> _checkLevelUp() async {
    final vm = Provider.of<MemberAppViewModel>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final lastCelebratedLevel = prefs.getInt('last_celebrated_level') ?? 1;

    if (vm.currentLevel > lastCelebratedLevel) {
      setState(() {
        _showLevelUpCelebration = true;
        _celebratedLevel = vm.currentLevel;
        _celebratedTitle = vm.currentTitle;
      });
      await prefs.setInt('last_celebrated_level', vm.currentLevel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        // Filter & Sort Achievements (Unlocked first, Locked later)
        final filteredList = vm.achievements.where((badge) {
          if (_selectedFilter == 'Unlocked') return badge['unlocked'] == true;
          if (_selectedFilter == 'Locked') return badge['unlocked'] != true;
          return true;
        }).toList();

        filteredList.sort((a, b) {
          final aUnlocked = a['unlocked'] == true ? 0 : 1;
          final bUnlocked = b['unlocked'] == true ? 0 : 1;
          return aUnlocked.compareTo(bUnlocked);
        });

        // Calculate progress totals
        final unlockedCount = vm.achievements.where((a) => a['unlocked'] == true).length;
        final totalBadges = vm.achievements.length;

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Premium Silver App Bar
                  SliverAppBar(
                    expandedHeight: 120.0,
                    floating: false,
                    pinned: true,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    backgroundColor: Colors.white,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        'Achievements',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      centerTitle: true,
                      background: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.5)),
                        ),
                      ),
                    ),
                  ),

                  // Content Body
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),

                        // ═══════ PREMIUM LEVEL CARD ═══════
                        _buildPremiumLevelCard(vm),
                        const SizedBox(height: 24),

                        // ═══════ STATS SUMMARY ═══════
                        _buildStatsSummary(vm, unlockedCount, totalBadges),
                        const SizedBox(height: 24),

                        // ═══════ ACTIVITY HEATMAP ═══════
                        _buildSectionHeader('📅 Activity This Year'),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: MemberActivityHeatmapWidget(
                              memberId: vm.memberId,
                              gymId: _getGymId(vm),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ═══════ MUSCLE MAP ═══════
                        _buildSectionHeader('💪 Muscle Training Map'),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: AppTheme.cardShadow,
                            ),
                            child: MemberMuscleMapWidget(
                              memberId: vm.memberId,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ═══════ BADGES FILTER CHIPS ═══════
                        _buildSectionHeader('🏅 Badges'),
                        const SizedBox(height: 8),
                        // ═══════ BADGES FILTER CHIPS ═══════
                        _buildFilterRow(),
                        const SizedBox(height: 16),

                        // List Empty State
                        if (filteredList.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  const Text('🔍', style: TextStyle(fontSize: 48)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No badges found matching this filter.',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ═══════ BADGES GRID ═══════
                  if (filteredList.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.85,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final badge = filteredList[index];
                            return _buildBadgeCard(badge);
                          },
                          childCount: filteredList.length,
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),

              // Level Up Overlay Celebration
              if (_showLevelUpCelebration)
                _LevelUpCelebrationOverlay(
                  level: _celebratedLevel,
                  title: _celebratedTitle,
                  onClose: () {
                    setState(() {
                      _showLevelUpCelebration = false;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  String _getGymId(MemberAppViewModel vm) {
    // Try to get gymId from SharedPreferences synchronously (it's cached)
    // If not available, use empty string — heatmap will handle gracefully
    return '';
  }

  Widget _buildPremiumLevelCard(MemberAppViewModel vm) {
    final double xpProgress = vm.nextLevelXP > 0 ? (vm.currentXP / vm.nextLevelXP) : 0.0;
    final int progressPercent = (xpProgress * 100).round();


    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9), Color(0xFF4C1D95)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative background patterns
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              left: -40,
              bottom: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Text('🏆', style: TextStyle(fontSize: 28)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LEVEL ${vm.currentLevel}',
                              style: GoogleFonts.inter(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                vm.currentTitle,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // XP details
                  Row(
                    children: [
                      Text(
                        'Progress',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${vm.currentXP} / ${vm.nextLevelXP} XP',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Animated Progress bar
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: xpProgress),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.fastOutSlowIn,
                    builder: (context, val, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: val,
                              minHeight: 10,
                              backgroundColor: Colors.white.withOpacity(0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$progressPercent%',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummary(MemberAppViewModel vm, int unlocked, int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Stat 1: Unlocked Badges
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Badges Unlocked',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('🏅', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(
                        '$unlocked / $total',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Stat 2: Streak info
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Streak Streak',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(
                        '${vm.currentStreak} Days',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: ['All', 'Unlocked', 'Locked'].map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFilter = filter;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0),
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: AppTheme.primary.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Text(
                  filter,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBadgeCard(Map<String, dynamic> badge) {
    final bool unlocked = badge['unlocked'] == true;
    final int progress = badge['progress'] ?? 0;
    final int target = badge['target'] ?? 1;
    final String key = badge['key'] ?? '';
    final isSpecial = (key == 'never_miss_gym' || key == 'gymos_legend' || key == 'club_365');
    final double progressVal = target > 0 ? (progress / target) : 0.0;

    return GestureDetector(
      onTap: () => _showBadgeDetailBottomSheet(badge),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: unlocked 
                ? (isSpecial ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0))
                : const Color(0xFFF1F5F9),
            width: unlocked ? (isSpecial ? 2.5 : 1.5) : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: unlocked 
                  ? (isSpecial ? const Color(0xFFF59E0B).withOpacity(0.12) : Colors.black.withOpacity(0.02))
                  : Colors.transparent,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Emoji Container
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: unlocked 
                          ? (badge['color'] as Color).withOpacity(0.12)
                          : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        badge['icon']?.toString() ?? '🏅',
                        style: TextStyle(
                          fontSize: 22,
                          color: unlocked ? null : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Unlock / Lock status icon
                  Icon(
                    unlocked ? Icons.check_circle_rounded : Icons.lock_rounded,
                    color: unlocked 
                        ? (isSpecial ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                        : AppTheme.textMuted.withOpacity(0.7),
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Title
              Text(
                badge['title']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: unlocked ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 4),

              // Description
              Expanded(
                child: Text(
                  badge['description']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Progress bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progressVal,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          unlocked 
                              ? (isSpecial ? const Color(0xFFF59E0B) : AppTheme.primary)
                              : Colors.grey.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$progress/$target',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: unlocked ? AppTheme.textPrimary : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBadgeDetailBottomSheet(Map<String, dynamic> badge) {
    final bool unlocked = badge['unlocked'] == true;
    final int progress = badge['progress'] ?? 0;
    final int target = badge['target'] ?? 1;
    final String key = badge['key'] ?? '';
    final isSpecial = (key == 'never_miss_gym' || key == 'gymos_legend' || key == 'club_365');
    final double progressVal = target > 0 ? (progress / target) : 0.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull Bar
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 32),

              // Large Badge Icon
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: unlocked 
                      ? (badge['color'] as Color).withOpacity(0.12)
                      : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: unlocked 
                        ? (isSpecial ? const Color(0xFFF59E0B) : (badge['color'] as Color))
                        : Colors.transparent,
                    width: unlocked ? 3 : 0,
                  ),
                ),
                child: Center(
                  child: Text(
                    badge['icon']?.toString() ?? '🏆',
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Name
              Text(
                badge['title']?.toString() ?? '',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // Unlocked status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: unlocked 
                      ? const Color(0xFFD1FAE5) 
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      unlocked ? Icons.check_circle : Icons.lock,
                      color: unlocked ? const Color(0xFF059669) : Colors.grey,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      unlocked ? 'Unlocked' : 'Locked',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: unlocked ? const Color(0xFF059669) : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Detailed Description
              Text(
                badge['description']?.toString() ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),

              // Requirement Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  children: [
                    Text(
                      'HOW TO UNLOCK',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      badge['requirement']?.toString() ?? '',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Progress details
              Row(
                children: [
                  Text(
                    'Progress',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$progress / $target Days',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progressVal,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    unlocked 
                        ? (isSpecial ? const Color(0xFFF59E0B) : AppTheme.primary)
                        : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // XP Reward indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💎', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(
                    '+${badge['xp_reward']} XP Reward',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Close Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Got It',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════ CUSTOM OVERLAY CELEBRATING LEVEL UP ═══════
class _LevelUpCelebrationOverlay extends StatefulWidget {
  final int level;
  final String title;
  final VoidCallback onClose;

  const _LevelUpCelebrationOverlay({
    required this.level,
    required this.title,
    required this.onClose,
  });

  @override
  State<_LevelUpCelebrationOverlay> createState() => _LevelUpCelebrationOverlayState();
}

class _LevelUpCelebrationOverlayState extends State<_LevelUpCelebrationOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Spawn 60 colorful particles
    final random = Random();
    _particles = List.generate(60, (index) {
      return _ConfettiParticle(
        x: random.nextDouble() * 400 - 200,
        y: random.nextDouble() * -500 - 100,
        speed: random.nextDouble() * 200 + 150,
        size: random.nextDouble() * 8 + 6,
        color: Colors.primaries[random.nextInt(Colors.primaries.length)],
        angle: random.nextDouble() * 2 * pi,
        spin: random.nextDouble() * 5,
      );
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withOpacity(0.85),
      child: Stack(
        children: [
          // Falling Confetti animation using CustomPainter
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: _ConfettiPainter(
                  particles: _particles,
                  time: _animController.value,
                ),
              );
            },
          ),

          // Central Celebratory Card
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                  CurvedAnimation(parent: _animController, curve: const Interval(0, 0.15, curve: Curves.elasticOut)),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.1),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      Text(
                        'LEVEL UP!',
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You reached Level ${widget.level}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: widget.onClose,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Awesome!',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiParticle {
  double x;
  double y;
  final double speed;
  final double size;
  final Color color;
  final double angle;
  final double spin;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
    required this.angle,
    required this.spin,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double time;

  _ConfettiPainter({required this.particles, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final midX = size.width / 2;

    for (var p in particles) {
      // Calculate current position
      final double fallY = p.y + (p.speed * time * 5);
      final double fallX = midX + p.x + (25 * sin(time * 2 * pi + p.angle));

      // Reset when falling off-screen
      if (fallY > size.height) {
        p.y = -50;
      }

      paint.color = p.color;

      canvas.save();
      canvas.translate(fallX, fallY);
      canvas.rotate(time * p.spin * pi);

      // Draw confetti rectangle or circle
      if (p.size % 2 == 0) {
        canvas.drawRect(Rect.fromLTWH(-p.size / 2, -p.size / 2, p.size, p.size * 1.5), paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
