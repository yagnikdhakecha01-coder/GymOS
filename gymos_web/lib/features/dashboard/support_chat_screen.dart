import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import '../authentication/auth_viewmodel.dart';

class SupportChatScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;

  const SupportChatScreen({super.key, required this.ticket});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _refreshTimer;
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _subscribeChatRealtime();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchMessagesQuietly());
  }

  void _subscribeChatRealtime() {
    if (!SupabaseService.isInitialized) return;
    try {
      final ticketId = widget.ticket['id'];
      _chatChannel = SupabaseService.client
          .channel('public_support_messages_$ticketId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'support_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'ticket_id',
              value: ticketId,
            ),
            callback: (_) {
              if (mounted) _fetchMessagesQuietly();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _chatChannel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessagesQuietly() async {
    if (!SupabaseService.isInitialized || !mounted) return;
    try {
      final response = await SupabaseService.client
          .from('support_messages')
          .select()
          .eq('ticket_id', widget.ticket['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        final newMsgs = List<Map<String, dynamic>>.from(response);
        if (newMsgs.length != _messages.length) {
          setState(() {
            _messages = newMsgs;
          });
          _scrollToBottom();
          _markMessagesAsRead();
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchMessages() async {
    if (!SupabaseService.isInitialized) {
      // Mock messages for offline/mock mode
      setState(() {
        _messages = [
          {
            'id': 'mock_msg_1',
            'ticket_id': widget.ticket['id'],
            'sender_role': 'owner',
            'message': widget.ticket['description'] ?? 'Hello, I need help.',
            'created_at': widget.ticket['created_at'] ?? DateTime.now().toIso8601String(),
          },
          {
            'id': 'mock_msg_2',
            'ticket_id': widget.ticket['id'],
            'sender_role': 'admin',
            'message': 'Hi! Welcome to support. We have received your query and are looking into it.',
            'created_at': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
          }
        ];
        _loading = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final response = await SupabaseService.client
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
        _markMessagesAsRead();
      }
    } catch (e) {
      debugPrint("Failed to fetch messages: $e");
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (!SupabaseService.isInitialized) return;
    try {
      final unreadAdminMessages = _messages.where((m) => m['sender_role'] == 'admin' && m['is_read'] != true).toList();
      if (unreadAdminMessages.isNotEmpty) {
        await SupabaseService.client
            .from('support_messages')
            .update({'is_read': true})
            .eq('ticket_id', widget.ticket['id'])
            .eq('sender_role', 'admin');
      }
    } catch (e) {
      debugPrint("Failed to mark messages as read: $e");
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

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    final msgText = text?.trim() ?? _messageController.text.trim();
    if (msgText.isEmpty && imageUrl == null) return;

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final userId = authVm.currentUser?.id;

    if (text == null) {
      _messageController.clear();
    }

    setState(() => _sending = true);

    if (!SupabaseService.isInitialized) {
      // Offline mock send
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          _messages.add({
            'id': DateTime.now().toIso8601String(),
            'ticket_id': widget.ticket['id'],
            'sender_role': 'owner',
            'message': msgText.isNotEmpty ? msgText : null,
            'image_url': imageUrl,
            'created_at': DateTime.now().toIso8601String(),
          });
          _sending = false;
        });
        _scrollToBottom();
      }
      return;
    }

    try {
      await SupabaseService.client.from('support_messages').insert({
        'ticket_id': widget.ticket['id'],
        'sender_id': userId,
        'sender_role': 'owner',
        'message': msgText.isNotEmpty ? msgText : null,
        'image_url': imageUrl,
      });
      _fetchMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
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
            const CircularProgressIndicator(color: Color(0xFF6C4EFF)),
            const SizedBox(width: 20),
            Expanded(child: Text('Uploading attachment...', style: GoogleFonts.inter())),
          ],
        ),
      ),
    );

    try {
      String? uploadUrl;

      if (!SupabaseService.isInitialized) {
        // Mock upload url
        await Future.delayed(const Duration(seconds: 1));
        uploadUrl = 'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=800';
      } else {
        final file = File(pickedFile.path);
        final bytes = await file.readAsBytes();
        
        uploadUrl = await ImageSecurityService.uploadSecureImage(
          bucket: 'support_attachments',
          directoryPath: 'attachments/${widget.ticket['id']}',
          bytes: bytes,
        );
      }

      // Close loader
      Navigator.pop(context);

      _sendMessage(imageUrl: uploadUrl);
    } catch (e) {
      // Close loader
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showImagePreviewDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const SizedBox(
                        height: 200,
                        width: 200,
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(24),
                      color: Colors.grey[900],
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_rounded, color: Colors.white70, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.ticket['status'] ?? 'Open';
    final isClosed = status.toString().toLowerCase() == 'closed';

    Color statusColor;
    switch (status.toString().toLowerCase()) {
      case 'open': statusColor = Colors.blue; break;
      case 'in progress': statusColor = Colors.orange; break;
      case 'resolved': statusColor = Colors.green; break;
      default: statusColor = Colors.grey;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.ticket['title'] ?? 'Ticket Support',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            Text(
              'Ticket ID: ${widget.ticket['id'].toString().substring(0, 8)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Ticket description banner
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Issue Description:',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.ticket['description'] ?? '',
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Message list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C4EFF)))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isOwner = msg['sender_role'] == 'owner';
                        final time = msg['created_at'] != null
                            ? DateTime.tryParse(msg['created_at'])?.toLocal().toString().substring(11, 16) ?? ''
                            : '';
                        final hasImage = msg['image_url'] != null;

                        return Align(
                          alignment: isOwner ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isOwner ? const Color(0xFF6C4EFF) : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isOwner ? const Radius.circular(16) : const Radius.circular(2),
                                bottomRight: isOwner ? const Radius.circular(2) : const Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                              border: isOwner ? null : Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasImage) ...[
                                   GestureDetector(
                                     onTap: () => _showImagePreviewDialog(context, msg['image_url']),
                                     child: Stack(
                                       alignment: Alignment.center,
                                       children: [
                                         ClipRRect(
                                           borderRadius: BorderRadius.circular(8),
                                           child: Image.network(
                                             msg['image_url'],
                                             fit: BoxFit.cover,
                                             height: 200,
                                             width: double.infinity,
                                             loadingBuilder: (context, child, loadingProgress) {
                                               if (loadingProgress == null) return child;
                                               return Container(
                                                 height: 150,
                                                 width: double.infinity,
                                                 color: Colors.grey[200],
                                                 child: const Center(
                                                   child: CircularProgressIndicator(strokeWidth: 2),
                                                 ),
                                               );
                                             },
                                             errorBuilder: (context, error, stackTrace) => Container(
                                               height: 150,
                                               width: double.infinity,
                                               color: Colors.grey[200],
                                               child: const Icon(Icons.broken_image, color: Colors.grey),
                                             ),
                                           ),
                                         ),
                                         Positioned(
                                           bottom: 6,
                                           right: 6,
                                           child: Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                             decoration: BoxDecoration(
                                               color: Colors.black.withOpacity(0.65),
                                               borderRadius: BorderRadius.circular(10),
                                             ),
                                             child: const Row(
                                               mainAxisSize: MainAxisSize.min,
                                               children: [
                                                 Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white),
                                                 SizedBox(width: 3),
                                                 Text(
                                                   'Tap to view',
                                                   style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                                 ),
                                               ],
                                             ),
                                           ),
                                         ),
                                       ],
                                     ),
                                   ),
                                   const SizedBox(height: 6),
                                 ],
                                if (msg['message'] != null)
                                  Text(
                                    msg['message'],
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      color: isOwner ? Colors.white : const Color(0xFF1E293B),
                                      height: 1.3,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      time,
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        color: isOwner ? Colors.white70 : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Message compose bar (disabled if ticket is Closed)
            if (isClosed)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded, color: Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'This ticket has been resolved and closed.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF6C4EFF)),
                      onPressed: _sending ? null : _pickAndUploadImage,
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _messageController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (val) => _sendMessage(),
                          style: GoogleFonts.inter(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            hintStyle: GoogleFonts.inter(color: Colors.grey[500], fontSize: 13.5),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF6C4EFF)),
                      onPressed: _sending ? null : () => _sendMessage(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
