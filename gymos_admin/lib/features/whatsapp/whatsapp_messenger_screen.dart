import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../whatsapp_templates/services/template_service.dart';
import '../whatsapp_templates/whatsapp_templates_screen.dart';
import 'services/whatsapp_chat_service.dart';

class WhatsAppMessengerScreen extends StatefulWidget {
  const WhatsAppMessengerScreen({super.key});

  @override
  State<WhatsAppMessengerScreen> createState() => _WhatsAppMessengerScreenState();
}

class _WhatsAppMessengerScreenState extends State<WhatsAppMessengerScreen> {
  final WhatsAppChatService _chatService = WhatsAppChatService.instance;

  bool _isLoadingConversations = true;
  List<WhatsAppConversationSummary> _conversations = [];
  String _searchQuery = '';

  WhatsAppConversationSummary? _activeConversation;
  List<WhatsAppMessageModel> _activeMessages = [];
  bool _isLoadingMessages = false;
  bool _isSending = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  Timer? _pollingTimer;

  final List<String> _quickReplies = [
    'Welcome to GymOS! How can we assist you today?',
    'Your gym membership has been successfully updated.',
    'Reminder: Your gym subscription renewal is due soon.',
    'Thank you for your payment! Receipt has been recorded.',
    'Please feel free to reach out if you have any questions.',
  ];

