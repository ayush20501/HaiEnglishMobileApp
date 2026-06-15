import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:haienglish/services/api_service.dart';
import 'package:haienglish/models/user.dart';

class AuthScreen extends StatefulWidget {
  final Function(User) onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String _authMode = 'login';
  bool _isLoading = false;
  bool _showPassword = false;
  bool _showNewPassword = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();

  String _appLogoUrl = 'https://i.ibb.co/KcpRPJD4/HAI-logo.png';

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    final logo = await ApiService.getAppLogo();
    if (logo != null && mounted) {
      setState(() {
        _appLogoUrl = logo;
      });
    }
  }

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Email and password are required');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_authMode == 'login') {
        final user = await ApiService.login(email, password);
        widget.onLoginSuccess(user);
      } else {
        if (name.isEmpty) {
          _showError('Full name is required');
          setState(() => _isLoading = false);
          return;
        }
        await ApiService.register(email, password, name);
        _showSuccess('Registration completed. Please log in.');
        setState(() {
          _authMode = 'login';
        });
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Email is required');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.forgotPassword(email);
      _showSuccess('OTP sent to your email.');
      setState(() {
        _authMode = 'forgot-otp';
      });
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    if (email.isEmpty || otp.isEmpty || newPassword.isEmpty) {
      _showError('All fields are required');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ApiService.resetPassword(email, otp, newPassword);
      _showSuccess('Password has been reset successfully. Please log in.');
      setState(() {
        _authMode = 'login';
        _passwordController.clear();
        _otpController.clear();
        _newPasswordController.clear();
      });
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Image.network(
                      _appLogoUrl,
                      width: size.width * 0.32,
                      height: size.width * 0.32,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: size.width * 0.32,
                          height: size.width * 0.32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'HaiEnglish',
                      style: GoogleFonts.poppins(
                        fontSize: size.width * 0.1,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF004AAD),
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Online Language Learning Platform',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  color: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _getCardTitle(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_authMode == 'forgot-email') ...[
                          _buildTextField(
                            label: 'Email Address',
                            hint: 'you@example.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          _buildPrimaryButton(
                            text: 'Send OTP',
                            onPressed: _handleSendOtp,
                          ),
                        ] else if (_authMode == 'forgot-otp') ...[
                          _buildTextField(
                            label: 'One-Time Password (OTP)',
                            hint: '123456',
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          _buildPasswordField(
                            label: 'New Password',
                            hint: '••••••••',
                            controller: _newPasswordController,
                            obscureText: !_showNewPassword,
                            toggleObscure: () => setState(() => _showNewPassword = !_showNewPassword),
                          ),
                          const SizedBox(height: 16),
                          _buildPrimaryButton(
                            text: 'Reset Password',
                            onPressed: _handleResetPassword,
                          ),
                        ] else ...[
                          if (_authMode == 'register') ...[
                            _buildTextField(
                              label: 'Full Name',
                              hint: 'John Doe',
                              controller: _nameController,
                            ),
                            const SizedBox(height: 16),
                          ],
                          _buildTextField(
                            label: 'Email Address',
                            hint: 'you@example.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          _buildPasswordField(
                            label: 'Password',
                            hint: '••••••••',
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            toggleObscure: () => setState(() => _showPassword = !_showPassword),
                          ),
                          if (_authMode == 'login') ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => setState(() => _authMode = 'forgot-email'),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF004AAD),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _buildPrimaryButton(
                            text: _authMode == 'login' ? 'Sign In' : 'Sign Up',
                            onPressed: _handleAuth,
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _toggleAuthMode,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _getToggleText(),
                              maxLines: 1,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF004AAD),
                              ),
                            ),
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
      ),
    );
  }

  String _getCardTitle() {
    if (_authMode == 'forgot-email') return 'Forgot Password';
    if (_authMode == 'forgot-otp') return 'Reset Password';
    return _authMode == 'login' ? 'Welcome Back' : 'Join HaiEnglish';
  }

  String _getToggleText() {
    if (_authMode == 'forgot-email' || _authMode == 'forgot-otp') return '← Back to Sign In';
    return _authMode == 'login' ? "Don't have an account? Sign Up" : 'Already have an account? Sign In';
  }

  void _toggleAuthMode() {
    setState(() {
      if (_authMode == 'forgot-email' || _authMode == 'forgot-otp') {
        _authMode = 'login';
      } else {
        _authMode = _authMode == 'login' ? 'register' : 'login';
      }
    });
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(fontSize: 15, color: const Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: const Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF004AAD), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool obscureText,
    required VoidCallback toggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: GoogleFonts.poppins(fontSize: 15, color: const Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: const Color(0xFF9CA3AF)),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF6B7280),
              ),
              onPressed: toggleObscure,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF004AAD), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF004AAD),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
          shadowColor: const Color(0xFF004AAD).withAlpha(102),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }
}
