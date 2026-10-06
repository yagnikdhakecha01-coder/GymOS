import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/trial_member.dart';
import '../../core/models/finance.dart';

class TrialMembersViewModel extends ChangeNotifier {
  final GymRepository _repository;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Active, Expired, Converted, Free Trial, Paid Trial

  TrialMembersViewModel(this._repository) {
    fetchTrialMembers();
    _repository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _repository.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> fetchTrialMembers() async {
    await _repository.fetchTrialMembersFromSupabase();
    notifyListeners();
  }

  // Get/Set Search and Filters
  String get searchQuery => _searchQuery;
  String get selectedFilter => _selectedFilter;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilter(String filter) {
    _selectedFilter = filter;
    notifyListeners();
  }

  List<TrialMember> get allTrials => _repository.getTrialMembers();

  List<TrialMember> get filteredTrials {
    final query = _searchQuery.trim().toLowerCase();
    
    return allTrials.where((trial) {
      // 1. Search filter
      final matchesSearch = trial.name.toLowerCase().contains(query) ||
          trial.phone.contains(query);
      if (!matchesSearch) return false;

      // 2. Tab filter
      final effStatus = trial.calculatedStatus;
      switch (_selectedFilter) {
        case 'Active':
          return effStatus == 'Active';
        case 'Expiring / Expired':
        case 'Expired':
          return trial.isExpiringTodayOrExpired || effStatus == 'Expired';
        case 'Converted':
          return effStatus == 'Converted';
        case 'Free Trial':
          return trial.trialType == 'Free';
        case 'Paid Trial':
          return trial.trialType == 'Paid';
        default:
          return true;
      }
    }).toList();
  }

  // Save Trial Member
  Future<void> addTrialMember(TrialMember trial, {String paymentMethod = 'Cash'}) async {
    await _repository.saveTrialMember(trial);
    
    // Log Finance entry if Paid and received amount > 0
    if (trial.trialType == 'Paid' && trial.receivedAmount > 0) {
      final txId = 'tx_trial_${DateTime.now().millisecondsSinceEpoch}';
      final tx = FinanceTransaction(
        id: txId,
        title: '${trial.name} - Trial Fee',
        amount: trial.receivedAmount,
        type: 'Revenue',
        category: 'Trial Membership', // Category updated in check constraint
        paymentMethod: paymentMethod,
        date: DateFormat('dd MMM yyyy').format(DateTime.now()),
        transactionDate: DateTime.now().toIso8601String(),
        notes: 'Initial Paid Trial Registration Fee',
        referenceId: trial.id,
      );
      await _repository.saveTransaction(tx);
    }
    notifyListeners();
  }

  // Update Trial Member (Edits)
  Future<void> updateTrialMember(TrialMember trial, {String paymentMethod = 'Cash'}) async {
    final oldTrials = _repository.getTrialMembers();
    final oldMatch = oldTrials.where((t) => t.id == trial.id).toList();
    final double oldReceived = oldMatch.isNotEmpty ? oldMatch.first.receivedAmount : 0.0;

    await _repository.saveTrialMember(trial);

    final double newReceived = trial.receivedAmount;
    final double diff = newReceived - oldReceived;

    if (diff > 0 && trial.trialType == 'Paid') {
      final txId = 'tx_trial_edit_${DateTime.now().millisecondsSinceEpoch}';
      final tx = FinanceTransaction(
        id: txId,
        title: '${trial.name} - Trial Fee Payment',
        amount: diff,
        type: 'Revenue',
        category: 'Trial Membership',
        paymentMethod: paymentMethod,
        date: DateFormat('dd MMM yyyy').format(DateTime.now()),
        transactionDate: DateTime.now().toIso8601String(),
        notes: 'Trial Registration Fee Payment Update (Edited)',
        referenceId: trial.id,
      );
      await _repository.saveTransaction(tx);
    }
    notifyListeners();
  }

  // Mark trial status (e.g. Converted)
  Future<void> markAsConverted(String trialId) async {
    await _repository.updateTrialStatus(trialId, 'Converted');
    notifyListeners();
  }
}
