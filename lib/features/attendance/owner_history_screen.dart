import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import 'attendance_viewmodel.dart';

class OwnerAttendanceHistoryScreen extends StatefulWidget {
  const OwnerAttendanceHistoryScreen({super.key});

  @override
  State<OwnerAttendanceHistoryScreen> createState() => _OwnerAttendanceHistoryScreenState();
}

class _OwnerAttendanceHistoryScreenState extends State<OwnerAttendanceHistoryScreen> {
  int _selectedTab = 0;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Static dummy data matching the mockup
  final List<Map<String, dynamic>> _dummyLogs = [
    {
      'name': 'Amit Patel',
      'checkIn': '09:14 AM',
      'checkOut': '07:08 PM',
      'hours': '09h 54m',
      'status': 'Present',
      'avatar': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=150',
    },
    {
      'name': 'Priya Shah',
      'checkIn': '09:05 AM',
      'checkOut': '06:30 PM',
      'hours': '09h 25m',
      'status': 'Present',
      'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=150',
    },
    {
      'name': 'Vivek Singh',
      'checkIn': '09:20 AM',
      'checkOut': '05:40 PM',
      'hours': '08h 20m',
      'status': 'Present',
      'avatar': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=150',
    },
    {
      'name': 'Siddharth Verma',
      'checkIn': '--',
      'checkOut': '--',
      'hours': '--',
      'status': 'Absent',
      'avatar': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=150',
    },
    {
      'name': 'Neha Joshi',
      'checkIn': '09:10 AM',
      'checkOut': '07:16 PM',
      'hours': '10h 06m',
      'status': 'Present',
      'avatar': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&q=80&w=150',
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _dummyLogs.where((l) {
      return l['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final presentCount = _dummyLogs.where((l) => l['status'] == 'Present').length;
    final absentCount = _dummyLogs.where((l) => l['status'] == 'Absent').length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Attendance History',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded, color: AppTheme.textSecondary, size: 22),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              children: [
                // ── Tab Pills ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _tabPill('Day', 0),
                      _tabPill('Week', 1),
                      _tabPill('Month', 2),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Date Navigation ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.textSecondary),
                      onPressed: () {},
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '14 May 2025',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                      onPressed: () {},
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Summary Stats Row ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _miniStat('Total Staff', '18', AppTheme.textPrimary),
                    _miniStat('Present', '$presentCount', const Color(0xFF16A34A)),
                    _miniStat('Absent', '$absentCount', const Color(0xFFEF4444)),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Search Bar ──
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF0F0F2)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: GoogleFonts.inter(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search staff...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── Attendance List ──
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, index) {
                final item = filtered[index];
                return _AttendanceCard(data: item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// ── Attendance Card ──
class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AttendanceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String;
    final isAbsent = status == 'Absent';

    Color badgeBg;
    Color badgeText;
    if (status == 'Present') {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF16A34A);
    } else if (status == 'Late') {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else {
      badgeBg = const Color(0xFFFEE2E2);
      badgeText = const Color(0xFFEF4444);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(data['avatar']),
          ),
          const SizedBox(width: 12),

          // Name & Times
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name'],
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  isAbsent ? 'Not checked in' : '${data['checkIn']} - ${data['checkOut']}',
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),

          // Hours
          if (!isAbsent) ...[
            Text(
              data['hours'],
              style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 10),
          ],

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: badgeText),
            ),
          ),
        ],
      ),
    );
  }
}