  @override
  void initState() {
    super.initState();
    _loadConversations();
    // Auto-poll for new incoming messages every 4 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollUpdates());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingConversations = true);
    try {
      final list = await _chatService.fetchConversations();
      if (mounted) {
        setState(() {
          _conversations = list;
          _isLoadingConversations = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoadingConversations = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load conversations: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  Future<void> _selectConversation(WhatsAppConversationSummary convo) async {
    setState(() {
      _activeConversation = convo;
      _isLoadingMessages = true;
    });

    await _loadMessages(convo.phoneNumber);
  }

  Future<void> _loadMessages(String phoneNumber, {bool silent = false}) async {
    try {
      final msgs = await _chatService.fetchMessages(phoneNumber);
      if (mounted) {
        setState(() {
          _activeMessages = msgs;
          _isLoadingMessages = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoadingMessages = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load messages: $e'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  void _pollUpdates() {
    _loadConversations(silent: true);
    if (_activeConversation != null) {
      _loadMessages(_activeConversation!.phoneNumber, silent: true);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _activeConversation == null || _isSending) return;

    setState(() => _isSending = true);
    final targetPhone = _activeConversation!.phoneNumber;

    try {
      final newMsg = await _chatService.sendMessage(
        toPhoneNumber: targetPhone,
        text: text,
        contactName: _activeConversation!.senderName,
      );

      _messageController.clear();
      setState(() {
        _activeMessages.add(newMsg);
        _isSending = false;
      });
      _scrollToBottom();
      _loadConversations(silent: true);
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        String actionableHint = '';
        if (errStr.contains('131030') || errStr.contains('allowed list')) {
          actionableHint = '\n\n💡 Reason & Fix:\nYou are currently sending from Meta\'s Sandbox Test Number (+1 555).\nMeta only allows sending to numbers added in the Test List.\n\nTo Fix:\n• Go to Meta Developer Console > WhatsApp > API Setup > Click "To" dropdown > "Manage phone number list" and add $targetPhone.\n• Or register your Real Gym Phone Number in Meta to message all contacts without restriction.';
        } else if (errStr.contains('131047') || errStr.contains('24 hours') || errStr.contains('Re-engagement')) {
          actionableHint = '\n\n💡 Reason & Fix:\nOutside the 24-hour customer window, Meta requires businesses to initiate or re-engage conversations using an Approved Meta Template.\n\nTo Fix:\n• Click "Send Meta Template" to send an approved template like "hello_world" to start the conversation.';
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AdminTheme.danger),
                const SizedBox(width: 8),
                Text('WhatsApp Send Error', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Text(
              'Could not deliver message to $targetPhone:\n\n$errStr$actionableHint',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  void _openSendTemplateForChat([String? targetPhone, String? targetName]) {
    final phone = targetPhone ?? _activeConversation?.phoneNumber;
    final name = targetName ?? _activeConversation?.senderName;
    showDialog(
      context: context,
      builder: (ctx) => _TemplateSelectorDialog(
        targetPhone: phone,
        targetName: name,
        onTemplateSent: () {
          if (phone != null) {
            _loadMessages(phone);
            _loadConversations(silent: true);
          }
        },
      ),
    );
  }

  void _showNewChatDialog() {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final msgCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.cardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusCard)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF25D366).withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF25D366), size: 20),
            ),
            const SizedBox(width: 12),
            Text('Start New WhatsApp Chat', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recipient Mobile Number (with country code, e.g. 919876543210)', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 6),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                decoration: InputDecoration(
                  hintText: 'e.g. 919876543210',
                  prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                  filled: true,
                  fillColor: AdminTheme.surfaceColor(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              Text('Contact Name (Optional)', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                decoration: InputDecoration(
                  hintText: 'e.g. Rahul Sharma',
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                  filled: true,
                  fillColor: AdminTheme.surfaceColor(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              Text('First Message (Optional)', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 6),
              TextField(
                controller: msgCtrl,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  filled: true,
                  fillColor: AdminTheme.surfaceColor(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AdminTheme.secondaryTextColor(context))),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final rawPhone = phoneCtrl.text.trim();
              final clean = WhatsAppChatService.normalizePhoneNumber(rawPhone);
              Navigator.pop(ctx);
              _openSendTemplateForChat(
                clean.isNotEmpty ? clean : null,
                nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
              );
            },
            icon: const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF25D366)),
            label: Text('Use Meta Template',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF25D366))),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final rawPhone = phoneCtrl.text.trim();
              final clean = WhatsAppChatService.normalizePhoneNumber(rawPhone);
              if (clean.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid phone number with country code'), backgroundColor: AdminTheme.warning),
                );
                return;
              }
              Navigator.pop(ctx);

              final newConvo = WhatsAppConversationSummary(
                phoneNumber: clean,
                senderName: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : null,
                lastMessage: msgCtrl.text.trim().isNotEmpty ? msgCtrl.text.trim() : 'Chat started',
                lastDirection: 'outbound',
                lastStatus: 'sent',
                lastMessageAt: DateTime.now(),
              );

              setState(() {
                _activeConversation = newConvo;
                _isLoadingMessages = true;
              });

              if (msgCtrl.text.trim().isNotEmpty) {
                try {
                  await _chatService.sendMessage(
                    toPhoneNumber: clean,
                    text: msgCtrl.text.trim(),
                    contactName: newConvo.senderName,
                  );
                } catch (err) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Message error: $err'), backgroundColor: AdminTheme.danger),
                    );
                  }
                }
              }

              await _loadMessages(clean);
              _loadConversations(silent: true);
            },
            icon: const Icon(Icons.chat_bubble_rounded, size: 16),
            label: Text('Start Conversation', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdminResponsive.isMobile(context);

    return Scaffold(
      backgroundColor: AdminTheme.surfaceColor(context),
      body: Row(
        children: [
          // Left Pane: Conversation List
          if (!isMobile || _activeConversation == null)
            SizedBox(
              width: isMobile ? MediaQuery.of(context).size.width : 380,
              child: _buildConversationsList(context),
            ),

          // Divider
          if (!isMobile)
            VerticalDivider(width: 1, thickness: 1, color: AdminTheme.borderColor(context)),

          // Right Pane: Active Chat Window
          if (!isMobile || _activeConversation != null)
            Expanded(
              child: _activeConversation == null
                  ? _buildEmptyState(context)
                  : _buildActiveChat(context),
            ),
        ],
      ),
    );
  }

  Widget _buildConversationsList(BuildContext context) {
    final filtered = _conversations.where((c) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final phone = c.phoneNumber.toLowerCase();
      final name = (c.senderName ?? '').toLowerCase();
      return phone.contains(q) || name.contains(q);
    }).toList();

    return Container(
      color: AdminTheme.cardColor(context),
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AdminTheme.borderColor(context))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Chats',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                      ),
                      Text(
                        '${_conversations.length} Active Conversations',
                        style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Chats',
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => _loadConversations(),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: _showNewChatDialog,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text('New Chat', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
              decoration: InputDecoration(
                hintText: 'Search by phone or name...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AdminTheme.surfaceColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),

          // Conversation List Items
          Expanded(
            child: _isLoadingConversations
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mark_chat_read_outlined, size: 40, color: AdminTheme.mutedTextColor(context)),
                            const SizedBox(height: 10),
                            Text('No conversations found', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: _showNewChatDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Start your first chat'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: AdminTheme.borderColor(context)),
                        itemBuilder: (ctx, i) {
                          final c = filtered[i];
                          final isSelected = _activeConversation?.phoneNumber == c.phoneNumber;
                          final initial = (c.senderName != null && c.senderName!.isNotEmpty)
                              ? c.senderName![0].toUpperCase()
                              : 'WA';

                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: AdminTheme.primary.withValues(alpha: 0.1),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: isSelected ? AdminTheme.primary : const Color(0xFF25D366).withValues(alpha: 0.15),
                              child: Text(
                                initial,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : const Color(0xFF25D366),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.senderName ?? '+${c.phoneNumber}',
                                    style: GoogleFonts.inter(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 14,
                                      color: AdminTheme.textColor(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  _formatTime(c.lastMessageAt),
                                  style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.secondaryTextColor(context)),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  if (c.lastDirection == 'outbound') ...[
                                    _buildStatusIcon(c.lastStatus, size: 14),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      c.lastMessage,
                                      style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () => _selectConversation(c),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_rounded, size: 64, color: Color(0xFF25D366)),
          ),
          const SizedBox(height: 20),
          Text(
            'WhatsApp Business Messenger',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a conversation from the left or click "New Chat" to send a direct WhatsApp message.',
            style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showNewChatDialog,
            icon: const Icon(Icons.add_rounded),
            label: Text('Start New WhatsApp Chat', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveChat(BuildContext context) {
    final isMobile = AdminResponsive.isMobile(context);
    final convo = _activeConversation!;

    return Column(
      children: [
        // Chat Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AdminTheme.cardColor(context),
            border: Border(bottom: BorderSide(color: AdminTheme.borderColor(context))),
          ),
          child: Row(
            children: [
              if (isMobile)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _activeConversation = null),
                ),
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                child: const Icon(Icons.person_rounded, color: Color(0xFF25D366), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      convo.senderName ?? '+${convo.phoneNumber}',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                    ),
                    Text(
                      '+${convo.phoneNumber} • Meta Cloud API Active',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF25D366), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Send Meta Approved Template to this contact',
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.verified_rounded, size: 14),
                  label: Text('Send Meta Template',
                      style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 34),
                    elevation: 0,
                  ),
                  onPressed: () => _openSendTemplateForChat(
                      convo.phoneNumber, convo.senderName),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copy Number',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: convo.phoneNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phone number copied!'), backgroundColor: AdminTheme.primary),
                  );
                },
              ),
              IconButton(
                tooltip: 'Refresh Thread',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => _loadMessages(convo.phoneNumber),
              ),
            ],
          ),
        ),

        // Messages Bubble Stream
        Expanded(
          child: _isLoadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _activeMessages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366)
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.mark_email_read_outlined,
                                  size: 36, color: Color(0xFF25D366)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Start Conversation via Meta Template',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AdminTheme.textColor(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                'Meta WhatsApp Rule: To message a customer for the first time or outside the 24-hour window, you must send an approved template.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AdminTheme.secondaryTextColor(context),
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            ElevatedButton.icon(
                              onPressed: () => _openSendTemplateForChat(
                                  convo.phoneNumber, convo.senderName),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: Text('Send Approved Meta Template',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      itemCount: _activeMessages.length,
                      itemBuilder: (ctx, i) {
                        final m = _activeMessages[i];
                        return _buildMessageBubble(context, m);
                      },
                    ),
        ),

        // Quick Replies Chips
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: AdminTheme.cardColor(context).withValues(alpha: 0.8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickReplies.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (ctx, idx) {
              final qr = _quickReplies[idx];
              return ActionChip(
                label: Text(qr, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.textColor(context))),
                backgroundColor: AdminTheme.surfaceColor(context),
                onPressed: () {
                  _messageController.text = qr;
                  _messageFocusNode.requestFocus();
                },
              );
            },
          ),
        ),

        // Bottom Input Bar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AdminTheme.cardColor(context),
            border: Border(top: BorderSide(color: AdminTheme.borderColor(context))),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Send Approved Meta Template',
                icon: const Icon(Icons.verified_rounded, color: Color(0xFF25D366), size: 24),
                onPressed: () => _openSendTemplateForChat(convo.phoneNumber, convo.senderName),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageFocusNode,
                  maxLines: 4,
                  minLines: 1,
                  style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
                  decoration: InputDecoration(
                    hintText: 'Type WhatsApp reply to +${convo.phoneNumber}...',
                    filled: true,
                    fillColor: AdminTheme.surfaceColor(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_isSending ? 'Sending...' : 'Send', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, WhatsAppMessageModel msg) {
    final isOutbound = msg.isOutbound;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = isOutbound
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? const Color(0xFF202C33) : Colors.white);

    final textColor = isOutbound
        ? (isDark ? Colors.white : const Color(0xFF111B21))
        : (isDark ? Colors.white : const Color(0xFF111B21));

    return Align(
      alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOutbound ? 14 : 2),
            bottomRight: Radius.circular(isOutbound ? 2 : 14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.messageType == 'template') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.white70,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded,
                          size: 11, color: Color(0xFF25D366)),
                      const SizedBox(width: 4),
                      Text(
                        'Meta Template',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF25D366)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                msg.messageBody,
                style: GoogleFonts.inter(fontSize: 14, color: textColor),
              ),
            ),
            if (isOutbound && msg.status == 'failed') ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AdminTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 12, color: AdminTheme.danger),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        msg.errorMessage != null && msg.errorMessage!.isNotEmpty
                            ? msg.errorMessage!
                            : 'Failed: Recipient not in allowed list / sandbox restriction',
                        style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.danger, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('hh:mm a').format(msg.createdAt),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
                if (isOutbound) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(msg.status, size: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status, {double size = 14}) {
    switch (status.toLowerCase()) {
      case 'read':
        return Icon(Icons.done_all_rounded, size: size, color: const Color(0xFF53BDEB));
      case 'delivered':
        return Icon(Icons.done_all_rounded, size: size, color: Colors.grey);
      case 'sent':
        return Icon(Icons.done_rounded, size: size, color: Colors.grey);
      case 'failed':
        return Icon(Icons.error_outline_rounded, size: size, color: AdminTheme.danger);
      default:
        return Icon(Icons.access_time_rounded, size: size, color: Colors.grey);
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0 && dt.day == now.day) {
      return DateFormat('hh:mm a').format(dt);
    } else if (diff.inDays < 7) {
      return DateFormat('E').format(dt);
    } else {
      return DateFormat('dd/MM/yy').format(dt);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// TEMPLATE SELECTOR DIALOG FOR MESSENGER
// ═══════════════════════════════════════════════════════════════════

class _TemplateSelectorDialog extends StatefulWidget {
  final String? targetPhone;
  final String? targetName;
  final VoidCallback? onTemplateSent;

  const _TemplateSelectorDialog({
    this.targetPhone,
    this.targetName,
    this.onTemplateSent,
  });

  @override
  State<_TemplateSelectorDialog> createState() => _TemplateSelectorDialogState();
}

class _TemplateSelectorDialogState extends State<_TemplateSelectorDialog> {
  bool _loading = true;
  String? _error;
  List<WhatsAppTemplate> _approvedTemplates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await WhatsAppTemplateService.instance.fetchTemplates();
      final approved =
          list.where((t) => t.status.toUpperCase() == 'APPROVED').toList();
      if (mounted) {
        setState(() {
          _loading = false;
          _approvedTemplates = approved;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 650),
        decoration: BoxDecoration(
          color: isDark ? AdminTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
          border: Border.all(
            color: isDark ? AdminTheme.darkBorder : AdminTheme.lightBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.verified_rounded,
                        color: Color(0xFF25D366), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Approved Meta Template',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.textColor(context),
                          ),
                        ),
                        Text(
                          widget.targetPhone != null
                              ? 'Recipient: +${widget.targetPhone}'
                              : 'Choose an official template approved by Meta',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AdminTheme.secondaryTextColor(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AdminTheme.danger, size: 36),
                                const SizedBox(height: 10),
                                Text('Failed to load templates from Meta',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                Text(_error!,
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AdminTheme.danger),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                    onPressed: _loadTemplates,
                                    child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _approvedTemplates.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.article_outlined,
                                        size: 40, color: AdminTheme.warning),
                                    const SizedBox(height: 12),
                                    Text('No Approved Templates Found in Meta',
                                        style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 6),
                                    Text(
                                        'Go to WA Templates in the sidebar to create and submit templates for Meta approval.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color:
                                                AdminTheme.secondaryTextColor(
                                                    context))),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _approvedTemplates.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final t = _approvedTemplates[i];
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AdminTheme.darkSurface
                                        : AdminTheme.lightSurface,
                                    borderRadius: BorderRadius.circular(
                                        AdminTheme.radiusSm),
                                    border: Border.all(
                                        color: const Color(0xFF25D366)
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF25D366)
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text('APPROVED',
                                                style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: const Color(
                                                        0xFF25D366))),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(t.name,
                                              style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AdminTheme.textColor(
                                                      context))),
                                          const Spacer(),
                                          Text(t.language,
                                              style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color:
                                                      AdminTheme.mutedTextColor(
                                                          context))),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        t.bodyText,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color:
                                                AdminTheme.secondaryTextColor(
                                                    context)),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (ctx) =>
                                                  SendTemplateDialog(
                                                template: t,
                                                initialPhone:
                                                    widget.targetPhone,
                                                initialName: widget.targetName,
                                                onSent: widget.onTemplateSent,
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.send_rounded,
                                              size: 14),
                                          label: Text('Use This Template',
                                              style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF25D366),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 6),
                                            minimumSize: const Size(0, 32),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

