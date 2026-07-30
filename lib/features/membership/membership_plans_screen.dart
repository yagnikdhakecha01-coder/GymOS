import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../membership/membership_viewmodel.dart';
import '../../core/models/membership_plan.dart';
import 'package:intl/intl.dart';
import 'membership_detail_screen.dart';
import '../../core/navigation/app_router.dart';

class MembershipPlansScreen extends StatelessWidget {
  const MembershipPlansScreen({Key? key}) : super(key: key);

  void _showAddPlan(BuildContext context) {
    Navigator.push(
      context,
      AppRouter.slideRoute(const MembershipDetailScreen(plan: null)),
    );
  }

  void _showEditPlan(BuildContext context, MembershipPlan plan) {
    Navigator.push(
      context,
      AppRouter.slideRoute(MembershipDetailScreen(plan: plan)),
    );
  }

  void _deleteConfirm(BuildContext context, MembershipViewModel vm, MembershipPlan plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: Text('Are you sure you want to delete "${plan.title}"? Active members on this plan will not be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              Navigator.pop(context);
              await vm.deletePlan(plan.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Membership plan deleted'), backgroundColor: AppTheme.success),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membershipVm = Provider.of<MembershipViewModel>(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Membership Plans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.primary, size: 28),
            onPressed: () => _showAddPlan(context),
          ),
        ],
      ),
      body: SafeArea(
        child: membershipVm.plans.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.card_membership_rounded, size: 54, color: AppTheme.textMuted),
                      const SizedBox(height: 16),
                      const Text('No membership plans yet', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                      const SizedBox(height: 6),
                      const Text('Create membership plans to define pricing and features before registering new gym members.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
                      const SizedBox(height: 20),
                      CustomButton(text: 'Create First Plan', onPressed: () => _showAddPlan(context)),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: membershipVm.plans.length,
                itemBuilder: (context, index) {
                  final plan = membershipVm.plans[index];
                  final durationLabel = '${plan.durationDays} Days';

                  return CustomCard(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    onTap: () => _showEditPlan(context, plan),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(plan.logo, style: const TextStyle(fontSize: 20)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          plan.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: plan.status == 'Active' ? AppTheme.successLight : AppTheme.dangerLight,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          plan.status,
                                          style: TextStyle(
                                            color: plan.status == 'Active' ? AppTheme.success : AppTheme.danger,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Duration: $durationLabel • Price: ₹${NumberFormat('#,##,###').format(plan.price)}',
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textMuted),
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  _showEditPlan(context, plan);
                                } else if (action == 'duplicate') {
                                  await membershipVm.duplicatePlan(plan);
                                } else if (action == 'delete') {
                                  _deleteConfirm(context, membershipVm, plan);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit Plan')),
                                const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        if (plan.description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            plan.description,
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                          ),
                        ],
                        const Divider(color: AppTheme.border, height: 24),
                        Row(
                          children: [
                            _buildFeatureIndicator('Workout', plan.workoutIncluded),
                            const SizedBox(width: 14),
                            _buildFeatureIndicator('Diet', plan.dietIncluded),
                            const SizedBox(width: 14),
                            _buildFeatureIndicator('Trainer (PT)', plan.ptIncluded),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildFeatureIndicator(String label, bool enabled) {
    return Row(
      children: [
        Icon(
          enabled ? Icons.check_circle_rounded : Icons.cancel_outlined,
          color: enabled ? AppTheme.success : AppTheme.textMuted,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
            fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
