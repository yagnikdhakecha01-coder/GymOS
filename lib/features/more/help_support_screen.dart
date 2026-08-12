import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/services/supabase_service.dart';
import '../dashboard/support_tickets_screen.dart';

class FAQItem {
  final String question;
  final String answer;

  FAQItem({required this.question, required this.answer});

  factory FAQItem.fromJson(Map<String, dynamic> json) {
    return FAQItem(
      question: json['question'] ?? '',
      answer: json['answer'] ?? '',
    );
  }
}

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  List<FAQItem> _faqs = [];
  bool _loadingFAQs = true;

  @override
  void initState() {
    super.initState();
    _fetchFAQs();
  }

  Future<void> _fetchFAQs() async {
    final defaultFAQs = [
      FAQItem(
        question: 'How do I add custom fields to member forms?',
        answer: 'Go to More -> Gym Settings -> Custom Member Form. Here, you can configure text, number, dropdown, switch, or photo fields that will automatically appear when adding a member.',
      ),
      FAQItem(
        question: 'Can I schedule multiple workouts in a single day?',
        answer: 'Yes, inside More -> Workout Plans -> Add/Edit Plan. Each day of the weekly schedule has an "+ Add Workout" button allowing you to add unlimited routines.',
      ),
      FAQItem(
        question: 'How does trainer assignment work?',
        answer: 'When adding a member, toggle the "Personal Trainer" switch to ON. You will then see options to select an assigned trainer, PT package, and custom coaching notes.',
      ),
    ];

    if (!SupabaseService.isInitialized) {
      setState(() {
        _faqs = defaultFAQs;
        _loadingFAQs = false;
      });
      return;
    }

    try {
      final List res = await SupabaseService.client
          .from('faqs')
          .select()
          .order('display_order', ascending: true);

      if (res.isNotEmpty) {
        setState(() {
          _faqs = res.map((e) => FAQItem.fromJson(e)).toList();
          _loadingFAQs = false;
        });
      } else {
        setState(() {
          _faqs = defaultFAQs;
          _loadingFAQs = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching FAQs: $e');
      setState(() {
        _faqs = defaultFAQs;
        _loadingFAQs = false;
      });
    }
  }

  Widget _buildFAQTile(String question, String answer) {
    return ExpansionTile(
      title: Text(
        question,
        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedAlignment: Alignment.topLeft,
      children: [
        Text(
          answer,
          style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Help & Support'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          children: [
            // Support Card
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need Instant Help?',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Our support team is available Monday to Saturday (09:00 AM - 06:00 PM)',
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Text('support@gymos.com', style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Text('+91 99887 76655', style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.support_agent_rounded, color: AppTheme.primary, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Raise a Support Ticket',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Submit queries & chat with our team',
                          style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportTicketsScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: Text('Open', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // FAQs Group
            Text('FREQUENTLY ASKED QUESTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: _loadingFAQs
                  ? const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    )
                  : Column(
                      children: List.generate(_faqs.length, (index) {
                        final faq = _faqs[index];
                        return Column(
                          children: [
                            _buildFAQTile(faq.question, faq.answer),
                            if (index < _faqs.length - 1) const Divider(height: 1),
                          ],
                        );
                      }),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
