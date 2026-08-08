import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/theme/admin_theme.dart';
import '../../core/services/supabase_service.dart';

class AdminSupportChatScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final Function() onRefresh;

  const AdminSupportChatScreen({
    super.key,
    required this.ticket,
    required this.onRefresh,
  });

  @override
  State<AdminSupportChatScreen> createState() => _AdminSupportChatScreenState();
}

class _AdminSupportChatScreenState extends State<AdminSupportChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.ticket['status'] ?? 'Open';
    _fetchMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    if (!AdminSupabaseService.isInitialized) {
      setState(() {
        _messages = [];
        _loading = false;
      });
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final response = await client
          .from('support_messages')
          .select()
          .eq('ticket_id', widget.ticket['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Failed to fetch messages: $e");
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _updateTicketStatus(String newStatus) async {
    setState(() => _currentStatus = newStatus);

    if (!AdminSupabaseService.isInitialized) {
      widget.onRefresh();
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      await client
          .from('support_tickets')
          .update({'status': newStatus})
          .eq('id', widget.ticket['id']);
      widget.onRefresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e'), backgroundColor: AdminTheme.danger),
      );
    }
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    final msgText = text?.trim() ?? _messageController.text.trim();
    if (msgText.isEmpty && imageUrl == null) return;

    if (text == null) {
      _messageController.clear();
    }

    setState(() => _sending = true);

    if (!AdminSupabaseService.isInitialized) {
      setState(() => _sending = false);
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final currentUser = client.auth.currentUser;

      await client.from('support_messages').insert({
        'ticket_id': widget.ticket['id'],
        'sender_id': currentUser?.id,
        'sender_role': 'admin',
        'message': msgText.isNotEmpty ? msgText : null,
        'image_url': imageUrl,
      });

      // Automatically flip ticket status to 'In Progress' if currently 'Open'
      if (_currentStatus == 'Open') {
        await _updateTicketStatus('In Progress');
      }

      _fetchMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), backgroundColor: AdminTheme.danger),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(color: AdminTheme.primary),
            const SizedBox(width: 20),
            Expanded(child: Text('Uploading attachment...', style: GoogleFonts.inter())),
          ],
        ),
      ),
    );

    try {
      String? uploadUrl;

      if (!AdminSupabaseService.isInitialized) {
        // Mock upload url
        await Future.delayed(const Duration(seconds: 1));
        uploadUrl = 'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=800';
      } else {
        final client = AdminSupabaseService.client;
        final bytes = await pickedFile.readAsBytes();
        final path = 'attachments/${widget.ticket['id']}/${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
        
        await client.storage.from('support_attachments').uploadBinary(path, bytes);
        uploadUrl = client.storage.from('support_attachments').getPublicUrl(path);
      }

      // Close loader
      Navigator.pop(context);

      if (uploadUrl != null) {
        _sendMessage(imageUrl: uploadUrl);
      }
    } catch (e) {
      // Close loader
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: AdminTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isClosed = _currentStatus.toLowerCase() == 'closed';

    Color statusColor;
    switch (_currentStatus.toLowerCase()) {
      case 'open': statusColor = AdminTheme.info; break;
      case 'in progress': statusColor = AdminTheme.warning; break;
      case 'resolved': statusColor = AdminTheme.success; break;
      default: statusColor = AdminTheme.mutedTextColor(context);
    }

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
              widget.ticket['title'] ?? 'Manage Support Ticket',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AdminTheme.textColor(context),
              ),
            ),
            Text(
              'Gym: ${widget.ticket['gym_name'] ?? 'Unknown'}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AdminTheme.secondaryTextColor(context),
              ),
            ),
          ],
        ),
        actions: [
          // Status dropdown
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AdminTheme.backgroundColor(context),
                borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                border: Border.all(color: AdminTheme.borderColor(context)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currentStatus,
                  dropdownColor: AdminTheme.surfaceColor(context),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
                  onChanged: (newVal) {
                    if (newVal != null) {
                      _updateTicketStatus(newVal);
                    }
                  },
                  items: ['Open', 'In Progress', 'Resolved', 'Closed']
                      .map((val) => DropdownMenuItem<String>(
                            value: val,
                            child: Row(
                              children: [
                                Icon(Icons.circle, size: 8, color: val.toLowerCase() == 'closed' ? Colors.grey : val.toLowerCase() == 'resolved' ? AdminTheme.success : val.toLowerCase() == 'open' ? AdminTheme.info : AdminTheme.warning),
                                const SizedBox(width: 8),
                                Text(val),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
          if (!isClosed)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () => _updateTicketStatus('Closed'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  icon: const Icon(Icons.lock_rounded, size: 14),
                  label: const Text('Close Ticket', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          // Left Sidebar: Ticket Info Card
          Container(
            width: 320,
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor(context),
              border: Border(
                right: BorderSide(color: AdminTheme.borderColor(context)),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TICKET DETAILS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AdminTheme.mutedTextColor(context),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),
                _detailField('Title', widget.ticket['title']),
                const SizedBox(height: 16),
                _detailField('Description', widget.ticket['description']),
                const SizedBox(height: 16),
                _detailField('Priority', widget.ticket['priority']?.toString().toUpperCase()),
                const SizedBox(height: 16),
                _detailField('Created At', widget.ticket['created_at'] != null 
                    ? DateTime.tryParse(widget.ticket['created_at'].toString())?.toLocal().toString().substring(0, 16)
                    : 'Recent'),
                const Spacer(),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: AdminTheme.mutedTextColor(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Closed tickets are archived and hidden from the gym owner.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AdminTheme.mutedTextColor(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right Area: Messages / Chat Thread
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: AdminTheme.primary))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(24),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isAdmin = msg['sender_role'] == 'admin';
                            final time = msg['created_at'] != null
                                ? DateTime.tryParse(msg['created_at'])?.toLocal().toString().substring(11, 16) ?? ''
                                : '';
                            final hasImage = msg['image_url'] != null;

                            return Align(
                              alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 500),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: isAdmin 
                                      ? AdminTheme.primary.withValues(alpha: 0.1) 
                                      : AdminTheme.surfaceColor(context),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: isAdmin ? const Radius.circular(12) : const Radius.circular(2),
                                    bottomRight: isAdmin ? const Radius.circular(2) : const Radius.circular(12),
                                  ),
                                  border: Border.all(
                                    color: isAdmin 
                                        ? AdminTheme.primary.withValues(alpha: 0.3) 
                                        : AdminTheme.borderColor(context),
                                  ),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (hasImage) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(
                                          msg['image_url'],
                                          fit: BoxFit.cover,
                                          height: 250,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 200,
                                            color: Colors.grey[200],
                                            child: const Icon(Icons.broken_image, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (msg['message'] != null)
                                      Text(
                                        msg['message'],
                                        style: GoogleFonts.inter(
                                          fontSize: 13.5,
                                          color: AdminTheme.textColor(context),
                                          height: 1.4,
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${isAdmin ? "Support Admin" : (msg['sender_role'] == 'staff' ? 'Gym Staff' : 'Gym Owner')} • $time',
                                          style: GoogleFonts.inter(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: AdminTheme.mutedTextColor(context),
                                          ),
                                        ),
                                        if (isAdmin) ...[
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.done_all_rounded,
                                            size: 13,
                                            color: (msg['is_read'] == true) ? Colors.blue : AdminTheme.mutedTextColor(context),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Composer Panel
                if (isClosed)
                  Container(
                    color: AdminTheme.surfaceColor(context),
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, color: AdminTheme.mutedTextColor(context), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'This ticket is closed. Re-open the status above to send messages.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AdminTheme.mutedTextColor(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AdminTheme.surfaceColor(context),
                      border: Border(top: BorderSide(color: AdminTheme.borderColor(context))),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_photo_alternate_rounded, color: AdminTheme.primary),
                          onPressed: _sending ? null : _pickAndUploadImage,
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AdminTheme.backgroundColor(context),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AdminTheme.borderColor(context)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextField(
                              controller: _messageController,
                              style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (val) => _sendMessage(),
                              decoration: InputDecoration(
                                hintText: 'Type admin reply...',
                                hintStyle: GoogleFonts.inter(color: AdminTheme.mutedTextColor(context), fontSize: 13),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.send_rounded, color: AdminTheme.primary),
                          onPressed: _sending ? null : () => _sendMessage(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailField(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AdminTheme.mutedTextColor(context)),
        ),
        const SizedBox(height: 4),
        Text(
          value ?? '-',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.textColor(context)),
        ),
      ],
    );
  }
}

extension BorderToBoxDecoration on Border {
  BoxDecoration toBoxDecoration() {
    return BoxDecoration(border: this);
  }
}
