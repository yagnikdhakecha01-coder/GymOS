import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';
import 'admin_support_chat_screen.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  bool _isLoading = true;
  String _filter = 'all';
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets() async {
    try {
      setState(() => _isLoading = true);
      if (!AdminSupabaseService.isInitialized) {
        _loadMockTickets();
        return;
      }
      final client = AdminSupabaseService.client;
      final response = await client
          .from('support_tickets')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _tickets = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Failed to fetch tickets: $e");
      _loadMockTickets();
    }
  }

  void _loadMockTickets() {
    setState(() {
      _tickets = List<Map<String, dynamic>>.from(_mockTickets);
      _isLoading = false;
    });
  }

  Future<void> _updateTicketStatus(String ticketId, String newStatus) async {
    try {
      if (AdminSupabaseService.isInitialized) {
        final client = AdminSupabaseService.client;
        await client
            .from('support_tickets')
            .update({'status': newStatus})
            .eq('id', ticketId);
        _fetchTickets();
      } else {
        setState(() {
          final idx = _tickets.indexWhere((t) => t['id'] == ticketId);
          if (idx >= 0) {
            _tickets[idx]['status'] = newStatus;
          }
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket status updated to $newStatus'), backgroundColor: AdminTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  void _showReplyDialog(Map<String, dynamic> ticket) {
    final title = ticket['title'] as String? ?? 'Support Ticket';
    final ticketId = ticket['id'].toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Manage Ticket', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ticket Subject: "$title"',
              style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context)),
            ),
            const SizedBox(height: 18),
            Text(
              'Select new status to respond:',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _updateTicketStatus(ticketId, 'In Progress');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.warning),
                  child: const Text('In Progress'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _updateTicketStatus(ticketId, 'Resolved');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.success),
                  child: const Text('Resolve'),
                ),
              ],
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable());

    // Filter tickets based on selection
    final query = _searchController.text.toLowerCase().trim();
    final filteredTickets = _tickets.where((t) {
      final matchesFilter = _filter == 'all' || t['status'].toString().toLowerCase() == _filter;
      final matchesQuery = query.isEmpty ||
          t['title'].toString().toLowerCase().contains(query) ||
          t['description'].toString().toLowerCase().contains(query) ||
          t['gym_name'].toString().toLowerCase().contains(query);
      return matchesFilter && matchesQuery;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Row(
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Support Tickets', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Text('${filteredTickets.length} tickets found', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                  ]),
                  const Spacer(),
                  SizedBox(
                    width: 240,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search tickets...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
                        prefixIcon: Icon(Icons.search, size: 18, color: AdminTheme.mutedTextColor(context)),
                        filled: true,
                        fillColor: AdminTheme.surfaceColor(context),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                      ),
                      style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('All', 'all'),
                    _chip('Open', 'open'),
                    _chip('In Progress', 'in progress'),
                    _chip('Resolved', 'resolved'),
                    _chip('Closed', 'closed'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (filteredTickets.isEmpty)
                Container(
                  height: 300,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.support_agent_rounded, size: 48, color: AdminTheme.mutedTextColor(context)),
                      const SizedBox(height: 16),
                      Text('No tickets found', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminTheme.secondaryTextColor(context))),
                    ],
                  ),
                )
              else
                ...filteredTickets.map((t) => _ticketCard(context, t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final isActive = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: AdminTheme.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AdminTheme.primary.withValues(alpha: 0.1) : AdminTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isActive ? AdminTheme.primary.withValues(alpha: 0.4) : Colors.transparent),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? AdminTheme.primary : AdminTheme.secondaryTextColor(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ticketCard(BuildContext context, Map<String, dynamic> ticket) {
    Color priorityColor;
    final priority = (ticket['priority'] ?? 'medium').toString().toLowerCase();
    switch (priority) {
      case 'urgent': priorityColor = AdminTheme.danger; break;
      case 'high': priorityColor = AdminTheme.orange; break;
      case 'medium': priorityColor = AdminTheme.warning; break;
      default: priorityColor = AdminTheme.info;
    }

    final status = ticket['status'] ?? 'Open';
    final gymName = ticket['gym_name'] ?? ticket['gym'] ?? 'Unknown Gym';
    final date = ticket['created_at'] != null 
        ? DateTime.tryParse(ticket['created_at'].toString())?.toLocal().toString().substring(0, 16) ?? ''
        : 'Recent';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AdminTheme.cardColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        side: BorderSide(color: AdminTheme.borderColor(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminSupportChatScreen(
                ticket: ticket,
                onRefresh: _fetchTickets,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 4, height: 48, decoration: BoxDecoration(color: priorityColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ticket['title'] as String? ?? 'Support Ticket',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _statusColor(status.toString()).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            status.toString(),
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(status.toString())),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ticket['description'] as String? ?? 'No details provided.',
                      style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      gymName,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AdminTheme.secondaryTextColor(context)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(priority.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: priorityColor)),
                        ),
                        const SizedBox(width: 8),
                        Text(date, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
                        const Spacer(),
                        if (status.toString().toLowerCase() != 'closed') ...[
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminSupportChatScreen(
                                    ticket: ticket,
                                    onRefresh: _fetchTickets,
                                  ),
                                ),
                              );
                            },
                            child: Text('Respond', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          TextButton(
                            onPressed: () => _updateTicketStatus(ticket['id'].toString(), 'Closed'),
                            child: Text('Close', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.mutedTextColor(context))),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open': return AdminTheme.info;
      case 'in progress': return AdminTheme.warning;
      case 'resolved': return AdminTheme.success;
      case 'closed': return AdminTheme.textSecondary;
      default: return AdminTheme.textSecondary;
    }
  }
}

const _mockTickets = [
  {'id': 'mock-1', 'title': 'Unable to login after password reset', 'gym_name': 'Iron Paradise — Rahul Sharma', 'description': 'The owner cannot login using their temporary password credentials.', 'priority': 'urgent', 'status': 'Open', 'created_at': '2026-08-03T06:00:00Z'},
  {'id': 'mock-2', 'title': 'QR attendance not scanning', 'gym_name': 'FitZone Premium — Priya Patel', 'description': 'The staff is seeing camera permissions error on multiple Android devices.', 'priority': 'high', 'status': 'In Progress', 'created_at': '2026-08-03T03:00:00Z'},
  {'id': 'mock-3', 'title': 'Invoice generation error', 'gym_name': 'Elite Fitness — Ravi Joshi', 'description': 'Tax invoice calculations are throwing currency parse failures.', 'priority': 'medium', 'status': 'Open', 'created_at': '2026-08-02T10:00:00Z'},
];
