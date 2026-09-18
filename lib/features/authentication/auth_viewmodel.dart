import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/local_storage.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/staff.dart';
import '../../core/models/association_model.dart';
import '../../core/repository/gym_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/gym_logo_cache_service.dart';

class AuthViewModel extends ChangeNotifier {
  final LocalStorageService _storage;
  final GymRepository _gymRepository;
  final AuthService _authService = AuthService();

  String? _selectedRole;
  bool _isLoggedIn = false;
  Map<String, dynamic>? _gymInfo;
  UserProfile? _currentProfile;
  Staff? _staffRecord;
  bool _isLoading = false;
  List<UserGymAssociation> _userAssociations = [];
  UserGymAssociation? _activeAssociation;

  int _unreadNotificationsCount = 0;

  Map<String, dynamic>? _subscriptionInfo;
  bool _isSubscriptionExpired = false;
  bool _isOffline = false;

  AuthViewModel(this._storage, this._gymRepository) {
    final bool hasLocalLogin = _storage.isLoggedIn();
    bool hasSupabaseSession = false;
    try {
      if (SupabaseService.isInitialized) {
        hasSupabaseSession = SupabaseService.client.auth.currentSession != null;
      }
    } catch (_) {}
    _isLoggedIn = hasLocalLogin || hasSupabaseSession;
    _selectedRole = _storage.getUserRole();
    _gymInfo = _storage.getGymInfo();
  }

  // Getters
  LocalStorageService get storage => _storage;
  int get unreadNotificationsCount => _unreadNotificationsCount;
  String? get selectedRole => _selectedRole;
  bool get isLoggedIn => _isLoggedIn;
  Map<String, dynamic>? get gymInfo => _gymInfo;
  UserProfile? get currentProfile => _currentProfile;
  Staff? get staffRecord => _staffRecord;
  bool get isLoading => _isLoading;
  User? get currentUser => _authService.currentUser;
  List<UserGymAssociation> get userAssociations => _userAssociations;
  UserGymAssociation? get activeAssociation => _activeAssociation;
  Map<String, dynamic>? get subscriptionInfo => _subscriptionInfo;
  bool get isSubscriptionExpired => _isSubscriptionExpired;
  bool get isOffline => _isOffline;

  // Custom Whitelabel Branding Getters
  bool get isCustomBrandingEnabled {
    final allowed = _gymInfo?['custom_branding_allowed'] == true || _storage.getBrandingEnabled();
    final plan = _subscriptionInfo?['plan']?.toString() ?? _gymInfo?['plan']?.toString() ?? 'free_trial';
    final status = _subscriptionInfo?['status']?.toString() ?? _gymInfo?['status']?.toString() ?? 'trial';
    final hasPremiumPlan = plan == 'pro' || plan == 'business';
    final isActive = status == 'active' || status == 'trial';
    return allowed || (hasPremiumPlan && isActive);
  }
  String get customBrandingName => _storage.getBrandingName() ?? _gymInfo?['name'] ?? 'GYMOS';
  String? get customBrandingLogoUrl => _storage.getBrandingLogoUrl() ?? _gymInfo?['logo_url'] ?? _gymInfo?['logo'] ?? '';
  String? get customBrandingLogoBase64 => _storage.getCachedImage('custom_gym_logo');

  void clearUnreadNotifications() {
    _unreadNotificationsCount = 0;
    notifyListeners();

    // Mark notifications as read in Supabase for current role
    final gymId = activeAssociation?.gymId ?? gymInfo?['id'];
    if (gymId != null && SupabaseService.isInitialized) {
      final role = (_selectedRole ?? _storage.getUserRole() ?? '').toLowerCase();
      final bool isOwner = role == 'owner' || role == 'superadmin' || role == 'admin';
      final bool isStaff = role == 'staff' || role == 'receptionist' || role == 'trainer';
      final staffId = _staffRecord?.id;
      final authUid = currentUser?.id;
      final memberId = _storage.getString('member_id');

      SupabaseService.client
          .from('notifications')
          .select('id, target_role, user_id')
          .eq('gym_id', gymId)
          .eq('is_read', false)
          .then((res) {
            final matchingIds = (res as List).where((n) {
              final targetRole = (n['target_role']?.toString() ?? '').toLowerCase();
              final notifUserId = n['user_id']?.toString();
              if (isOwner) {
                return targetRole == 'owner' || targetRole == 'all' || targetRole == 'both' || targetRole.isEmpty;
              } else if (isStaff) {
                if (targetRole == 'owner') return false;
                final isRoleMatch = targetRole == 'staff' || targetRole == 'all' || targetRole == 'both';
                if (!isRoleMatch) return false;
                if (notifUserId != null && notifUserId.isNotEmpty) {
                  return notifUserId == staffId || notifUserId == authUid;
                }
                return true;
              } else {
                if (targetRole == 'owner' || targetRole == 'staff') return false;
                final isRoleMatch = targetRole == 'member' || targetRole == 'all' || targetRole == 'both';
                if (!isRoleMatch) return false;
                if (notifUserId != null && notifUserId.isNotEmpty) {
                  return notifUserId == memberId || notifUserId == authUid;
                }
                return true;
              }
            }).map((n) => n['id'].toString()).toList();

            if (matchingIds.isNotEmpty) {
              SupabaseService.client
                  .from('notifications')
                  .update({'is_read': true})
                  .filter('id', 'in', matchingIds)
                  .then((_) {});
            }
          })
          .catchError((e) {
            print('Error updating notifications in Supabase: $e');
          });
    }
  }

