import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../members/member_profile_screen.dart';
import '../members/members_viewmodel.dart';
import '../../core/models/member.dart';

class ExpiringMembershipsScreen extends StatefulWidget {
  final int initialTabIndex;
  const ExpiringMembershipsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ExpiringMembershipsScreen> createState() => _ExpiringMembershipsScreenState();
}

class _ExpiringMembershipsScreenState extends State<ExpiringMembershipsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int? _getDaysLeft(Member member) {
    final exp = member.extraFields['expiryDate'] as String?;
    if (exp == null || exp.isEmpty) return null;
    try {
      final parsed = DateTime.parse(exp);
      final today = DateTime.now();
      final todayDateOnly = DateTime(today.year, today.month, today.day);
      final expiryDateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      return expiryDateOnly.difference(todayDateOnly).inDays;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final allMembers = membersVm.allMembers;

    final expiredMembers = <Member>[];
    final todayMembers = <Member>[];
    final sevenDaysMembers = <Member>[];
    final fifteenDaysMembers = <Member>[];

    for (final member in allMembers) {
      final daysLeft = _getDaysLeft(member);
      if (daysLeft == null) continue;
      if (daysLeft >= -30 && daysLeft < 0) {
        expiredMembers.add(member);
      } else if (daysLeft == 0) {
        todayMembers.add(member);
      } else if (daysLeft >= 1 && daysLeft <= 7) {
        sevenDaysMembers.add(member);
      } else if (daysLeft >= 8 && daysLeft <= 15) {
        fifteenDaysMembers.add(member);
      }
    }

    List<Member> currentList;

    switch (_tabController.index) {
      case 0:
        currentList = fifteenDaysMembers;
        break;
      case 1:
        currentList = sevenDaysMembers;
        break;
      case 2:
        currentList = todayMembers;
        break;
      case 3:
      default:
        currentList = expiredMembers;
        break;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Expiring Memberships',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: Column(
        children: [
          // Tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.normal),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '15 Days'),
                  Tab(text: '7 Days'),
                  Tab(text: 'Today'),
                  Tab(text: 'Expired'),
                ],
              ),
            ),
          ),
          // Subtitle
          Container(
            width: double.infinity,
            color: AppTheme.background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                children: [
                  TextSpan(
                    text: '${currentList.length} ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  TextSpan(
                    text: _tabController.index == 0
                        ? 'Memberships expiring in next 15 days (8-15d)'
                        : _tabController.index == 1
                            ? 'Memberships expiring in next 7 days (1-7d)'
                            : _tabController.index == 2
                                ? 'Memberships expiring today'
                                : 'Memberships already expired',
                  ),
                ],
              ),
            ),
          ),
          // List View
          Expanded(
            child: currentList.isEmpty
                ? Center(
                    child: Text(
                      'No memberships found',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: currentList.length,
                    itemBuilder: (context, index) {
                      final member = currentList[index];
                      final daysLeft = _getDaysLeft(member) ?? 0;
                      return _buildMemberCard(member, daysLeft, membersVm);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(Member member, int daysLeft, MembersViewModel membersVm) {
    final plan = membersVm.getMemberPlan(member.membershipPlanId);
    final planTitle = plan?.title ?? 'No Plan';

    String daysText;
    Color daysColor;
    Color daysBgColor;

    if (daysLeft < 0) {
      daysText = '${daysLeft.abs()} Days Expired';
      daysColor = Colors.red;
      daysBgColor = const Color(0xFFFFECEF);
    } else if (daysLeft == 0) {
      daysText = 'Expires Today';
      daysColor = Colors.redAccent;
      daysBgColor = const Color(0xFFFFECEF);
    } else if (daysLeft == 1) {
      daysText = 'Expires Tomorrow';
      daysColor = Colors.redAccent;
      daysBgColor = const Color(0xFFFFECEF);
    } else {
      daysText = '$daysLeft Days Left';
      daysColor = Colors.orange;
      daysBgColor = const Color(0xFFFFF6ED);
    }

    String formattedExpiry = 'N/A';
    final exp = member.extraFields['expiryDate'] as String?;
    if (exp != null && exp.isNotEmpty) {
      try {
        final parsed = DateTime.parse(exp);
        formattedExpiry = DateFormat('dd MMM yyyy').format(parsed);
      } catch (_) {
        formattedExpiry = exp;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MemberProfileScreen(member: member),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: member.avatar.isNotEmpty && member.avatar.startsWith('http')
                      ? Image.network(member.avatar, width: 40, height: 40, fit: BoxFit.cover)
                      : Container(
                          width: 40,
                          height: 40,
                          color: AppTheme.primary.withOpacity(0.1),
                          child: const Icon(Icons.person, color: AppTheme.primary, size: 20),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        planTitle,
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ends on $formattedExpiry',
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: daysBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        daysText,
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: daysColor),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildIconBtn(Icons.phone_outlined, Colors.green),
                    const SizedBox(width: 4),
                    _buildIconBtn(Icons.chat_bubble_outline, Colors.green),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconBtn(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 14),
    );
  }
}
