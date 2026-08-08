import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../../core/repository/gym_repository.dart';
import '../../../core/services/supabase_service.dart';
import 'client_details_screen.dart';
import '../../../core/models/member.dart';

class StaffClientsScreen extends StatefulWidget {
  const StaffClientsScreen({super.key});

  @override
  State<StaffClientsScreen> createState() => _StaffClientsScreenState();
}

class _StaffClientsScreenState extends State<StaffClientsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _ptClients = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final repo = Provider.of<GymRepository>(context, listen: false);
      final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;

      if (profileUserId != null) {
        final matchingStaff = repo.getStaff().where((s) => s.userId == profileUserId).toList();
        final staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;

        if (staff != null) {
          final response = await SupabaseService.client
              .from('pt_assignments')
              .select('*, members(*)')
              .eq('staff_id', staff.id);

          final List rawList = response as List;
          final List<Map<String, dynamic>> clients = [];
          for (var item in rawList) {
            final memberJson = item['members'];
            if (memberJson != null) {
              final member = Member.fromJson(memberJson);
              clients.add({
                'member': member,
                'program': 'PT - ' + ((item['commission_percentage'] as num?)?.toString() ?? '0') + '% Comm.',
                'status': item['assignment_status'] ?? 'Active',
                'name': member.name,
                'image': member.avatar.isNotEmpty ? member.avatar : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=150',
                'phone': member.phone,
              });
            }
          }
          if (mounted) {
            setState(() {
              _ptClients = clients;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading PT clients: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredClients = _ptClients.where((c) {
      final name = c['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    final totalCount = _ptClients.length;
    final activeCount = _ptClients.where((c) => c['status'] == 'Active').length;
    final inactiveCount = _ptClients.where((c) => c['status'] == 'Inactive' || c['status'] == 'Trial').length;
    final completedCount = _ptClients.where((c) => c['status'] == 'Completed').length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: const SizedBox.shrink(),
        title: Text(
          'My Clients (PT)',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: _loadClients,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildHeaderStat('Total PT Clients', totalCount.toString(), Colors.blue)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildHeaderStat('Active Clients', activeCount.toString(), Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildHeaderStat('Trial / Inactive', inactiveCount.toString(), Colors.orange)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildHeaderStat('Completed', completedCount.toString(), Colors.purple)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  onChanged: (val) {
                                    setState(() {
                                      _searchQuery = val;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search clients...',
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (filteredClients.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'No PT clients found.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredClients.length,
                      itemBuilder: (context, index) {
                        final client = filteredClients[index];
                        return CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ClientDetailsScreen(
                                    member: client['member'] as Member,
                                    program: client['program'] as String,
                                    status: client['status'] as String,
                                  ),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundImage: NetworkImage(client['image']!),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        client['name']!,
                                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        client['program']!,
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildStatusBadge(client['status']!),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderStat(String label, String value, Color color) {
    return CustomCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(width: 4, height: 28, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    if (status == 'Active') {
      bg = const Color(0xFFE8F5E9);
      text = Colors.green;
    } else if (status == 'Trial') {
      bg = const Color(0xFFFFF3E0);
      text = Colors.orange;
    } else {
      bg = const Color(0xFFFFEBEE);
      text = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }
}
