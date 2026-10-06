import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';
import 'support_chat_screen.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  String _selectedPriority = 'medium';
  int _activeTab = 0; // 0 = Raise Ticket, 1 = Ticket History
  List<Map<String, dynamic>> _tickets = [];
  bool _loadingTickets = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets() async {
    if (!mounted) return;
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    if (gymId == null || !SupabaseService.isInitialized) return;

    try {
      setState(() => _loadingTickets = true);
      final List response = await SupabaseService.client
          .from('support_tickets')
          .select()
          .eq('gym_id', gymId)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _tickets = List<Map<String, dynamic>>.from(response);
          _loadingTickets = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch tickets: $e");
      if (mounted) {
        setState(() => _loadingTickets = false);
      }
    }
  }

  Future<void> _createTicket() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ticket title and description.'), backgroundColor: Colors.red),
      );
      return;
    }

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final gymName = authVm.activeAssociation?.gymName ?? authVm.gymInfo?['name'] ?? 'GYMOS';
    final ownerId = authVm.currentUser?.id;

    if (gymId == null || ownerId == null || !SupabaseService.isInitialized) return;

    setState(() => _submitting = true);

    try {
      final List res = await SupabaseService.client.from('support_tickets').insert({
        'title': title,
        'description': desc,
        'priority': _selectedPriority,
        'status': 'Open',
        'gym_id': gymId,
        'gym_name': gymName,
        'owner_id': ownerId,
      }).select();

      if (res.isNotEmpty && res.first['id'] != null) {
        final ticketId = res.first['id'];
        await SupabaseService.client.from('support_messages').insert({
          'ticket_id': ticketId,
          'sender_id': ownerId,
          'sender_role': 'owner',
          'message': desc,
        });
      }

      _titleController.clear();
      _descController.clear();
      if (mounted) {
        setState(() {
          _selectedPriority = 'medium';
          _activeTab = 1; // Switch to history list to show ticket
        });
      }

      await _fetchTickets();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Support ticket raised successfully!'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to raise support ticket: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Support Ticket Center',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: Row(
              children: [
                _buildTabButton('Raise Ticket', 0),
                _buildTabButton('History (${_tickets.length})', 1),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _activeTab == 0 ? _buildRaiseTicketForm() : _buildTicketHistory(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _activeTab = index;
          });
          if (index == 1) {
            _fetchTickets();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? AppTheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
              color: isActive ? AppTheme.primary : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRaiseTicketForm() {
    return Column(
      key: const ValueKey('raise_ticket_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Describe Your Issue',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Subject / Title',
                    hintText: 'e.g. Printer not printing bills',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Priority Level',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedPriority = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _descController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Detailed Message',
                    hintText: 'Describe the problem you are facing in detail...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _submitting ? null : _createTicket,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  'Submit Support Ticket',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  Widget _buildTicketHistory() {
    if (_loadingTickets) {
      return const SizedBox(
        key: ValueKey('tickets_loading'),
        height: 200,
        child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    if (_tickets.isEmpty) {
      return SizedBox(
        key: const ValueKey('tickets_empty'),
        height: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_chat_read_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Support Tickets Found',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            Text(
              'Tickets you raise will be shown here.',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('tickets_list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tickets.length,
      itemBuilder: (context, index) {
        final ticket = _tickets[index];
        final priority = (ticket['priority'] ?? 'medium').toString().toUpperCase();
        final status = ticket['status'] ?? 'Open';
        final title = ticket['title'] ?? 'Support Ticket';
        final date = ticket['created_at'] != null 
            ? DateTime.tryParse(ticket['created_at'])?.toLocal().toString().substring(0, 16) ?? ''
            : '';

        Color priorityColor;
        switch (priority.toLowerCase()) {
          case 'urgent': priorityColor = Colors.red[700]!; break;
          case 'high': priorityColor = Colors.orange[700]!; break;
          case 'medium': priorityColor = Colors.amber[700]!; break;
          default: priorityColor = Colors.blue[700]!;
        }

        Color statusColor;
        switch (status.toString().toLowerCase()) {
          case 'open': statusColor = Colors.blue; break;
          case 'in progress': statusColor = Colors.orange; break;
          case 'resolved': statusColor = Colors.green; break;
          default: statusColor = Colors.grey;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SupportChatScreen(ticket: ticket),
                ),
              ).then((_) => _fetchTickets());
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ticket['description'] ?? '',
                    style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: priorityColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          priority,
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: priorityColor),
                        ),
                      ),
                      Text(
                        date,
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