  void setUnreadNotificationsCount(int count) {
    _unreadNotificationsCount = count;
    notifyListeners();
  }

  Future<void> selectRole(String role) async {
    _selectedRole = role;
    await _storage.setUserRole(role);
    notifyListeners();
  }

  String? getCachedImage(String key) => _storage.getCachedImage(key);

  Future<void> cacheImageLocally(String? url, String key) async {
    if (url == null || url.isEmpty || (!url.startsWith('http') && !url.startsWith('https'))) return;
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>([], (list, element) => list..addAll(element));
        final base64Str = base64Encode(bytes);
        await _storage.setCachedImage(key, base64Str);
        await GymLogoCacheService.cacheLogoBase64(_storage, activeAssociation?.gymId ?? gymInfo?['id']?.toString(), base64Str);
        notifyListeners();
      }
    } catch (e) {
      print('Error caching image locally for key $key: $e');
    }
  }

  /// Sets loading state
  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  /// Performs server-side verified login
  Future<void> login(String email, String password) async {
    _setLoading(true);
    try {
      await _authService.signIn(
        email: email,
        password: password,
      );

      // Load profile
      final profile = await _authService.getVerifiedProfile();
      _currentProfile = profile;
      if (profile?.photoUrl != null && profile!.photoUrl!.isNotEmpty) {
        cacheImageLocally(profile.photoUrl, 'user_avatar');
      }
      _isLoggedIn = true;
      await _storage.setLoggedIn(true);

      if (profile != null) {
        // Fetch associations
        final allAssociations = (await _authService.getUserGymAssociations(profile.id)) ?? [];
        _userAssociations = allAssociations;

        _staffRecord = null;

        UserRole? desiredRole;
        if (_selectedRole == 'owner') desiredRole = UserRole.owner;
        if (_selectedRole == 'staff') desiredRole = UserRole.staff;
        if (_selectedRole == 'member') desiredRole = UserRole.member;

        final matchingAssocs = desiredRole != null
            ? _userAssociations.where((a) => a.role == desiredRole).toList()
            : _userAssociations;

        if (matchingAssocs.isEmpty) {
          _activeAssociation = null;
          _gymInfo = null;
          await _storage.remove(LocalStorageService.keyUserGymInfo);
          if (desiredRole != null) {
            _currentProfile = profile.copyWith(
              role: desiredRole,
              gymId: '',
              setupCompleted: false,
            );
            await _storage.setUserRole(_selectedRole!);
          } else {
            _selectedRole = _storage.getUserRole();
          }
        } else if (matchingAssocs.length == 1) {
          final assoc = matchingAssocs.first;
          await selectAssociation(assoc);
        } else {
          // Multiple associations exist: the UI must direct to selector.
          _activeAssociation = null;
          _gymInfo = null;
          await _storage.remove(LocalStorageService.keyUserGymInfo);
        }
      }
      await fetchSubscriptionStatus();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Switches active profile/gym context
  Future<void> selectAssociation(UserGymAssociation assoc) async {
    _activeAssociation = assoc;
    _selectedRole = assoc.role.name;
    await _storage.setUserRole(_selectedRole!);

    if (_currentProfile != null) {
      _currentProfile = _currentProfile!.copyWith(
        role: assoc.role,
        gymId: assoc.gymId,
        setupCompleted: assoc.setupCompleted,
      );
    }

    try {
      final gymData = await SupabaseService.client
          .from('gyms')
          .select()
          .eq('id', assoc.gymId)
          .maybeSingle();

      if (gymData != null) {
        final info = {
          'id': gymData['id'],
          'name': gymData['name'],
          'logo': gymData['logo_url'] ?? '',
          'logo_url': gymData['logo_url'] ?? '',
          'gym_code': gymData['gym_code'],
          'owner': _currentProfile?.email ?? '',
          'email': gymData['email'] ?? _currentProfile?.email ?? '',
          'phone': gymData['phone_number'] ?? '',
          'address': gymData['address'] ?? '',
          'city': gymData['city'] ?? '',
          'state': gymData['state'] ?? '',
          'country': gymData['country'] ?? '',
          'pin_code': gymData['pin_code'] ?? '',
          'gym_type': gymData['gym_type'] ?? '',
          'status': gymData['status'] ?? 'active',
          'is_locked': gymData['is_locked'] ?? false,
        };
        _gymInfo = info;
        await _storage.setGymInfo(info);
        final logoUrl = info['logo'] ?? info['logo_url'];
        if (logoUrl != null && logoUrl.isNotEmpty) {
          cacheImageLocally(logoUrl, 'gym_logo_${info['id']}');
        }
      }
    } catch (_) {
      final info = {
        'id': assoc.gymId,
        'name': assoc.gymName ?? 'GYMOS',
        'gym_code': assoc.gymCode ?? 'MOCK1234',
        'owner': _currentProfile?.email ?? '',
      };
      _gymInfo = info;
      await _storage.setGymInfo(info);
    }

    if (assoc.role == UserRole.staff) {
      try {
        final userId = _currentProfile?.id ?? SupabaseService.client.auth.currentUser?.id;
        if (userId != null) {
          final res = await SupabaseService.client
              .from('staff')
              .select()
              .eq('user_id', userId)
              .eq('gym_id', assoc.gymId)
              .maybeSingle();
          if (res != null) {
            _staffRecord = Staff.fromJson(res);
          }
        }
      } catch (e) {
        print('Error loading staff record in selectAssociation: $e');
      }
    } else {
      _staffRecord = null;
    }

    // Clear repository cache and reload for the new gym context
    _gymRepository.clearAllData();
    await _gymRepository.reloadForActiveGym();
    _gymRepository.syncAllFromSupabase();

    await fetchSubscriptionStatus();
    notifyListeners();
  }

  /// Creates an additional gym under the owner profile context
  Future<UserGymAssociation?> createAdditionalGym({
    required String gymName,
    required String gymLogo,
    required String gymType,
    required String gymPhone,
    required String gymEmail,
    required String gymAddress,
    required String gymCity,
    required String gymState,
    required String gymCountry,
    required String gymPinCode,
  }) async {
    _setLoading(true);
    try {
      final uid = currentUser?.id ?? 'mock_user_123';
      final email = currentUser?.email ?? gymEmail;
      
      String gymId = 'mock_gym_${DateTime.now().millisecondsSinceEpoch}';
      if (SupabaseService.client != null) {
        // Count how many gyms this owner already owns
        final currentGymsRes = await SupabaseService.client
            .from('user_gym_associations')
            .select('gym_id')
            .eq('user_id', uid)
            .eq('role', 'owner');
        final currentGymsCount = (currentGymsRes as List).length;

        // Query the owner's active plan limits from their existing subscriptions
        int maxGymsLimit = 1;
        String planName = 'Trial';

        if (currentGymsCount > 0) {
          final existingGymId = currentGymsRes.first['gym_id'];
          final subRes = await SupabaseService.client
              .from('subscriptions')
              .select('plan_id, subscription_plans(max_gyms, name)')
              .eq('gym_id', existingGymId)
              .maybeSingle();
          if (subRes != null) {
            final plan = subRes['subscription_plans'] as Map<String, dynamic>?;
            if (plan != null) {
              maxGymsLimit = plan['max_gyms'] as int? ?? 1;
              planName = plan['name']?.toString() ?? 'Trial';
            }
          }
        }

        if (maxGymsLimit > 0 && currentGymsCount >= maxGymsLimit) {
          throw Exception('limit_reached:Your current $planName Plan only allows up to $maxGymsLimit Gym(s). Upgrade to Business Plan to manage multiple gyms.');
        }

        final gymData = await SupabaseService.client
            .from('gyms')
            .insert({
              'name': gymName.trim(),
              'logo_url': gymLogo.trim(),
              'gym_type': gymType.trim(),
              'phone_number': gymPhone.trim(),
              'email': gymEmail.trim(),
              'address': gymAddress.trim(),
              'city': gymCity.trim(),
              'state': gymState.trim(),
              'country': gymCountry.trim(),
              'pin_code': gymPinCode.trim(),
            })
            .select()
            .single();
        gymId = gymData['id'] as String;

        await SupabaseService.client
            .from('user_gym_associations')
            .insert({
              'user_id': uid,
              'gym_id': gymId,
              'role': 'owner',
              'setup_completed': true,
            });

        await _gymRepository.initializeDefaultRoles(gymId);
      }

      // Reload associations
      await loadCurrentProfile();
      
      return _userAssociations.firstWhere((a) => a.gymId == gymId);
    } catch (e) {
      print('createAdditionalGym error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Sign up using Supabase Auth only (No DB queries)
  Future<void> signup(String email, String password) async {
    _setLoading(true);
    try {
      await _authService.signUp(
        email: email,
        password: password,
      );
      _isLoggedIn = true;
      await _storage.setLoggedIn(true);
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Log out securely
  Future<void> logout() async {
    _setLoading(true);
    try {
      await _authService.signOut();
      _isLoggedIn = false;
      _selectedRole = null;
      _currentProfile = null;
      _gymInfo = null;
      _userAssociations = [];
      _activeAssociation = null;
      _staffRecord = null;
      await _storage.clearAll();
      _gymRepository.clearAllData();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Permanently delete current user account and all associated data
  Future<bool> deleteAccount() async {
    _setLoading(true);
    try {
      final uid = _authService.currentUser?.id;
      if (uid != null && SupabaseService.isInitialized) {
        try {
          await SupabaseService.client.rpc('delete_user_account', params: {
            'p_user_id': uid,
          });
        } catch (e) {
          debugPrint('Error invoking delete_user_account RPC: $e');
        }
      }
      await logout();
      return true;
    } catch (e) {
      debugPrint('Error deleting account: $e');
      await logout();
      return true;
    } finally {
      _setLoading(false);
    }
  }

  /// Returns true and logs out if the account was unlinked or deactivated.
  Future<bool> forceLogoutIfUnlinked() async {
    final reason = await getUnlinkBlockReason();
    if (reason == null) return false;
    await logout();
    return true;
  }

  /// Returns logout dialog title/message if account was unlinked or deactivated.
  /// Returns null when access is still valid or if offline/error.
  Future<Map<String, String>?> getUnlinkBlockReason() async {
    if (!isLoggedIn || !SupabaseService.isInitialized) return null;

    final role = selectedRole ?? currentProfile?.role.name ?? _storage.getUserRole() ?? '';
    // Gym owners can NEVER be unlinked by an owner
    if (role == 'owner' || currentProfile?.role == UserRole.owner) {
      return null;
    }

    final user = currentUser;
    if (user == null) return null;

    final gymId = activeAssociation?.gymId ?? gymInfo?['id'];
    if (gymId == null || gymId.toString().isEmpty) return null;

    try {
      final isLinked = await SupabaseService.client.rpc(
        'is_user_linked_to_gym',
        params: {
          'p_user_id': user.id,
          'p_gym_id': gymId,
          'p_role': role == 'member' ? 'member' : 'staff',
        },
      );

      // Only logout if server explicitly confirms the account was unlinked (false)
      if (isLinked == false) {
        return {
          'title': 'Account Unlinked',
          'message': 'Gym Owner unlinked your account.',
        };
      }
    } catch (e) {
      // Network failure, timeout, or server unreachable:
      // MUST NOT logout! Allow user to remain logged in offline.
      print('Unlink check skipped due to network/RPC error: $e');
    }

    return null;
  }

  /// Real Google Sign-In trigger (Native Google Sign-In on Mobile, OAuth on Web).
  /// Returns true only when a Supabase session was created; false if user cancelled.
  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    try {
      // Clean sign out first to support switching roles/users cleanly
      try {
        await SupabaseService.client.auth.signOut();
      } catch (_) {}

      if (kIsWeb) {
        // Standard OAuth flow is highly optimized and recommended for Web
        final String webRedirect = '${Uri.base.origin}/';
        await SupabaseService.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: webRedirect,
          queryParams: {'prompt': 'select_account'},
        );
        return true;
      }

      // Pure Native In-App Google Sign-In for Android & iOS
      try {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          clientId: (!kIsWeb && Platform.isIOS)
              ? '225633708172-75k5t5303ici4s40lat94ps647lbci5e.apps.googleusercontent.com'
              : null,
          serverClientId: '225633708172-7st3l0u84rl22ccnaphap3dfpooai0o6.apps.googleusercontent.com',
          scopes: ['email', 'profile'],
        );

        // Reset previous Google session state to ensure account picker prompt pops up natively in-app
        try {
          await googleSignIn.signOut();
        } catch (_) {}

        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return false;
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final String? idToken = googleAuth.idToken;
        final String? accessToken = googleAuth.accessToken;

        if (idToken != null) {
          try {
            await SupabaseService.client.auth.signInWithIdToken(
              provider: OAuthProvider.google,
              idToken: idToken,
            );
          } catch (tokenErr) {
            print('signInWithIdToken with idToken only failed: $tokenErr. Retrying with accessToken...');
            await SupabaseService.client.auth.signInWithIdToken(
              provider: OAuthProvider.google,
              idToken: idToken,
              accessToken: accessToken,
            );
          }

          await loadCurrentProfile();
          return SupabaseService.client.auth.currentSession != null || _authService.currentUser != null;
        }
      } catch (nativeErr) {
        print('Native Google Sign-In error: $nativeErr');
        final errStr = nativeErr.toString();
        // User cancelled — silently return false
        if (errStr.contains('sign_in_canceled') || errStr.contains('12501')) {
          return false;
        }

        throw Exception('Google Sign-in failed: $errStr');
      }

      return false;
    } on AuthException catch (ae) {
      print('signInWithGoogle AuthException: $ae');
      throw Exception('Google Sign-in failed (400): ${ae.message}');
    } catch (e) {
      print('signInWithGoogle native error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Completes the first-time setup flow after authentication
  Future<void> completeFirstTimeSetup({
    required UserRole role,
    String? gymName,
    String? gymCode,
    required String fullName,
  }) async {
    _setLoading(true);
    try {
      final profile = await _authService.completeSetup(
        role: role,
        gymName: gymName,
        gymCode: gymCode,
        fullName: fullName,
      );

      _currentProfile = profile;
      _selectedRole = profile.role.name;
      _isLoggedIn = true;

      // Cache locally
      await _storage.setLoggedIn(true);
      await _storage.setUserRole(_selectedRole!);

      if (profile.gymId != null) {
        try {
          final gymData = await SupabaseService.client
              .from('gyms')
              .select()
              .eq('id', profile.gymId!)
              .single();

          final info = {
            'id': gymData['id'],
            'name': gymData['name'],
            'gym_code': gymData['gym_code'],
            'owner': profile.email,
            'status': gymData['status'] ?? 'active',
            'is_locked': gymData['is_locked'] ?? false,
          };
          _gymInfo = info;
          await _storage.setGymInfo(info);
        } catch (e) {
          final info = {
            'id': 'mock_gym_123',
            'name': gymName ?? 'GYMOS',
            'gym_code': gymCode ?? 'MOCK1234',
            'owner': profile.email,
          };
          _gymInfo = info;
          await _storage.setGymInfo(info);
        }
      }
      await fetchSubscriptionStatus();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Set the role of the user (e.g. from splash screen check)
  void setRole(String role) {
    _selectedRole = role;
    _storage.setUserRole(role);
    notifyListeners();
  }

  /// Sets gym info and caches it
  Future<void> setGymInfo(Map<String, dynamic> info) async {
    _gymInfo = info;
    await _storage.setGymInfo(info);
    final logoUrl = info['logo'] ?? info['logo_url'];
    if (logoUrl != null && logoUrl.isNotEmpty) {
      cacheImageLocally(logoUrl, 'gym_logo_${info['id']}');
    }
    notifyListeners();
  }

  /// Syncs user profile state on boot
  Future<void> loadCurrentProfile() async {
    final authUser = _authService.currentUser;
    var profile = await _authService.getVerifiedProfile();
    
    // Fallback for offline/mock mode
    if (profile == null && _storage.isLoggedIn()) {
      final roleStr = _storage.getUserRole() ?? 'owner';
      final role = roleStr == 'owner' 
          ? UserRole.owner 
          : (roleStr == 'staff' ? UserRole.staff : UserRole.member);
      
      final savedGymInfo = _storage.getGymInfo();
      profile = UserProfile(
        id: authUser?.id ?? 'mock_user_123',
        email: authUser?.email ?? savedGymInfo?['email'] ?? 'owner@gymos.com',
        role: role,
        gymId: savedGymInfo != null ? (savedGymInfo['id'] ?? 'mock_gym_123') : null,
        setupCompleted: savedGymInfo != null,
      );
    } else if (profile == null && authUser != null) {
      final roleStr = _selectedRole ?? _storage.getUserRole() ?? 'owner';
      final role = roleStr == 'owner' 
          ? UserRole.owner 
          : (roleStr == 'staff' ? UserRole.staff : UserRole.member);

      profile = UserProfile(
        id: authUser.id,
        email: authUser.email ?? '',
        fullName: authUser.userMetadata?['full_name'] ?? authUser.userMetadata?['name'] ?? '',
        photoUrl: authUser.userMetadata?['avatar_url'] ?? authUser.userMetadata?['picture'],
        role: role,
        gymId: null,
        setupCompleted: false,
      );
    }

    _currentProfile = profile;
    if (profile?.photoUrl != null && profile!.photoUrl!.isNotEmpty) {
      cacheImageLocally(profile.photoUrl, 'user_avatar');
    }
    _staffRecord = null;

    if (profile != null || authUser != null) {
      _isLoggedIn = true;
      await _storage.setLoggedIn(true);

      final uid = profile?.id ?? authUser?.id;
      if (uid != null) {
        // Fetch associations
        final allAssociations = await _authService.getUserGymAssociations(uid);
        if (allAssociations != null) {
          _userAssociations = allAssociations;
        }
      }

      if (_userAssociations.isNotEmpty) {
        final savedRole = _storage.getUserRole();
        final savedGym = _storage.getGymInfo();
        
        UserGymAssociation? matchedAssoc;
        if (savedGym != null && savedGym['id'] != null) {
          for (var a in _userAssociations) {
            if (a.gymId == savedGym['id'] && a.role.name == savedRole) {
              matchedAssoc = a;
              break;
            }
          }
        }
        
        final assoc = matchedAssoc ?? _userAssociations.first;
        _activeAssociation = assoc;
        _selectedRole = assoc.role.name;
        final activeProf = profile ?? UserProfile(
          id: uid!,
          email: authUser?.email ?? '',
          role: assoc.role,
          gymId: assoc.gymId,
          setupCompleted: assoc.setupCompleted,
        );
        _currentProfile = activeProf.copyWith(
          role: assoc.role,
          gymId: assoc.gymId,
          setupCompleted: assoc.setupCompleted,
        );
        await _storage.setUserRole(_selectedRole!);

        if (_currentProfile?.role == UserRole.staff) {
          try {
            final res = await SupabaseService.client
                .from('staff')
                .select()
                .eq('user_id', activeProf.id)
                .eq('gym_id', assoc.gymId)
                .maybeSingle();
            if (res != null) {
              _staffRecord = Staff.fromJson(res);
            } else {
              // Staff was unlinked — remove stale association for this gym
              _userAssociations = _userAssociations
                  .where((a) => !(a.gymId == assoc.gymId && a.role == UserRole.staff))
                  .toList();
              _staffRecord = null;
              if (_userAssociations.isEmpty) {
                _activeAssociation = null;
                _gymInfo = null;
                await _storage.remove(LocalStorageService.keyUserGymInfo);
              }
            }
          } catch (e) {
            print('Error loading staff record in loadCurrentProfile: $e');
          }
        }

        // Load Gym Details
        try {
          final gymData = await SupabaseService.client
              .from('gyms')
              .select()
              .eq('id', assoc.gymId)
              .maybeSingle();

          if (gymData != null) {
            final info = {
              'id': gymData['id'],
              'name': gymData['name'],
              'logo': gymData['logo_url'] ?? '',
              'logo_url': gymData['logo_url'] ?? '',
              'gym_code': gymData['gym_code'],
              'owner': activeProf.email,
              'email': gymData['email'] ?? activeProf.email,
              'phone': gymData['phone_number'] ?? '',
              'address': gymData['address'] ?? '',
              'city': gymData['city'] ?? '',
              'state': gymData['state'] ?? '',
              'country': gymData['country'] ?? '',
              'pin_code': gymData['pin_code'] ?? '',
              'gym_type': gymData['gym_type'] ?? '',
              'status': gymData['status'] ?? 'active',
              'is_locked': gymData['is_locked'] ?? false,
              'custom_branding_allowed': gymData['custom_branding_allowed'] ?? false,
              'plan': gymData['plan'] ?? 'free_trial',
            };
            _gymInfo = info;
            await _storage.setGymInfo(info);

            // Fetch and cache branding status from RPC
            try {
              final brandingRes = await SupabaseService.client
                  .rpc('check_custom_branding_status', params: {'p_gym_id': assoc.gymId})
                  .maybeSingle();

              if (brandingRes != null) {
                final bool isAllowed = brandingRes['is_allowed'] == true;
                final String gName = brandingRes['gym_name'] ?? gymData['name'] ?? 'GYMOS';
                final String gLogo = brandingRes['gym_logo'] ?? gymData['logo_url'] ?? '';

                await _storage.setBrandingEnabled(isAllowed);
                await _storage.setBrandingName(gName);
                await _storage.setBrandingLogoUrl(gLogo);

                if (isAllowed && gLogo.isNotEmpty) {
                  // Cache image locally in background
                  cacheImageLocally(gLogo, 'custom_gym_logo');
                } else if (!isAllowed) {
                  await _storage.remove('cached_img_custom_gym_logo');
                }
              }
            } catch (e) {
              print('Error checking custom branding status in loadCurrentProfile: $e');
            }
          }
        } catch (_) {
          final info = _storage.getGymInfo() ?? {
            'id': assoc.gymId,
            'name': assoc.gymName ?? 'GYMOS',
            'gym_code': assoc.gymCode ?? 'MOCK1234',
            'owner': activeProf.email,
          };
          _gymInfo = info;
          await _storage.setGymInfo(info);
        }

        // Fetch unread notifications count from Supabase for current role
        try {
          if (SupabaseService.isInitialized) {
            final res = await SupabaseService.client
                .from('notifications')
                .select('id, target_role, user_id')
                .eq('gym_id', assoc.gymId)
                .eq('is_read', false);
            
            final role = (_selectedRole ?? _storage.getUserRole() ?? '').toLowerCase();
            final bool isOwner = role == 'owner' || role == 'superadmin' || role == 'admin';
            final bool isStaff = role == 'staff' || role == 'receptionist' || role == 'trainer';
            final staffId = _staffRecord?.id;
            final authUid = currentUser?.id;
            final memberId = _storage.getString('member_id');

            final matching = (res as List).where((n) {
              final targetRole = (n['target_role']?.toString() ?? '').toLowerCase();
              final notifUserId = n['user_id']?.toString();
              if (isOwner) {
                return targetRole == 'owner' || targetRole == 'all' || targetRole == 'both' || targetRole.isEmpty;
              } else if (isStaff) {
                if (targetRole == 'owner') return false;
                final isRoleMatch = targetRole == 'staff' || targetRole == 'all' || targetRole == 'both';
                if (!isRoleMatch) return false;
                if (notifUserId != null && notifUserId.isNotEmpty) {
                  return notifUserId == staffId || notifUserId == authUid;
                }
                return true;
              } else {
                if (targetRole == 'owner' || targetRole == 'staff') return false;
                final isRoleMatch = targetRole == 'member' || targetRole == 'all' || targetRole == 'both';
                if (!isRoleMatch) return false;
                if (notifUserId != null && notifUserId.isNotEmpty) {
                  return notifUserId == memberId || notifUserId == authUid;
                }
                return true;
              }
            }).toList();

            _unreadNotificationsCount = matching.length;
          }
        } catch (e) {
          print('Error fetching unread notifications count: $e');
        }
      } else {
        _selectedRole = _storage.getUserRole();
        _activeAssociation = null;
        _gymInfo = null;
        await _storage.remove(LocalStorageService.keyUserGymInfo);
      }
    }
    await fetchSubscriptionStatus();
    notifyListeners();
  }

  /// Complete the premium onboarding setup specifically for Gym Owners
  Future<void> completeOwnerOnboarding({
    required String gymName,
    required String gymLogo,
    required String gymType,
    required String gymPhone,
    required String gymEmail,
    required String gymAddress,
    required String gymCity,
    required String gymState,
    required String gymCountry,
    required String gymPinCode,
    required String ownerFullName,
    required String ownerPhone,
    required String ownerEmail,
    required String ownerPhoto,
    required String ownerDob,
    required String ownerExperience,
  }) async {
    _setLoading(true);
    try {
      final profile = await _authService.completeOwnerSetup(
        gymName: gymName,
        gymLogo: gymLogo,
        gymType: gymType,
        gymPhone: gymPhone,
        gymEmail: gymEmail,
        gymAddress: gymAddress,
        gymCity: gymCity,
        gymState: gymState,
        gymCountry: gymCountry,
        gymPinCode: gymPinCode,
        ownerFullName: ownerFullName,
        ownerPhone: ownerPhone,
        ownerEmail: ownerEmail,
        ownerPhoto: ownerPhoto,
        ownerDob: ownerDob,
        ownerExperience: ownerExperience,
      );

      _currentProfile = profile;
      if (profile.gymId != null) {
        await _gymRepository.initializeDefaultRoles(profile.gymId!);
      }
      _selectedRole = profile.role.name;
      _isLoggedIn = true;

      // Cache locally
      await _storage.setLoggedIn(true);
      await _storage.setUserRole(_selectedRole!);

      // Fetch or create the gym info maps
      Map<String, dynamic> info;
      if (profile.gymId != null && profile.gymId != 'mock_gym_123') {
        try {
          final gymData = await SupabaseService.client
              .from('gyms')
              .select()
              .eq('id', profile.gymId!)
              .single();

          info = {
            'id': gymData['id'],
            'name': gymData['name'],
            'logo': gymData['logo_url'] ?? gymLogo,
            'logo_url': gymData['logo_url'] ?? gymLogo,
            'gym_code': gymData['gym_code'],
            'owner': profile.email,
            'email': gymData['email'] ?? gymEmail,
            'phone': gymData['phone_number'] ?? gymPhone,
            'address': gymData['address'] ?? gymAddress,
            'city': gymData['city'] ?? gymCity,
            'state': gymData['state'] ?? gymState,
            'country': gymData['country'] ?? gymCountry,
            'pin_code': gymData['pin_code'] ?? gymPinCode,
            'gym_type': gymData['gym_type'] ?? gymType,
            'status': gymData['status'] ?? 'active',
            'is_locked': gymData['is_locked'] ?? false,
          };
        } catch (_) {
          info = {
            'id': profile.gymId ?? 'mock_gym_123',
            'name': gymName,
            'logo': gymLogo,
            'logo_url': gymLogo,
            'gym_code': 'MOCK1234',
            'owner': profile.email,
            'email': gymEmail,
            'phone': gymPhone,
            'address': gymAddress,
            'city': gymCity,
            'state': gymState,
            'country': gymCountry,
            'pin_code': gymPinCode,
            'gym_type': gymType,
          };
        }
      } else {
        info = {
          'id': 'mock_gym_123',
          'name': gymName,
          'logo': gymLogo,
          'logo_url': gymLogo,
          'gym_code': 'MOCK1234',
          'owner': profile.email,
          'email': gymEmail,
          'phone': gymPhone,
          'address': gymAddress,
          'city': gymCity,
          'state': gymState,
          'country': gymCountry,
          'pin_code': gymPinCode,
          'gym_type': gymType,
        };
      }
      
      _gymInfo = info;
      await _storage.setGymInfo(info);
      await fetchSubscriptionStatus();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// Submits the invitation code and mobile number to verify.
  /// Returns a Map with success status and any error text.
  Future<Map<String, dynamic>> submitInvitationCode({
    required String code,
    required String mobileNumber,
  }) async {
    _setLoading(true);
    try {
      final user = currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No active login session found.'};
      }

      final result = await _authService.verifyInvitation(
        code: code,
        mobileNumber: mobileNumber,
        userId: user.id,
        email: user.email ?? '',
      );

      if (result['success'] == true) {
        // Refresh local user profile and associations to direct dashboard correctly
        await loadCurrentProfile();
      }
      return result;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchSubscriptionStatus() async {
    final gymId = activeAssociation?.gymId ?? gymInfo?['id'];
    if (gymId == null || !SupabaseService.isInitialized) {
      _isOffline = false;
      _isSubscriptionExpired = false;
      _subscriptionInfo = null;
      notifyListeners();
      return;
    }
    
    try {
      // 1. Direct fetch from subscriptions table
      Map<String, dynamic>? subData;
      try {
        subData = await SupabaseService.client
            .from('subscriptions')
            .select('plan_id, status, trial_start, trial_end, start_date, end_date, created_at')
            .eq('gym_id', gymId)
            .maybeSingle();
      } catch (e) {
        print('Error querying subscriptions table in fetchSubscriptionStatus: $e');
      }

      // 2. Direct fetch from gyms table
      Map<String, dynamic>? gymData;
      try {
        gymData = await SupabaseService.client
            .from('gyms')
            .select('plan, status, expiry_date, trial_end_date, is_locked')
            .eq('id', gymId)
            .maybeSingle();
      } catch (e) {
        print('Error querying gyms table in fetchSubscriptionStatus: $e');
      }

      _isOffline = false;

      if (subData != null || gymData != null) {
        final plan = (subData?['plan_id'] ?? gymData?['plan'] ?? 'free_trial').toString();
        final status = (subData?['status'] ?? gymData?['status'] ?? 'trial').toString();
        
        // Pick the most accurate live expiry date from subscriptions or gyms table
        final rawExpiry = subData?['end_date'] ?? 
            subData?['trial_end'] ?? 
            gymData?['expiry_date'] ?? 
            gymData?['trial_end_date'];
        
        DateTime? expiryDate;
        if (rawExpiry != null) {
          expiryDate = rawExpiry is DateTime ? rawExpiry : DateTime.tryParse(rawExpiry.toString());
        }

        final int daysLeft = expiryDate != null 
            ? expiryDate.difference(DateTime.now()).inDays.clamp(0, 99999)
            : 0;
        final bool isExpired = status.toLowerCase() == 'expired' || 
            (expiryDate != null && expiryDate.isBefore(DateTime.now()));
        final bool isLocked = gymData?['is_locked'] == true;

        final resolvedInfo = {
          'gym_id': gymId,
          'plan': plan,
          'status': status,
          'expiry_date': expiryDate?.toIso8601String() ?? '',
          'days_left': daysLeft,
          'is_expired': isExpired,
          'is_locked': isLocked,
        };

        _subscriptionInfo = resolvedInfo;
        _isSubscriptionExpired = isExpired || isLocked;

        // Keep local gymInfo in sync as well
        if (_gymInfo != null) {
          _gymInfo!['plan'] = plan;
          _gymInfo!['status'] = status;
          if (expiryDate != null) {
            _gymInfo!['expiry_date'] = expiryDate.toIso8601String();
            _gymInfo!['trial_end_date'] = expiryDate.toIso8601String();
          }
          await _storage.setGymInfo(_gymInfo!);
        }
      } else {
        _isSubscriptionExpired = false;
        _subscriptionInfo = null;
      }
      notifyListeners();
    } catch (e) {
      print('Error in fetchSubscriptionStatus: $e');
      final errStr = e.toString();
      if (errStr.contains('SocketException') || errStr.contains('ClientException') || errStr.contains('Failed host lookup') || errStr.contains('connection failed')) {
        _isOffline = true;
        _isSubscriptionExpired = true; // Lock the app when offline as requested
        notifyListeners();
      }
    }
  }

  Future<void> updateCustomBranding({required bool enabled, required String name, required String logoUrl}) async {
    await _storage.setBrandingEnabled(enabled);
    await _storage.setBrandingName(name);
    await _storage.setBrandingLogoUrl(logoUrl);
    if (enabled && logoUrl.isNotEmpty) {
      await cacheImageLocally(logoUrl, 'custom_gym_logo');
    } else {
      await _storage.remove('cached_img_custom_gym_logo');
    }
    // Update local gymInfo as well so changes reflect immediately
    if (_gymInfo != null) {
      _gymInfo!['name'] = name;
      _gymInfo!['logo_url'] = logoUrl;
      _gymInfo!['logo'] = logoUrl;
      await _storage.setGymInfo(_gymInfo!);
    }
    notifyListeners();
  }
}
