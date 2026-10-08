import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Sidebar navigation state with URL hash and localStorage persistence
class NavigationProvider extends ChangeNotifier {
  static const String _storageKey = 'gymos_admin_active_tab_index';
  
  static const List<String> _slugs = [
    'dashboard',
    'gyms',
    'subscriptions',
    'revenue',
    'payments',
    'app-versions',
    'feature-control',
    'notifications',
    'support',
    'whatsapp',
    'whatsapp-templates',
    'duplicates',
    'analytics',
    'database',
    'audit-logs',
    'settings',
    'profile',
  ];

  int _selectedIndex = 0;
  bool _isExpanded = true;

  NavigationProvider() {
    _restoreNavigation();
    _listenToBrowserNavigation();
  }

  int get selectedIndex => _selectedIndex;
  bool get isExpanded => _isExpanded;

  void _restoreNavigation() {
    if (!kIsWeb) return;
    try {
      // 1. Try restoring from URL hash first (e.g. #gyms, #whatsapp-templates)
      final rawHash = html.window.location.hash.replaceAll('#', '').trim().toLowerCase();
      if (rawHash.isNotEmpty) {
        final hashIndex = _slugs.indexOf(rawHash);
        if (hashIndex != -1) {
          _selectedIndex = hashIndex;
          _saveIndexToStorage(hashIndex);
          return;
        }
      }

      // 2. Fallback to localStorage
      final savedIndexStr = html.window.localStorage[_storageKey];
      if (savedIndexStr != null) {
        final parsed = int.tryParse(savedIndexStr);
        if (parsed != null && parsed >= 0 && parsed < _slugs.length) {
          _selectedIndex = parsed;
          _syncHash(parsed);
          return;
        }
      }

      // 3. Default to dashboard
      _syncHash(0);
    } catch (e) {
      debugPrint('Error restoring navigation state: $e');
    }
  }

  void _listenToBrowserNavigation() {
    if (!kIsWeb) return;
    try {
      html.window.onHashChange.listen((_) {
        final rawHash = html.window.location.hash.replaceAll('#', '').trim().toLowerCase();
        if (rawHash.isNotEmpty) {
          final hashIndex = _slugs.indexOf(rawHash);
          if (hashIndex != -1 && hashIndex != _selectedIndex) {
            _selectedIndex = hashIndex;
            _saveIndexToStorage(hashIndex);
            notifyListeners();
          }
        }
      });
    } catch (e) {
      debugPrint('Error listening to browser hash changes: $e');
    }
  }

  void _syncHash(int index) {
    if (!kIsWeb) return;
    try {
      if (index >= 0 && index < _slugs.length) {
        final slug = _slugs[index];
        final currentHash = html.window.location.hash.replaceAll('#', '').trim();
        if (currentHash != slug) {
          html.window.location.hash = '#$slug';
        }
      }
    } catch (e) {
      debugPrint('Error syncing URL hash: $e');
    }
  }

  void _saveIndexToStorage(int index) {
    if (!kIsWeb) return;
    try {
      html.window.localStorage[_storageKey] = index.toString();
    } catch (e) {
      debugPrint('Error saving index to localStorage: $e');
    }
  }

  void setIndex(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    _saveIndexToStorage(index);
    _syncHash(index);
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

