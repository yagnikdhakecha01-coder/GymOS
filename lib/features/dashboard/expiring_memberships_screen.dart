import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../members/member_profile_screen.dart';
import '../../core/models/member.dart';

class ExpiringMembershipsScreen extends StatefulWidget {
  const ExpiringMembershipsScreen({super.key});

  @override
  State<ExpiringMembershipsScreen> createState() => _ExpiringMembershipsScreenState();
}

class _ExpiringMembershipsScreenState extends State<ExpiringMembershipsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Dummy list of expiring members
  final List<Map<String, dynamic>> _expiringMembers = [
    {
      'name': 'Rahul Patel',
      'plan': 'Gold Plan',
      'endDate': '29 May 2025',
      'daysLeft': 15,
      'avatar': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Priya Shah',
      'plan': 'Silver Plan',
      'endDate': '27 May 2025',
      'daysLeft': 13,
      'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Amit Verma',
      'plan': 'Platinum Plan',
      'endDate': '25 May 2025',
      'daysLeft': 11,
      'avatar': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Neha Joshi',
      'plan': 'Gold Plan',
      'endDate': '24 May 2025',
      'daysLeft': 10,
      'avatar': 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Rohan Mehta',
      'plan': 'Silver Plan',
      'endDate': '22 May 2025',
      'daysLeft': 8,
      'avatar': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Siddharth Singh',
      'plan': 'Gold Plan',
      'endDate': '21 May 2025',
      'daysLeft': 7,
      'avatar': 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Vivek Kumar',
      'plan': 'Platinum Plan',
      'endDate': '20 May 2025',
      'daysLeft': 6,
      'avatar': 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&q=80&w=100',
    },
    {
      'name': 'Anjali Kapoor',
      'plan': 'Silver Plan',
      'endDate': '19 May 2025',
      'daysLeft': 5,
      'avatar': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=100',
    },
  ];

  @override
  Widget build(BuildContext context) {
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
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined, color: AppTheme.textPrimary),
            onPressed: () {},
          ),
        ],
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
                children: const [
                  TextSpan(text: '18 ', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  TextSpan(text: 'Memberships expiring in next 15 days'),
                ],
              ),
            ),
          ),
          // List View
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _expiringMembers.length,
              itemBuilder: (context, index) {
                final memberData = _expiringMembers[index];
                return _buildMemberCard(memberData);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> data) {
    final int days = data['daysLeft'];
    final String daysText = '$days Days Left';

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
            // Navigate to MemberProfileScreen with a dummy Member model
            final dummyMember = Member(
              id: 'M10042',
              name: data['name'],
              email: '${data['name'].toString().toLowerCase().replaceAll(' ', '')}@gmail.com',
              phone: '+91 98765 43210',
              avatar: data['avatar'],
              status: 'Active',
              joinDate: '01 Jan 2026',
              membershipPlanId: 'p1',
              assignedWorkoutId: 'w1',
              assignedDietId: 'd1',
              medicalDetails: 'Focus on weight loss goal.',
              ptMember: true,
              ptTrainer: 't1',
              notes: 'Prefers morning sessions.',
              pendingAmount: 0.0,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MemberProfileScreen(member: dummyMember),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(data['avatar'], width: 40, height: 40, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['name'],
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data['plan'],
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ends on ${data['endDate']}',
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
                        color: const Color(0xFFFFF6ED),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        daysText,
                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
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
