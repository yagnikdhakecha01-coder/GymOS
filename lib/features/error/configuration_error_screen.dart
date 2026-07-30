import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/role_selection_screen.dart';
import '../../core/navigation/app_router.dart';

class ConfigurationErrorScreen extends StatefulWidget {
  const ConfigurationErrorScreen({super.key});

  @override
  State<ConfigurationErrorScreen> createState() => _ConfigurationErrorScreenState();
}

class _ConfigurationErrorScreenState extends State<ConfigurationErrorScreen> {
  bool _isChecking = false;

  Future<void> _handleRetry() async {
    setState(() {
      _isChecking = true;
    });

    // Wait a brief moment for dynamic visual feedback
    await Future.delayed(const Duration(milliseconds: 800));

    // Try initializing again
    await SupabaseService.initialize();

    setState(() {
      _isChecking = false;
    });

    if (SupabaseService.isConfigured && !SupabaseService.hasError) {
      if (mounted) {
        // Successfully connected, redirect to role selection
        Navigator.pushReplacement(
          context,
          AppRouter.scaleRoute(const RoleSelectionScreen()),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  'Configuration check failed. Keys are still missing.',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  String _getErrorDescription(String? error) {
    if (error == null || error.isEmpty) {
      return 'This application is configured for secure deployment. Please specify environment variables to launch the system.';
    }
    switch (error) {
      case 'Missing .env file':
        return 'The .env file could not be found in the root directory. Please copy .env.example to .env and configure your keys.';
      case 'Missing SUPABASE_URL':
        return 'The SUPABASE_URL environment variable is missing or empty. Please check your .env file.';
      case 'Missing SUPABASE_ANON_KEY':
        return 'The SUPABASE_ANON_KEY environment variable is missing or empty. Please check your .env file.';
      case 'Invalid URL':
        return 'The SUPABASE_URL provided is not a valid HTTPS URL. Please check the spelling and format.';
      case 'Invalid API Key':
        return 'The SUPABASE_ANON_KEY provided is invalid or has expired. Please check your Supabase API keys.';
      case 'Network Error':
        return 'Could not establish connection to Supabase. Please check your network connection and ensure the host is reachable.';
      case 'Flutter configuration issue':
        return 'An error occurred within the Flutter configuration context. Check your console logs for details.';
      default:
        return 'An unexpected initialization error occurred: $error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Slate
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glassmorphic warning card
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.8), // Translucent slate
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.redAccent.withOpacity(0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.08),
                        blurRadius: 40,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Warning icon with ambient glow
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_person_rounded,
                          color: Colors.redAccent,
                          size: 44,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        SupabaseService.errorMessage ?? 'Supabase is not configured.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _getErrorDescription(SupabaseService.errorMessage),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8), // slate-400
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Color(0xFF334155), height: 1),
                      const SizedBox(height: 24),
                      
                      // Instructions list
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'HOW TO CONFIGURE:',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF38BDF8), // Light blue accent
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInstructionItem(
                        '1',
                        'Create a new file named .env in your project root folder.',
                      ),
                      _buildInstructionItem(
                        '2',
                        'Add your Supabase details into the .env file:\nSUPABASE_URL="your-url"\nSUPABASE_ANON_KEY="your-key"',
                      ),
                      _buildInstructionItem(
                        '3',
                        'Run the application passing the environment variables file:',
                      ),
                      
                      // Command box
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8, left: 32),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: SelectableText(
                          'flutter run --dart-define-from-file=.env',
                          style: GoogleFonts.firaCode(
                            fontSize: 11,
                            color: const Color(0xFFF1F5F9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Retry Button
                SizedBox(
                  width: 200,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _handleRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      disabledBackgroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF94A3B8)),
                            ),
                          )
                        : Text(
                            'Retry Connection',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionItem(String index, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF334155),
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFFCBD5E1),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
