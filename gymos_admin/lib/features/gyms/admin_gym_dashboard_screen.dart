import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/services/supabase_service.dart';
import 'package:intl/intl.dart';

class AdminGymDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> gym;

  const AdminGymDashboardScreen({super.key, required this.gym});

  @override
  State<AdminGymDashboardScreen> createState() => _AdminGymDashboardScreenState();
}

class _AdminGymDashboardScreenState extends State<AdminGymDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loadingFinance = true;
  bool _loadingMembers = true;
  bool _loadingStaff = true;

  double _totalRevenue = 0.0;
  double _totalExpense = 0.0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _staff = [];

  String _memberSearch = '';
  String _staffSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFinanceData();
    _loadMembersData();
    _loadStaffData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFinanceData() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _totalRevenue = 450000.00;
        _totalExpense = 120000.00;
        _transactions = [
          {'type': 'Revenue', 'category': 'Membership', 'amount': 1500.00, 'transaction_date': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(), 'notes': 'Monthly fee'},
          {'type': 'Expense', 'category': 'Rent', 'amount': 35000.00, 'transaction_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(), 'notes': 'Monthly Rent'},
          {'type': 'Revenue', 'category': 'Personal Training', 'amount': 8000.00, 'transaction_date': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(), 'notes': 'PT session package'},
          {'type': 'Expense', 'category': 'Utilities', 'amount': 4500.00, 'transaction_date': DateTime.now().subtract(const Duration(days: 4)).toIso8601String(), 'notes': 'Electricity bill'},
        ];
        _loadingFinance = false;
      });
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('finance_transactions')
          .select()
          .eq('gym_id', widget.gym['id'])
          .order('transaction_date', ascending: false);

      double rev = 0.0;
      double exp = 0.0;
      final txList = List<Map<String, dynamic>>.from(response);

      for (var tx in txList) {
        final amt = double.tryParse(tx['amount'].toString()) ?? 0.0;
        if (tx['type'] == 'Revenue') {
          rev += amt;
        } else if (tx['type'] == 'Expense') {
          exp += amt;
        }
      }

      setState(() {
        _totalRevenue = rev;
        _totalExpense = exp;
        _transactions = txList;
        _loadingFinance = false;
      });
    } catch (e) {
      debugPrint('Error loading finance data: $e');
      setState(() => _loadingFinance = false);
    }
  }

  Future<void> _loadMembersData() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _members = [
          {'full_name': 'Rahul Sharma', 'email': 'rahul@gmail.com', 'phone': '9876543210', 'membership_name': 'Gold Plan', 'status': 'Active', 'avatar_url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150'},
          {'full_name': 'Pooja Patel', 'email': 'pooja@gmail.com', 'phone': '9876543211', 'membership_name': 'Silver Plan', 'status': 'Active', 'avatar_url': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150'},
          {'full_name': 'Rohan Das', 'email': 'rohan@gmail.com', 'phone': '9876543212', 'membership_name': 'Gold Plan', 'status': 'Expired', 'avatar_url': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=150'},
        ];
        _loadingMembers = false;
      });
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('members')
          .select('*, member_memberships(membership_plans(name))')
          .eq('gym_id', widget.gym['id'])
          .order('created_at', ascending: false);

      final membersList = List<Map<String, dynamic>>.from(response);
      setState(() {
        _members = membersList.map((m) {
          final memberships = m['member_memberships'] as List?;
          final activeMem = memberships != null && memberships.isNotEmpty ? memberships.first : null;
          final planName = activeMem != null && activeMem['membership_plans'] != null 
              ? activeMem['membership_plans']['name'] as String? ?? 'No Plan'
              : 'No Plan';

          return {
            'id': m['id'],
            'full_name': m['full_name'] ?? 'Unnamed Member',
            'email': m['email'] ?? '-',
            'phone': m['phone_number'] ?? m['phone'] ?? '-',
            'membership_name': planName,
            'status': m['payment_status'] ?? 'Active',
            'avatar_url': m['avatar_url'] ?? m['photo_url'],
          };
        }).toList();
        _loadingMembers = false;
      });
    } catch (e) {
      debugPrint('Error loading members: $e');
      setState(() => _loadingMembers = false);
    }
  }

  Future<void> _loadStaffData() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _staff = [
          {'full_name': 'Vikram Rathore', 'email': 'vikram@fitzone.com', 'phone': '9876543220', 'role': 'Manager', 'salary': 35000.00, 'avatar_url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150'},
          {'full_name': 'Nehal Shah', 'email': 'nehal@fitzone.com', 'phone': '9876543221', 'role': 'Trainer', 'salary': 25000.00, 'avatar_url': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150'},
        ];
        _loadingStaff = false;
      });
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('staff')
          .select('*, profiles(*)')
          .eq('gym_id', widget.gym['id'])
          .order('created_at', ascending: false);

      final staffList = List<Map<String, dynamic>>.from(response);
      setState(() {
        _staff = staffList.map((s) {
          final profile = s['profiles'] as Map<String, dynamic>?;
          return {
            'full_name': profile?['full_name'] ?? s['name'] ?? 'Unnamed Staff',
            'email': profile?['email'] ?? '-',
            'phone': profile?['phone_number'] ?? s['phone'] ?? '-',
            'role': s['role'] ?? 'Staff',
            'salary': double.tryParse(s['salary']?.toString() ?? '0') ?? 0.0,
            'avatar_url': profile?['avatar_url'],
          };
        }).toList();
        _loadingStaff = false;
      });
    } catch (e) {
      debugPrint('Error loading staff: $e');
      setState(() => _loadingStaff = false);
    }
  }

  void _showMemberDetail(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: AdminTheme.primary.withValues(alpha: 0.1),
              backgroundImage: member['avatar_url'] != null ? NetworkImage(member['avatar_url']) : null,
              child: member['avatar_url'] == null 
                  ? const Icon(Icons.person_rounded, size: 40, color: AdminTheme.primary) 
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              member['full_name'],
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: (member['status'].toString().toLowerCase() == 'active' || member['status'].toString().toLowerCase() == 'paid') 
                    ? AdminTheme.success.withValues(alpha: 0.1) 
                    : AdminTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                member['status'],
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: (member['status'].toString().toLowerCase() == 'active' || member['status'].toString().toLowerCase() == 'paid') 
                      ? AdminTheme.success 
                      : AdminTheme.danger,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _profileField('Email Address', member['email']),
            const SizedBox(height: 12),
            _profileField('Phone Number', member['phone']),
            const SizedBox(height: 12),
            _profileField('Membership Plan', member['membership_name']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          )
        ],
      ),
    );
  }

  Widget _profileField(String label, String value) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.mutedTextColor(context))),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      backgroundColor: AdminTheme.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: AdminTheme.surfaceColor(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AdminTheme.textColor(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.gym['name'] ?? 'Gym Console',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
            ),
            Text(
              'Super Admin Management Portal • Privacy Enforced',
              style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AdminTheme.primary,
          unselectedLabelColor: AdminTheme.secondaryTextColor(context),
          indicatorColor: AdminTheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_rounded), text: 'Financials'),
            Tab(icon: Icon(Icons.people_rounded), text: 'Members'),
            Tab(icon: Icon(Icons.badge_rounded), text: 'Staff List'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Financials
          _loadingFinance 
              ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
              : _buildFinanceTab(currencyFormat),

          // Tab 2: Members
          _loadingMembers
              ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
              : _buildMembersTab(),

          // Tab 3: Staff
          _loadingStaff
              ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
              : _buildStaffTab(),
        ],
      ),
    );
  }

  Widget _buildFinanceTab(NumberFormat fmt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Row
          Row(
            children: [
              Expanded(
                child: _statCard(
                  'Total Revenue',
                  fmt.format(_totalRevenue),
                  Icons.arrow_upward_rounded,
                  AdminTheme.success,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _statCard(
                  'Total Expenses',
                  fmt.format(_totalExpense),
                  Icons.arrow_downward_rounded,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _statCard(
                  'Net Profit',
                  fmt.format(_totalRevenue - _totalExpense),
                  Icons.account_balance_wallet_rounded,
                  AdminTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Recent Ledger Transactions',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminTheme.borderColor(context)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tx = _transactions[index];
                final isRev = tx['type'] == 'Revenue';
                final amt = double.tryParse(tx['amount'].toString()) ?? 0.0;
                final date = tx['transaction_date'] != null 
                    ? DateTime.tryParse(tx['transaction_date'])?.toLocal().toString().substring(0, 16) ?? ''
                    : '';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRev ? AdminTheme.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    child: Icon(
                      isRev ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: isRev ? AdminTheme.success : Colors.red,
                      size: 18,
                    ),
                  ),
                  title: Text(tx['category'] ?? 'Other', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('${tx['notes'] ?? ""} • $date', style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                  trailing: Text(
                    '${isRev ? "+" : "-"}${fmt.format(amt)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isRev ? AdminTheme.success : Colors.red,
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    final filtered = _members.where((m) => m['full_name'].toString().toLowerCase().contains(_memberSearch.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _memberSearch = val),
            decoration: InputDecoration(
              hintText: 'Search members by name...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AdminTheme.surfaceColor(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              itemCount: filtered.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                childAspectRatio: 2.2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final m = filtered[index];
                return InkWell(
                  onTap: () => _showMemberDetail(m),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminTheme.borderColor(context)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: m['avatar_url'] != null ? NetworkImage(m['avatar_url']) : null,
                          child: m['avatar_url'] == null ? const Icon(Icons.person) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                m['full_name'],
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AdminTheme.textColor(context)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                m['membership_name'],
                                style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                m['phone'],
                                style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context)),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStaffTab() {
    final filtered = _staff.where((s) => s['full_name'].toString().toLowerCase().contains(_staffSearch.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _staffSearch = val),
            decoration: InputDecoration(
              hintText: 'Search staff by name...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AdminTheme.surfaceColor(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              itemCount: filtered.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                childAspectRatio: 2.2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final s = filtered[index];
                return Container(
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.borderColor(context)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: s['avatar_url'] != null ? NetworkImage(s['avatar_url']) : null,
                        child: s['avatar_url'] == null ? const Icon(Icons.badge_rounded) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              s['full_name'],
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AdminTheme.textColor(context)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s['role']} • Salary: ₹${s['salary']}',
                              style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s['phone'],
                              style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context)),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AdminTheme.secondaryTextColor(context))),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
