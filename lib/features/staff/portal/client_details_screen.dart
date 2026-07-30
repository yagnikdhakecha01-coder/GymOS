import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/widgets/custom_button.dart';

class ClientDetailsScreen extends StatelessWidget {
  final String name;
  final String program;
  final String status;
  final String imageUrl;

  const ClientDetailsScreen({
    super.key,
    required this.name,
    required this.program,
    required this.status,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Client Details',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textPrimary),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Card Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(imageUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '+91 98765 43210',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          program,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(status),
                ],
              ),
            ),

            // Tab selector
            Container(
              color: Colors.white,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                dividerColor: const Color(0xFFF3F4F6),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Attendance'),
                  Tab(text: 'Progress'),
                  Tab(text: 'Plan'),
                  Tab(text: 'Payments'),
                ],
              ),
            ),

            // Tab body (Only implementing Overview high fidelity to match image)
            Expanded(
              child: TabBarView(
                children: [
                  _buildOverviewTab(),
                  _buildPlaceholderTab(),
                  _buildPlaceholderTab(),
                  _buildPlaceholderTab(),
                  _buildPlaceholderTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Joined / Sessions info card
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailsStat('Joined On', '10 Apr 2025'),
                  _buildDetailsStat('Next Expiry', '10 Jul 2025'),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailsStat('Total Sessions', '24'),
                  _buildDetailsStat('Completed', '16', valueColor: Colors.green),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Program Details card
        Text(
          'Program Details',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProgramRow('Goal', 'Weight Gain'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Duration', '3 Months'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Days', 'Mon, Wed, Fri, Sat'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Time', '7:00 AM'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Status', 'Active', valueColor: Colors.green),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Actions buttons row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('Message'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomButton(
                text: 'View Plan',
                color: AppTheme.primary,
                onPressed: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildProgramRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary)),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab() {
    return const Center(child: Text('History or progress records...', style: TextStyle(color: AppTheme.textMuted)));
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
