import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/sparkline_chart.dart';
import 'finance_viewmodel.dart';
import '../../core/models/finance.dart';
import '../../core/repository/gym_repository.dart';
import 'package:intl/intl.dart';
import '../../core/theme/responsive.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  bool _showAllTransactions = false;

  void _showAddTransactionSheet(BuildContext context, String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddTransactionSheet(type: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final financeVm = Provider.of<FinanceViewModel>(context);
    final gymRepo = Provider.of<GymRepository>(context);
    final analytics = gymRepo.reportsAnalytics;
    final transactions = financeVm.transactions;
    
    final totalRevenue = financeVm.totalRevenue;
    final totalExpense = financeVm.totalExpense;
    final profit = totalRevenue - totalExpense;
    final pendingPayments = financeVm.totalPendingPayments;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mockup Header Section
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.pagePadding, 16, AppTheme.pagePadding, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Finance',
                          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Overview of your gym finances',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: financeVm.selectedDate != null ? AppTheme.primary : AppTheme.border),
                          ),
                          child: IconButton(
                            icon: Icon(
                              financeVm.selectedDate != null ? Icons.calendar_today : Icons.calendar_today_outlined, 
                              color: financeVm.selectedDate != null ? AppTheme.primary : AppTheme.textSecondary, 
                              size: 20
                            ),
                            onPressed: () async {
                              if (financeVm.selectedDate != null) {
                                financeVm.setSelectedDate(null);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Date filter cleared')),
                                );
                                return;
                              }
                               final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime(2100),
                              );
                              if (date != null) {
                                financeVm.setSelectedDate(date);
                              }
                            },
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: financeVm.filterType != 'All' ? AppTheme.primary : AppTheme.border),
                          ),
                          child: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.filter_list_rounded, 
                              color: financeVm.filterType != 'All' ? AppTheme.primary : AppTheme.textPrimary, 
                              size: 20
                            ),
                            onSelected: (val) {
                              financeVm.setFilterType(val);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'All', child: Text('All Transactions')),
                              const PopupMenuItem(value: 'Revenue', child: Text('Income Only')),
                              const PopupMenuItem(value: 'Expense', child: Text('Expenses Only')),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),

              // Mockup Top Blue Gradient Total Revenue Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Revenue',
                            style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '₹ ${NumberFormat('#,##,###').format(totalRevenue)}',
                            style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.trending_up, color: Colors.greenAccent, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${totalRevenue > 0 ? 16 : 0}% vs last month',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.w600),
                              ),
                            ],
                          )
                        ],
                      ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Mockup 2x2 Stat Cards Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                child: ResponsiveGrid(
                  crossAxisCountMobile: 2,
                  crossAxisCountTablet: 4,
                  spacing: 12,
                  runSpacing: 12,
                  childAspectRatio: context.selectValue(mobile: 1.45, smallMobile: 1.15, tablet: 1.6),
                  children: [
                    _buildGridStat(
                      icon: Icons.arrow_downward,
                      iconColor: AppTheme.success,
                      title: 'Income',
                      value: '₹ ${NumberFormat('#,##,###').format(totalRevenue)}',
                      subtitle: 'This Month',
                      trend: analytics['collected_revenue_change'] != null 
                          ? (analytics['collected_revenue_change']!.toString().startsWith('-') 
                              ? '↓ ${analytics['collected_revenue_change']!.toString().replaceAll('-', '')}' 
                              : '↑ ${analytics['collected_revenue_change']!.toString().replaceAll('+', '')}')
                          : '↑ 14%',
                      trendColor: AppTheme.success,
                    ),
                    _buildGridStat(
                      icon: Icons.arrow_upward,
                      iconColor: AppTheme.danger,
                      title: 'Expense',
                      value: '₹ ${NumberFormat('#,##,###').format(totalExpense)}',
                      subtitle: 'This Month',
                      trend: totalExpense > 0 ? '↑ 8%' : '0%',
                      trendColor: AppTheme.danger,
                    ),
                    _buildGridStat(
                      icon: Icons.bar_chart,
                      iconColor: AppTheme.info,
                      title: 'Profit',
                      value: '₹ ${NumberFormat('#,##,###').format(profit)}',
                      subtitle: 'This Month',
                      trend: analytics['total_invoiced_change'] != null 
                          ? (analytics['total_invoiced_change']!.toString().startsWith('-') 
                              ? '↓ ${analytics['total_invoiced_change']!.toString().replaceAll('-', '')}' 
                              : '↑ ${analytics['total_invoiced_change']!.toString().replaceAll('+', '')}')
                          : '↑ 16%',
                      trendColor: AppTheme.success,
                    ),
                    _buildGridStat(
                      icon: Icons.description_outlined,
                      iconColor: AppTheme.warning,
                      title: 'Outstanding',
                      value: '₹ ${NumberFormat('#,##,###').format(pendingPayments)}',
                      subtitle: 'Total Pending',
                      trend: analytics['pending_dues_change'] != null 
                          ? (analytics['pending_dues_change']!.toString().startsWith('-') 
                              ? '↓ ${analytics['pending_dues_change']!.toString().replaceAll('-', '')}' 
                              : '↑ ${analytics['pending_dues_change']!.toString().replaceAll('+', '')}')
                          : 'View >',
                      trendColor: AppTheme.warning,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Mockup Chart Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                child: CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Revenue Overview',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          Row(
                            children: [
                              Text('This Month', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                              const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Smooth curve custom sparkline graph
                      SparklineChart(
                        data: financeVm.monthlyRevenueData.isEmpty 
                            ? const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] 
                            : financeVm.monthlyRevenueData,
                        labels: const ['5th', '10th', '15th', '20th', '25th', '30th'],
                        lineColor: AppTheme.primary,
                        maxVal: _calculateMaxVal(financeVm.monthlyRevenueData),
                        customYValues: _calculateYValues(financeVm.monthlyRevenueData),
                        yLabelFormatter: (v) => v == 0 ? '0' : (v >= 100000 ? '${(v / 100000).toStringAsFixed(1).replaceAll('.0', '')}L' : '${(v / 1000).toStringAsFixed(0)}K'),
                        tooltipIndex: financeVm.monthlyRevenueData.isEmpty ? 0 : financeVm.monthlyRevenueData.length - 1,
                        tooltipDate: financeVm.monthlyRevenueData.isEmpty ? '' : '30th',
                        tooltipValueFormatter: (v) => '₹ ${NumberFormat('#,##,###').format(v)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Mockup Add Action Buttons Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Add Income',
                        icon: Icons.add,
                        color: AppTheme.success,
                        onPressed: () => _showAddTransactionSheet(context, 'Revenue'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomButton(
                        text: 'Add Expense',
                        icon: Icons.remove,
                        color: AppTheme.danger,
                        onPressed: () => _showAddTransactionSheet(context, 'Expense'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Mockup Recent Transactions List Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: AppTheme.pagePadding + 4),
                    child: Text(
                      'Recent Transactions',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showAllTransactions = !_showAllTransactions;
                      });
                    },
                    child: Text(
                      _showAllTransactions ? 'Show Less' : 'View All',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // List of transactions
              transactions.isEmpty
                  ? const Center(child: Text('No transactions recorded.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                      itemCount: _showAllTransactions ? transactions.length : transactions.take(4).length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        final isRevenue = tx.type == 'Revenue';
                        return CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isRevenue ? AppTheme.successLight : AppTheme.dangerLight,
                                child: Icon(
                                  isRevenue ? Icons.person_outline_rounded : Icons.flash_on_rounded,
                                  color: isRevenue ? AppTheme.success : AppTheme.danger,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.title,
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    Text(
                                      '${isRevenue ? "Membership Fee" : "Expense"} • by ${tx.createdByInfo.isNotEmpty ? tx.createdByInfo : "Owner"}',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                    Text(
                                      tx.date,
                                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isRevenue ? "+" : "-"} ₹ ${NumberFormat('#,##,###').format(tx.amount)}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isRevenue ? AppTheme.success : AppTheme.danger,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
                            ],
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridStat({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    required String trend,
    required Color trendColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                ),
                Text(
                  trend,
                  style: GoogleFonts.inter(fontSize: 10, color: trendColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddTransactionSheet extends StatefulWidget {
  final String type;
  const AddTransactionSheet({super.key, required this.type});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'Other';
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeVm = Provider.of<FinanceViewModel>(context, listen: false);
    final categories = widget.type == 'Revenue'
        ? ['Membership', 'Personal Training', 'Protein Sale', 'Locker Rent', 'Merchandise', 'Other']
        : ['Salary', 'Rent', 'Utilities', 'Other'];

    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = categories.first;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Add ${widget.type}', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Text('Title', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _titleController, decoration: InputDecoration(hintText: 'e.g. ${widget.type == 'Revenue' ? "Monthly Fees" : "Electricity Bill"}')),
            const SizedBox(height: 12),

            Text('Amount (₹)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g. 5000')),
            const SizedBox(height: 12),

            Text(widget.type == 'Expense' ? 'Expense Date' : 'Revenue Date', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    _selectedDate = picked;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('dd MMM yyyy').format(_selectedDate),
                      style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                    ),
                    const Icon(Icons.calendar_today, size: 18, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Text('Category', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            const SizedBox(height: 20),

            CustomButton(
              text: 'Save ${widget.type}',
              color: widget.type == 'Revenue' ? AppTheme.success : AppTheme.danger,
              onPressed: () async {
                if (_titleController.text.isEmpty || _amountController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill out all fields'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }

                await financeVm.addTransaction(
                  title: _titleController.text,
                  amount: double.tryParse(_amountController.text) ?? 0.0,
                  type: widget.type,
                  category: _selectedCategory,
                  notes: '',
                  expenseDate: widget.type == 'Expense' ? _selectedDate : null,
                  revenueDate: widget.type == 'Revenue' ? _selectedDate : null,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction saved!'), backgroundColor: AppTheme.success),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

double _calculateMaxVal(List<double> data) {
  if (data.isEmpty) return 100.0;
  double maxVal = data.reduce((curr, next) => curr > next ? curr : next);
  return maxVal <= 0 ? 100.0 : maxVal * 1.2; // Add 20% headroom
}

List<double> _calculateYValues(List<double> data) {
  double max = _calculateMaxVal(data);
  return [0.0, max * 0.25, max * 0.5, max * 0.75, max];
}

