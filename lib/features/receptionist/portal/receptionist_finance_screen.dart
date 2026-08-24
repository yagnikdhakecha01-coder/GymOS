import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/repository/gym_repository.dart';
import '../../../core/models/finance.dart';
import '../../../core/widgets/success_dialog.dart';
import '../../finance/finance_viewmodel.dart';
import '../receptionist_viewmodel.dart';
import 'widgets/receptionist_restricted_widget.dart';

class ReceptionistFinanceScreen extends StatefulWidget {
  const ReceptionistFinanceScreen({super.key});

  @override
  State<ReceptionistFinanceScreen> createState() => _ReceptionistFinanceScreenState();
}

class _ReceptionistFinanceScreenState extends State<ReceptionistFinanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _rawTransactions = [];
  bool _isLoading = false;
  String _selectedPeriod = 'Today'; // 'Today', 'This Month', 'All Time', 'Custom'
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    final vm = Provider.of<ReceptionistViewModel>(context, listen: false);
    final gymRepo = Provider.of<GymRepository>(context, listen: false);
    final gymId = vm.staffRecord?.gymId ?? gymRepo.storage.getGymInfo()?['id'];
    if (gymId == null || gymId.toString().isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final res = await SupabaseService.client
          .from('finance_transactions')
          .select()
          .eq('gym_id', gymId)
          .order('transaction_date', ascending: false)
          .limit(300);

      if (mounted) {
        setState(() {
          _rawTransactions = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading receptionist transactions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredTransactions() {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    return _rawTransactions.where((tx) {
      final txDateRaw = tx['transaction_date']?.toString() ?? 
          tx['revenue_date']?.toString() ?? 
          tx['expense_date']?.toString() ?? 
          tx['created_at']?.toString();
      if (txDateRaw == null || txDateRaw.isEmpty) return false;

      DateTime? dt;
      try {
        dt = DateTime.parse(txDateRaw).toLocal();
      } catch (_) {
        return false;
      }

      if (_selectedPeriod == 'Today') {
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      } else if (_selectedPeriod == 'This Month') {
        return dt.year == now.year && dt.month == now.month;
      } else if (_selectedPeriod == 'Custom' && _customDate != null) {
        return dt.year == _customDate!.year && dt.month == _customDate!.month && dt.day == _customDate!.day;
      }
      return true; // 'All Time'
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<ReceptionistViewModel>(context);
    final canViewIncome = vm.hasPermission('add_income');
    final canViewExpense = vm.hasPermission('add_expense');

    if (!canViewIncome && !canViewExpense) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: RestrictedAccessWidget(moduleName: 'Finance'),
        ),
      );
    }

    final filteredTx = _getFilteredTransactions();
    final incomeList = filteredTx.where((tx) => tx['type'] == 'Revenue').toList();
    final expenseList = filteredTx.where((tx) => tx['type'] == 'Expense').toList();

    final totalIncome = incomeList.fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0));
    final totalExpense = expenseList.fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0));

    String periodLabel = _selectedPeriod;
    if (_selectedPeriod == 'Custom' && _customDate != null) {
      periodLabel = DateFormat('dd MMM yyyy').format(_customDate!);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Finance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 22),
            tooltip: 'Sync & Refresh Database',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing latest database records...'),
                  duration: Duration(seconds: 1),
                ),
              );
              await _fetchTransactions();
              final gymRepo = Provider.of<GymRepository>(context, listen: false);
              final financeVm = Provider.of<FinanceViewModel>(context, listen: false);
              final gymId = vm.staffRecord?.gymId ?? gymRepo.storage.getGymInfo()?['id'];
              await gymRepo.fetchTransactionsFromSupabase();
              if (gymId != null && gymId.toString().isNotEmpty) {
                await financeVm.fetchFinanceSummary(gymId, DateTime.now());
              }
              await vm.fetchDashboardStats();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Finance data updated from database!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Income'),
            Tab(text: 'Expense'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Period Filter Chips Row
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPeriodChip('Today'),
                  const SizedBox(width: 8),
                  _buildPeriodChip('This Month'),
                  const SizedBox(width: 8),
                  _buildPeriodChip('All Time'),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _customDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() {
                          _customDate = picked;
                          _selectedPeriod = 'Custom';
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedPeriod == 'Custom' ? AppTheme.primary : AppTheme.surfaceGray,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _selectedPeriod == 'Custom' ? AppTheme.primary : AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: _selectedPeriod == 'Custom' ? Colors.white : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _selectedPeriod == 'Custom' && _customDate != null
                                ? DateFormat('dd MMM').format(_customDate!)
                                : 'Pick Date',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _selectedPeriod == 'Custom' ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Income Tab
                canViewIncome
                    ? _buildFinanceTabContent(
                        type: 'Income',
                        periodLabel: periodLabel,
                        totalAmount: totalIncome,
                        list: incomeList,
                        btnColor: Colors.green,
                        onAddTap: () => _showAddTransactionBottomSheet('Income'),
                      )
                    : const RestrictedAccessWidget(moduleName: 'Income'),

                // Expense Tab
                canViewExpense
                    ? _buildFinanceTabContent(
                        type: 'Expense',
                        periodLabel: periodLabel,
                        totalAmount: totalExpense,
                        list: expenseList,
                        btnColor: Colors.red,
                        onAddTap: () => _showAddTransactionBottomSheet('Expense'),
                      )
                    : const RestrictedAccessWidget(moduleName: 'Expense'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String period) {
    final isSelected = _selectedPeriod == period;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPeriod = period;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceGray,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(
          period,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFinanceTabContent({
    required String type,
    required String periodLabel,
    required double totalAmount,
    required List<Map<String, dynamic>> list,
    required Color btnColor,
    required VoidCallback onAddTap,
  }) {
    return Column(
      children: [
        // Summary Card
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: btnColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: btnColor.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total $type ($periodLabel)',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: btnColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${list.length} ${list.length == 1 ? 'record' : 'records'}',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: btnColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '₹${NumberFormat('#,##,###').format(totalAmount)}',
                      style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: onAddTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Add $type',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Transactions list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textSecondary.withOpacity(0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'No $type logged for $periodLabel.',
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 12),
                            if (_selectedPeriod != 'This Month')
                              OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_month_rounded, size: 14),
                                label: const Text('View This Month'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: const BorderSide(color: AppTheme.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed: () {
                                  setState(() => _selectedPeriod = 'This Month');
                                },
                              ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final tx = list[index];
                        final title = tx['title'] ?? (type == 'Income' ? 'Gym Revenue' : 'Gym Expense');
                        final category = tx['category'] ?? 'General';
                        final paymentMethod = tx['payment_method'] ?? 'Cash';
                        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                        
                        String timeStr = '—';
                        final txDateRaw = tx['transaction_date'] ?? tx['revenue_date'] ?? tx['expense_date'] ?? tx['created_at'];
                        if (txDateRaw != null) {
                          try {
                            final dt = DateTime.parse(txDateRaw.toString()).toLocal();
                            timeStr = DateFormat('dd MMM, hh:mm a').format(dt);
                          } catch (_) {
                            timeStr = txDateRaw.toString();
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: btnColor.withOpacity(0.08),
                                radius: 18,
                                child: Icon(
                                  type == 'Income' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  size: 16,
                                  color: btnColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppTheme.surfaceGray,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            category,
                                            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '• $timeStr',
                                          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹${NumberFormat('#,##,###').format(amount)}',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: btnColor),
                                  ),
                                  Text(
                                    paymentMethod,
                                    style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
  }

  void _showAddTransactionBottomSheet(String type) {
    final isIncome = type == 'Income' || type == 'Revenue';
    final displayType = isIncome ? 'Income' : 'Expense';
    final dbType = isIncome ? 'Revenue' : 'Expense';

    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final vm = Provider.of<ReceptionistViewModel>(context, listen: false);
    
    final List<String> categories = isIncome 
        ? ['Membership', 'Personal Training', 'Protein Sale', 'Locker Rent', 'Merchandise', 'Other']
        : ['Salary', 'Rent', 'Utilities', 'Maintenance', 'Equipment', 'Other'];
        
    String selectedCategory = categories.first;
    DateTime selectedTxDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add $displayType',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // DATE SELECTION FIELD (INCOME DATE / EXPENSE DATE)
                    Text(
                      isIncome ? 'INCOME DATE' : 'EXPENSE DATE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedTxDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedTxDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('dd MMMM yyyy').format(selectedTxDate),
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'TITLE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Monthly Fee, Gym Rent, Electric bill',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: GoogleFonts.inter(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AMOUNT (₹)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Enter amount in ₹',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'CATEGORY',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                          items: categories.map((String cat) {
                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Text(
                                cat,
                                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedCategory = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isIncome ? Colors.green : AppTheme.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final amt = double.tryParse(amountController.text) ?? 0.0;
                        final title = titleController.text.trim();
                        if (title.isEmpty || amt <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid title and amount greater than 0.')),
                          );
                          return;
                        }

                        final gymRepo = Provider.of<GymRepository>(context, listen: false);
                        final financeVm = Provider.of<FinanceViewModel>(context, listen: false);

                        final selectedDateStr = DateFormat('yyyy-MM-dd').format(selectedTxDate);
                        final txDateIso = DateTime(
                          selectedTxDate.year,
                          selectedTxDate.month,
                          selectedTxDate.day,
                          DateTime.now().hour,
                          DateTime.now().minute,
                          DateTime.now().second,
                        ).toIso8601String();
                        final gymId = vm.staffRecord?.gymId ?? gymRepo.storage.getGymInfo()?['id'] ?? '';

                        final tx = FinanceTransaction(
                          id: '',
                          gymId: gymId,
                          title: title,
                          amount: amt,
                          type: dbType,
                          category: selectedCategory,
                          paymentMethod: 'Cash',
                          date: DateFormat('dd MMM yyyy').format(selectedTxDate),
                          transactionDate: txDateIso,
                          expenseDate: selectedDateStr,
                          revenueDate: selectedDateStr,
                          entryDate: selectedDateStr,
                          notes: title,
                          createdByInfo: 'Receptionist - ${vm.staffRecord?.name ?? ''}',
                        );

                        // 1. Single unified transaction save (updates local cache, performs single upsert to DB, no duplicates!)
                        await gymRepo.saveTransaction(tx);

                        // 2. Log activity, refresh all viewmodels, close modal & show success dialog
                        vm.logActivity('$displayType Added: $title ($selectedCategory - ₹${NumberFormat('#,##,###').format(amt)})', 'finance');
                        
                        if (context.mounted) {
                          Navigator.pop(context);
                          _fetchTransactions();
                          vm.fetchDashboardStats();
                          await gymRepo.fetchTransactionsFromSupabase();
                          if (gymId.isNotEmpty) {
                            await financeVm.fetchFinanceSummary(gymId, selectedTxDate);
                          }

                          SuccessDialog.show(
                            context,
                            title: '$displayType Saved Successfully!',
                            message: '₹${NumberFormat('#,##,###').format(amt)} recorded for $title ($selectedCategory) on ${DateFormat('dd MMM yyyy').format(selectedTxDate)}.',
                          );
                        }
                      },
                      child: Text(
                        'Save $displayType',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
