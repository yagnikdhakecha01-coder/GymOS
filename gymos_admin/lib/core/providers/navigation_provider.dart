import 'package:flutter/material.dart';

/// Sidebar navigation state
class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = 0;
  bool _isExpanded = true;

  int get selectedIndex => _selectedIndex;
  bool get isExpanded => _isExpanded;

  void setIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void toggleSidebar() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void collapseSidebar() {
    _isExpanded = false;
    notifyListeners();
  }

  void expandSidebar() {
    _isExpanded = true;
    notifyListeners();
  }
}
