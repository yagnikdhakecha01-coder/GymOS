import 'package:flutter/material.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/finance.dart';
import '../../core/services/supabase_service.dart';
import 'package:intl/intl.dart';

class FinanceViewModel extends ChangeNotifier {
  final GymRepository _repository;

  // Database stats cache
  double _dbTotalRevenue = 0.0;
  double _dbTotalExpense = 0.0;
  double _dbNetProfit = 0.0;
  double _dbMemberPendingTotal = 0.0;
  double _dbSalaryDueTotal = 0.0;
  bool _pendingTotalsLoaded = false;
  List<double> _dbMonthlyRevenueData = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
  bool _loadingFinanceStats = false;

  FinanceViewModel(this._repository) {
    fetchTransactions();
    _repository.addListener(_onRepositoryChanged);
  }

  void _onRepositoryChanged() {
    final gymId = _repository.storage.getGymInfo()?['id'];
    if (gymId != null) {
      fetchFinanceSummary(gymId, _selectedDate ?? DateTime.now());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  Future<void> fetchTransactions() async {
    await _repository.fetchTransactionsFromSupabase();
    final gymId = _repository.storage.getGymInfo()?['id'];
    if (gymId != null) {
      await fetchFinanceSummary(gymId, _selectedDate ?? DateTime.now());
    }
    notifyListeners();
  }

  // Getters
  String _filterType = 'All';
  DateTime? _selectedDate;

  String get filterType => _filterType;
  DateTime? get selectedDate => _selectedDate;

  double get totalRevenue => _dbTotalRevenue;
  double get totalExpense => _dbTotalExpense;
  double get totalProfit => _dbNetProfit;
  List<double> get monthlyRevenueData => _dbMonthlyRevenueData;
  bool get loadingFinanceStats => _loadingFinanceStats;

  void setFilterType(String type) {
    _filterType = type;
    notifyListeners();
  }

  void setSelectedDate(DateTime? date) {
    _selectedDate = date;
    notifyListeners();
    final gymId = _repository.storage.getGymInfo()?['id'];
    if (gymId != null) {
      fetchFinanceSummary(gymId, date ?? DateTime.now());
    }
  }

  Future<void> fetchFinanceSummary(String gymId, DateTime targetDate) async {
    if (!SupabaseService.isInitialized) return;
    _loadingFinanceStats = true;
    notifyListeners();
    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(targetDate);
      final response = await SupabaseService.client.rpc(
        'get_finance_summary',
        params: {
          'p_gym_id': gymId,
          'p_target_date': formattedDate,
        },
      );
      if (response != null && response is List && response.isNotEmpty) {
        final data = response[0] as Map<String, dynamic>;
        _dbTotalRevenue = (data['total_revenue'] as num?)?.toDouble() ?? 0.0;
        _dbTotalExpense = (data['total_expense'] as num?)?.toDouble() ?? 0.0;
        _dbNetProfit = (data['net_profit'] as num?)?.toDouble() ?? 0.0;
        
        final rawData = data['monthly_revenue_data'] as List?;
        if (rawData != null) {
          _dbMonthlyRevenueData = rawData.map((e) => (e as num).toDouble()).toList();
        }
      }

      await _fetchPendingTotalsFromDb(gymId);
    } catch (e) {
      print('Error fetching finance summary: $e');
    } finally {
      _loadingFinanceStats = false;
      notifyListeners();
    }
  }

  Future<void> _fetchPendingTotalsFromDb(String gymId) async {
    if (!SupabaseService.isInitialized) return;
    try {
      final memberPending = await SupabaseService.client.rpc(
        'get_gym_member_pending_total',
        params: {'p_gym_id': gymId},
      );
      if (memberPending != null) {
        _dbMemberPendingTotal = (memberPending as num).toDouble();
      }
    } catch (e) {
      print('get_gym_member_pending_total error: $e');
      _dbMemberPendingTotal = _repository.getMembers().fold(0.0, (sum, m) => sum + m.pendingAmount);
    }
    try {
      final salaryDue = await SupabaseService.client.rpc(
        'get_total_salary_due',
        params: {'p_gym_id': gymId},
      );
      if (salaryDue != null) {
        _dbSalaryDueTotal = (salaryDue as num).toDouble();
      }
    } catch (e) {
      print('get_total_salary_due error: $e');
      _dbSalaryDueTotal = _repository.getStaff().fold(0.0, (sum, s) => sum + s.salaryDue);
    }
    _pendingTotalsLoaded = true;
  }

  List<FinanceTransaction> get transactions {
    var list = List<FinanceTransaction>.from(_repository.getTransactions());
    if (_filterType != 'All') {
      list = list.where((t) => t.type == _filterType).toList();
    }
    if (_selectedDate != null) {
      final formattedDate = DateFormat('dd MMM yyyy').format(_selectedDate!);
      list = list.where((t) => t.date == formattedDate).toList();
    }
    list.sort((a, b) {
      if (a.transactionDate.isNotEmpty && b.transactionDate.isNotEmpty) {
        return b.transactionDate.compareTo(a.transactionDate);
      }
      return b.id.compareTo(a.id);
    });
    return list;
  }

  double get totalPendingPayments {
    if (_pendingTotalsLoaded) return _dbMemberPendingTotal;
    return _repository.getMembers().fold(0.0, (sum, m) => sum + m.pendingAmount);
  }

  double get totalSalaryDue {
    if (_pendingTotalsLoaded) return _dbSalaryDueTotal;
    return _repository.getStaff().fold(0.0, (sum, s) => sum + s.salaryDue);
  }

  Future<void> addTransaction({
    required String title,
    required double amount,
    required String type,
    required String category,
    String paymentMethod = 'Cash',
    required String notes,
    String referenceId = '',
    DateTime? expenseDate,
    DateTime? revenueDate,
  }) async {
    final finalTxDate = revenueDate ?? expenseDate ?? DateTime.now();
    final newTx = FinanceTransaction(
      id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      amount: amount,
      type: type,
      category: category,
      paymentMethod: paymentMethod,
      date: DateFormat('dd MMM yyyy').format(finalTxDate),
      transactionDate: finalTxDate.toIso8601String(),
      notes: notes,
      referenceId: referenceId,
      expenseDate: expenseDate != null ? DateFormat('yyyy-MM-dd').format(expenseDate) : '',
      revenueDate: revenueDate != null ? DateFormat('yyyy-MM-dd').format(revenueDate) : '',
      entryDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    await _repository.saveTransaction(newTx);
    final gymId = _repository.storage.getGymInfo()?['id'];
    if (gymId != null) {
      await fetchFinanceSummary(gymId, _selectedDate ?? DateTime.now());
    }
    notifyListeners();
  }

  Future<void> deleteTransaction(String id) async {
    await _repository.deleteTransaction(id);
    final gymId = _repository.storage.getGymInfo()?['id'];
    if (gymId != null) {
      await fetchFinanceSummary(gymId, _selectedDate ?? DateTime.now());
    }
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }
}
