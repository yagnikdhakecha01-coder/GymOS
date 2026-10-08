import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/sparkline.dart';
import 'members_viewmodel.dart';
import '../../core/models/member.dart';
import '../../core/navigation/app_router.dart';
import 'member_profile_screen.dart';
import 'trial_members_viewmodel.dart';
import 'trial_member_details_screen.dart';
import '../../core/widgets/add_member_selection_sheet.dart';
import '../attendance/attendance_viewmodel.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/app_cached_avatar.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late ScrollController _scrollController;
  late TextEditingController _searchController;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showAddMemberSheet(BuildContext context) {
    AddMemberSelectionSheet.show(context);
  }

  Widget _buildMemberPaymentBadge(Member member) {
    final double pending = member.pendingAmount;
    final bool isPaid = pending <= 0 || member.paymentStatus.toLowerCase() == 'paid';
    final Color badgeBg = isPaid ? const Color(0xFFE6FDF4) : const Color(0xFFFFF0F0);
    final Color badgeBorder = isPaid ? const Color(0xFFA7F3D0) : const Color(0xFFFFD4D4);
    final Color iconColor = isPaid ? const Color(0xFF10B981) : const Color(0xFFDC2626);
    final Color amountColor = isPaid ? const Color(0xFF047857) : const Color(0xFFDC2626);
    final Color labelColor = isPaid ? const Color(0xFF059669) : const Color(0xFFEF4444);
    final String labelText = isPaid ? 'Fees Paid' : 'Fees Pending';
    final IconData badgeIcon = isPaid ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined;
    final String formattedAmount = isPaid ? 'Done' : '₹${NumberFormat('#,##,###').format(pending.abs())}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badgeIcon,
            size: 12,
            color: iconColor,
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formattedAmount,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              Text(
                labelText,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicCardBadge(Member member, MemberSortOption sortOption) {
    switch (sortOption) {
      case MemberSortOption.pendingFeesFirst:
        return _buildMemberPaymentBadge(member);

      case MemberSortOption.expiringSoon:
        final exp = member.parsedExpiryDate;
        if (exp == null) {
          return _buildMemberPaymentBadge(member);
        }
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final expDay = DateTime(exp.year, exp.month, exp.day);
        final diff = expDay.difference(today).inDays;

        if (diff < 0) {
          final daysAgo = diff.abs();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD4D4), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFDC2626)),
                const SizedBox(width: 4),
                Text(
                  daysAgo == 0 ? 'Expired' : 'Expired ${daysAgo}d ago',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          );
        } else if (diff <= 7) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 12, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
                Text(
                  diff == 0 ? 'Expires Today' : 'Expires in ${diff}d',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFD97706),
                  ),
                ),
              ],
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0), width: 0.8),
            ),
            child: Text(
              'Expires in ${diff}d',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF16A34A),
              ),
            ),
          );
        }

      case MemberSortOption.recentlyJoined:
        final join = member.parsedJoinDate;
        String joinText = 'New Member';
        if (join != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final jDay = DateTime(join.year, join.month, join.day);
          final diff = today.difference(jDay).inDays;
          if (diff == 0) {
            joinText = 'Joined Today';
          } else if (diff == 1) {
            joinText = 'Joined Yesterday';
          } else if (diff <= 30) {
            joinText = 'Joined ${diff}d ago';
          } else {
            joinText = 'Joined ${DateFormat('dd MMM').format(join)}';
          }
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC7D2FE), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_add_alt_1, size: 12, color: Color(0xFF4F46E5)),
              const SizedBox(width: 4),
              Text(
                joinText,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
        );

      case MemberSortOption.alphabetical:
        return _buildMemberPaymentBadge(member);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final attendanceVm = Provider.of<AttendanceViewModel>(context);
    final trialsVm = Provider.of<TrialMembersViewModel>(context);
    final allMembers = membersVm.filteredMembers;
    final totalCount = membersVm.allMembers.length;
    final activeCount = membersVm.activeMembersCount;
    final inactiveCount = membersVm.inactiveMembersCount;
    final trialCount = trialsVm.allTrials.length;

    final checkInRecords = attendanceVm.todayRecords.where((r) => r.status == 'Present').length;
    final totalPending = membersVm.totalPendingAmount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppTheme.pagePadding, 16, AppTheme.pagePadding, 12),
                    child: _isSearching
                          ? Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_rounded, size: 22, color: AppTheme.textPrimary),
                                    onPressed: () {
                                      setState(() {
                                        _isSearching = false;
                                        _searchController.clear();
                                      });
                                      membersVm.setSearchQuery('');
                                      trialsVm.setSearchQuery('');
                                    },
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      autofocus: true,
                                      onChanged: (val) {
                                        membersVm.setSearchQuery(val);
                                        trialsVm.setSearchQuery(val);
                                        setState(() {});
                                      },
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: 'Search by name or mobile number...',
                                        hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textMuted),
                                      onPressed: () {
                                        _searchController.clear();
                                        membersVm.setSearchQuery('');
                                        trialsVm.setSearchQuery('');
                                        setState(() {});
                                      },
                                    ),
                                ],
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Members',
                                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    Text(
                                      'All members overview',
                                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.search_rounded, color: AppTheme.textPrimary, size: 24),
                                      onPressed: () {
                                        setState(() {
                                          _isSearching = true;
                                        });
                                      },
                                    ),
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.filter_list_rounded,
                                            color: membersVm.sortOption != MemberSortOption.pendingFeesFirst
                                                ? AppTheme.primary
                                                : AppTheme.textPrimary,
                                            size: 24,
                                          ),
                                          onPressed: () => MemberFilterBottomSheet.show(context),
                                        ),
                                        if (membersVm.sortOption != MemberSortOption.pendingFeesFirst)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _showAddMemberSheet(context),
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.add, color: Colors.white, size: 22),
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                      child: ResponsiveGrid(
                        crossAxisCountMobile: 2,
                        crossAxisCountTablet: 4,
                        spacing: 12,
                        runSpacing: 12,
                        childAspectRatio: context.selectValue(mobile: 1.35, smallMobile: 1.05, tablet: 1.6),
                        children: [
                          _buildSparklineStat(
                            title: 'Attendance',
                            value: '$checkInRecords',
                            subtitle: 'Check-ins today',
                            trend: '↑ 0%',
                            trendLabel: 'vs yesterday',
                            trendColor: AppTheme.success,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, checkInRecords.toDouble()],
                            sparklineColor: AppTheme.primary,
                          ),
                          _buildSparklineStat(
                            title: 'Active Members',
                            value: '$activeCount',
                            subtitle: 'Total active members',
                            trend: '↑ 0%',
                            trendLabel: 'vs last month',
                            trendColor: AppTheme.success,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, activeCount.toDouble()],
                            sparklineColor: AppTheme.success,
                          ),
                          _buildSparklineStat(
                            title: 'Pending Amount',
                            value: '₹ ${NumberFormat('#,##,###').format(totalPending)}',
                            subtitle: 'Total pending',
                            trend: '↑ 0%',
                            trendLabel: 'vs last month',
                            trendColor: AppTheme.danger,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, totalPending.toDouble()],
                            sparklineColor: AppTheme.warning,
                          ),
                          _buildSparklineStat(
                            title: 'PT Members',
                            value: '0',
                            subtitle: 'Personal training',
                            trend: '↑ 0%',
                            trendLabel: 'vs last month',
                            trendColor: AppTheme.success,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                            sparklineColor: AppTheme.info,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _MembersHeaderDelegate(
                height: 56.0,
                cacheKey: '${membersVm.selectedFilter}_${totalCount}_${activeCount}_${inactiveCount}_$trialCount',
                child: SizedBox.expand(
                  child: Container(
                    color: AppTheme.background,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildMockTab('All ($totalCount)', membersVm.selectedFilter == 'All', () {
                          membersVm.setFilter('All');
                        }),
                        _buildMockTab('Active ($activeCount)', membersVm.selectedFilter == 'Active', () {
                          membersVm.setFilter('Active');
                        }),
                        _buildMockTab('Inactive ($inactiveCount)', membersVm.selectedFilter == 'Inactive', () {
                          membersVm.setFilter('Inactive');
                        }),
                        _buildMockTab('Trial ($trialCount)', membersVm.selectedFilter == 'Trial', () {
                          membersVm.setFilter('Trial');
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (membersVm.selectedFilter == 'Trial')
              if (trialsVm.filteredTrials.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 80.0),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_ind_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No Trials Found',
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Trial members will appear here.',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final trial = trialsVm.filteredTrials[index];
                        final status = trial.calculatedStatus;
                        final startText = DateFormat('dd MMM').format(DateTime.parse(trial.startDate));
                        final endText = DateFormat('dd MMM yyyy').format(DateTime.parse(trial.endDate));

                        return CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => TrialMemberDetailsScreen(trial: trial)),
                            );
                          },
                          child: Row(
                            children: [
                              AppCachedAvatar(
                                imageUrl: trial.avatar,
                                name: trial.name,
                                size: 44,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trial.name,
                                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      trial.phone,
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_month_outlined, size: 12, color: AppTheme.textMuted),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$startText - $endText (${trial.trialDays} days)',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: status == 'Converted' 
                                          ? const Color(0xFFEEF2FF)
                                          : (status == 'Expired' ? const Color(0xFFFEF2F2) : const Color(0xFFE6F4EA)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      status,
                                      style: GoogleFonts.inter(
                                        fontSize: 9, 
                                        fontWeight: FontWeight.bold, 
                                        color: status == 'Converted' 
                                            ? const Color(0xFF4F46E5) 
                                            : (status == 'Expired' ? const Color(0xFFEF4444) : const Color(0xFF16A34A))
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    trial.trialType == 'Paid' ? 'Paid' : 'Free',
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: trialsVm.filteredTrials.length,
                    ),
                  ),
                )
            else if (allMembers.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 80.0),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'No Members Found',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Members added to this category will appear here.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final member = allMembers[index];
                      final isTrial = member.status == 'Trial';
                      
                      String nextDueStr = 'N/A';
                      final exp = member.parsedExpiryDate;
                      if (exp != null) {
                        nextDueStr = DateFormat('dd MMM yyyy').format(exp);
                      } else {
                        final rawExp = member.extraFields['expiryDate'] as String?;
                        if (rawExp != null && rawExp.isNotEmpty) {
                          nextDueStr = rawExp;
                        }
                      }

                      String subtitleText;
                      if (isTrial) {
                        subtitleText = 'Trial Subscription';
                      } else {
                        switch (membersVm.sortOption) {
                          case MemberSortOption.expiringSoon:
                            subtitleText = exp != null ? 'Expires: $nextDueStr' : 'Next Due: $nextDueStr';
                            break;
                          case MemberSortOption.recentlyJoined:
                            subtitleText = member.joinDate.isNotEmpty ? 'Joined: ${member.joinDate}' : 'Next Due: $nextDueStr';
                            break;
                          case MemberSortOption.pendingFeesFirst:
                          case MemberSortOption.alphabetical:
                            subtitleText = member.pendingAmount > 0
                                ? 'Next Due: $nextDueStr • Fees Pending'
                                : 'Next Due: $nextDueStr';
                            break;
                        }
                      }

                      return RepaintBoundary(
                        child: CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          onTap: () {
                            Navigator.push(context, AppRouter.slideRoute(MemberProfileScreen(member: member)));
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  AppCachedAvatar(
                                    imageUrl: member.avatar,
                                    name: member.name,
                                    size: 44,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          member.name,
                                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          member.phone,
                                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitleText,
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!isTrial) ...[
                                    _buildDynamicCardBadge(member, membersVm.sortOption),
                                    const SizedBox(width: 6),
                                  ],
                                  const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Member Status',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: member.status == 'Active'
                                          ? const Color(0xFFE6F4EA)
                                          : (member.status == 'Pending Activation'
                                              ? Colors.orange.withOpacity(0.1)
                                              : Colors.grey.withOpacity(0.1)),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          member.status == 'Active' ? Icons.check : Icons.circle,
                                          size: 10,
                                          color: member.status == 'Active'
                                              ? const Color(0xFF16A34A)
                                              : (member.status == 'Pending Activation'
                                                  ? Colors.orange
                                                  : Colors.grey),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          member.status,
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: member.status == 'Active' ? const Color(0xFF15803D) : AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: allMembers.length,
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: false,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMockTab(String title, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSparklineStat({
    required String title,
    required String value,
    required String subtitle,
    required String trend,
    required String trendLabel,
    required Color trendColor,
    required List<double> sparklineData,
    required Color sparklineColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: sparklineColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  title.contains('Attendance') 
                      ? Icons.calendar_today_rounded 
                      : (title.contains('Active') 
                          ? Icons.people_rounded 
                          : (title.contains('Pending') ? Icons.currency_rupee_rounded : Icons.person_add_alt_1_rounded)),
                  color: sparklineColor,
                  size: 16,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    title,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              MiniSparkline(data: sparklineData, color: sparklineColor),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                trend,
                style: GoogleFonts.inter(fontSize: 10, color: trendColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  trendLabel,
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MembersHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  final String cacheKey;

  _MembersHeaderDelegate({required this.height, required this.child, required this.cacheKey});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _MembersHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.cacheKey != cacheKey;
  }
}

class AddMemberSheet extends StatefulWidget {
  const AddMemberSheet({super.key});

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedPlanId = '1';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context, listen: false);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Register New Member', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Text('Full Name', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _nameController, decoration: const InputDecoration(hintText: 'e.g. Aman Gupta')),
            const SizedBox(height: 12),

            Text('Email Address', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _emailController, decoration: const InputDecoration(hintText: 'e.g. aman@gmail.com')),
            const SizedBox(height: 12),

            Text('Phone Number', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _phoneController, decoration: const InputDecoration(hintText: 'e.g. 98234 56789')),
            const SizedBox(height: 12),

            Text('Membership Plan', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedPlanId,
              items: const [
                DropdownMenuItem(value: '1', child: Text('Silver Monthly Plan (₹1,500)')),
                DropdownMenuItem(value: '2', child: Text('Gold Quarterly Plan (₹4,000)')),
                DropdownMenuItem(value: '3', child: Text('Platinum Annual Plan (₹12,000)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedPlanId = val);
              },
            ),
            const SizedBox(height: 20),

            CustomButton(
              text: 'Save Member',
              onPressed: () async {
                if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter name and email'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }
                await membersVm.addMember(
                  name: _nameController.text,
                  email: _emailController.text,
                  phone: _phoneController.text,
                  joinDate: '16 Jul 2026',
                  membershipPlanId: _selectedPlanId,
                  ptMember: false,
                  ptTrainer: '',
                  medicalDetails: 'None',
                  notes: '',
                  pendingAmount: 0.0,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Member added successfully!'), backgroundColor: AppTheme.success),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class MemberFilterBottomSheet extends StatelessWidget {
  const MemberFilterBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const MemberFilterBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final activeSort = membersVm.sortOption;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sort & Filter View',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Choose how member cards are organized',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildOptionTile(
              context: context,
              title: 'Pending Fees (Default)',
              subtitle: 'Highest pending dues first with fee alert badges',
              icon: Icons.account_balance_wallet_outlined,
              iconColor: const Color(0xFFDC2626),
              bgColor: const Color(0xFFFFF1F2),
              isSelected: activeSort == MemberSortOption.pendingFeesFirst,
              onTap: () {
                membersVm.setSortOption(MemberSortOption.pendingFeesFirst);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            _buildOptionTile(
              context: context,
              title: 'Expiring Soon & Expired',
              subtitle: 'Expired & soon-to-expire members for quick renewal',
              icon: Icons.alarm_rounded,
              iconColor: const Color(0xFFEA580C),
              bgColor: const Color(0xFFFFF7ED),
              isSelected: activeSort == MemberSortOption.expiringSoon,
              onTap: () {
                membersVm.setSortOption(MemberSortOption.expiringSoon);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            _buildOptionTile(
              context: context,
              title: 'Recently Joined',
              subtitle: 'Newest registered members on top',
              icon: Icons.person_add_alt_1_outlined,
              iconColor: const Color(0xFF4F46E5),
              bgColor: const Color(0xFFEEF2FF),
              isSelected: activeSort == MemberSortOption.recentlyJoined,
              onTap: () {
                membersVm.setSortOption(MemberSortOption.recentlyJoined);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            _buildOptionTile(
              context: context,
              title: 'Alphabetical (A - Z)',
              subtitle: 'Sorted alphabetically by member name',
              icon: Icons.sort_by_alpha_rounded,
              iconColor: const Color(0xFF0D9488),
              bgColor: const Color(0xFFF0FDFA),
              isSelected: activeSort == MemberSortOption.alphabetical,
              onTap: () {
                membersVm.setSortOption(MemberSortOption.alphabetical);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryLight.withValues(alpha: 0.35) : AppTheme.surfaceGray,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 20)
            else
              const Icon(Icons.circle_outlined, color: AppTheme.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
