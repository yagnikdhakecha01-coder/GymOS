import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/user_profile.dart';
import '../models/association_model.dart';

class AuthService {
  bool get isSupabaseActive {
    try {
      return SupabaseService.isInitialized;
    } catch (_) {
      return false;
    }
  }

  SupabaseClient? get _client => isSupabaseActive ? SupabaseService.client : null;


  /// Sign up with email + password
  Future<User?> signUp({required String email, required String password}) async {
    if (_client != null) {
      final response = await _client!.auth.signUp(
        email: email,
        password: password,
      );
      return response.user;
    }
    throw Exception('Database offline. Cannot register account.');
  }

  /// Sign in with email + password
  Future<User?> signIn({required String email, required String password}) async {
    if (_client != null) {
      final response = await _client!.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user;
    }
    throw Exception('Database offline. Cannot login.');
  }

  /// Sign out
  Future<void> signOut() async {
    if (_client != null) {
      try {
        await _client!.auth.signOut();
      } catch (_) {}
    }
  }

  /// Check if session exists
  Session? get currentSession {
    if (_client != null) {
      try {
        return _client!.auth.currentSession;
      } catch (_) {}
    }
    return null;
  }

  /// Get current user
  User? get currentUser {
    if (_client != null) {
      try {
        return _client!.auth.currentUser;
      } catch (_) {}
    }
    return null;
  }

  /// Verifies if a gym exists with the given gym code.
  /// Returns the Gym ID if exists, otherwise returns null.
  Future<String?> verifyGymCode(String code) async {
    if (_client != null) {
      try {
        final response = await _client!
            .from('gyms')
            .select('id')
            .eq('gym_code', code)
            .maybeSingle();
        
        return response?['id'] as String?;
      } catch (e) {
        print('Verify gym code error: $e');
      }
    }
    return null;
  }

  /// Fetches the profile of the current authenticated user directly from the database.
  Future<UserProfile?> getVerifiedProfile() async {
    if (_client != null) {
      try {
        final current = currentUser;
        if (current == null) return null;

        final profileData = await _client!
            .from('profiles')
            .select()
            .eq('id', current.id)
            .maybeSingle();

        if (profileData != null) {
          return UserProfile.fromJson(profileData);
        }
      } catch (e) {
        print('Fetch profile error: $e');
      }
    }
    // Return null on first-time setup check so they proceed to the Setup screen
    return null;
  }

  /// Fetches all gym associations for a specific user ID.
  Future<List<UserGymAssociation>?> getUserGymAssociations(String userId) async {
    if (_client != null) {
      try {
        final List<dynamic> data = await _client!
            .from('user_gym_associations')
            .select('*, gyms(*)')
            .eq('user_id', userId);
        return data.map((json) => UserGymAssociation.fromJson(json)).toList();
      } catch (e) {
        print('Fetch associations error: $e');
        return null;
      }
    }
    return null;
  }

  /// Creates the profile for a new user during the setup flow.
  Future<UserProfile> completeSetup({
    required UserRole role,
    String? gymName,
    String? gymCode,
    required String fullName,
  }) async {
    final email = currentUser?.email ?? 'user@gymos.com';

    if (_client != null) {
      try {
        String? gymId;

        if (role == UserRole.owner) {
          if (gymName != null && gymName.trim().isNotEmpty) {
            final gymData = await _client!
                .from('gyms')
                .insert({'name': gymName.trim()})
                .select()
                .single();
            gymId = gymData['id'] as String;
          }
        } else {
          if (gymCode != null && gymCode.trim().isNotEmpty) {
            gymId = await verifyGymCode(gymCode.trim());
          }
        }

        final profileData = await _client!
            .from('profiles')
            .insert({
              'id': currentUser?.id ?? 'mock_user_123',
              'email': email,
              'role': role.name,
              'gym_id': gymId ?? 'mock_gym_123',
            })
            .select()
            .single();

        return UserProfile.fromJson(profileData);
      } catch (e) {
        print('Database table write skipped or failed: $e. Using local model creation.');
      }
    }

    // Database fallback: immediately return a successful in-memory profile
    return UserProfile(
      id: currentUser?.id ?? 'mock_user_123',
      email: email,
      role: role,
      gymId: 'mock_gym_123',
    );
  }

  /// Completes the onboarding setup specifically for a Gym Owner, creating the gym and owner profile records.
  Future<UserProfile> completeOwnerSetup({
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
    final uid = currentUser?.id ?? 'mock_user_123';
    final email = currentUser?.email ?? ownerEmail;

    if (_client != null) {
      try {
        // 1. Create the Gym record with all gym info fields
        final gymData = await _client!
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

        final String gymId = gymData['id'] as String;

        // 2. Insert or update user profile with setup completed and owner fields
        final profileData = await _client!
            .from('profiles')
            .upsert({
              'id': uid,
              'email': email,
              'full_name': ownerFullName.trim(),
              'phone_number': ownerPhone.trim(),
              'photo_url': ownerPhoto.trim(),
              'dob': ownerDob.trim(),
              'experience': ownerExperience.trim(),
            })
            .select()
            .single();

        // 3. Create Gym Owner Association
        await _client!
            .from('user_gym_associations')
            .insert({
              'user_id': uid,
              'gym_id': gymId,
              'role': 'owner',
              'setup_completed': true,
            });

        return UserProfile.fromJson(profileData).copyWith(
          role: UserRole.owner,
          gymId: gymId,
          setupCompleted: true,
        );
      } catch (e) {
        print('Database completeOwnerSetup failed: $e.');
        rethrow;
      }
    }

    // Database fallback: immediately return a successful in-memory profile
    return UserProfile(
      id: uid,
      email: email,
      role: UserRole.owner,
      gymId: 'mock_gym_123',
      setupCompleted: true,
      fullName: ownerFullName,
      phoneNumber: ownerPhone,
      photoUrl: ownerPhoto,
      dob: ownerDob,
      experience: ownerExperience,
    );
  }

  /// Verifies the invitation code and mobile number.
  /// If valid, creates the profile association and registers the user as member/staff.
  Future<Map<String, dynamic>> verifyInvitation({
    required String code,
    required String mobileNumber,
    required String userId,
    required String email,
  }) async {
    if (_client == null) {
      return {'success': true, 'gymId': 'mock_gym_123', 'role': 'member'};
    }

    try {
      final res = await _client!.rpc(
        'redeem_gym_invitation',
        params: {
          'p_code': code.trim(),
          'p_mobile': mobileNumber.trim(),
        },
      );

      final Map<String, dynamic> data = res is Map<String, dynamic>
          ? res
          : Map<String, dynamic>.from(res as Map);

      if (data['success'] != true) {
        return {'success': false, 'error': data['error'] ?? 'Failed to verify invitation.'};
      }

      // Upsert user profile details
      await _client!
          .from('profiles')
          .upsert({
            'id': userId,
            'email': email,
            if ((data['full_name'] ?? '').toString().isNotEmpty)
              'full_name': data['full_name'],
            'phone_number': mobileNumber,
          });

      return {
        'success': true,
        'gymId': data['gym_id'],
        'role': data['role'],
        'fullName': data['full_name'] ?? '',
      };
    } catch (e) {
      debugPrint('verifyInvitation error: $e');
      return {'success': false, 'error': 'Unable to verify invitation. Please try again.'};
    }
  }
}
