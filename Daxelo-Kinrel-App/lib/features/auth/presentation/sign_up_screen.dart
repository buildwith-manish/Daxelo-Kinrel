import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/kinrel_logo.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _passwordStrength(String password) {
    if (password.length < 8) return 'Weak';
    if (password.length < 12 && !RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) return 'Medium';
    return 'Strong';
  }

  String _cleanErrorMessage(String rawMessage) {
    var message = rawMessage;
    message = message.replaceAll('AuthException: ', '');
    message = message.replaceAll('AuthApiException: ', '');

    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('AuthRetryableFetchException') ||
        message.contains('Connection refused') ||
        message.contains('Network is unreachable') ||
        message.contains('No address associated with hostname') ||
        message.contains('Connection timed out') ||
        message.contains('TimeoutException') ||
        message.contains('timed out') ||
        message.contains('Unable to connect') ||
        message.contains('FetchException') ||
        message.contains('Connection reset')) {
      return 'Could not reach server. The server may be waking up — please check your internet connection and try again.';
    } else if (message.contains('No API key found')) {
      return 'Server configuration error. Please contact support.';
    } else if (message.contains('User already registered')) {
      return 'This email is already registered. Try signing in instead.';
    } else if (message.contains('Password should be')) {
      return 'Password is too weak. Use at least 8 characters with numbers and symbols.';
    } else if (message.contains('Invalid email')) {
      return 'Please enter a valid email address.';
    } else if (message.contains('not available') ||
        message.contains('not available. Please restart')) {
      return 'Authentication service is not ready. Please restart the app and try again.';
    } else if (message.length > 150) {
      return 'Sign up failed. Please check your details and try again.';
    }
    return message;
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      context.showSnackBar('Please agree to the Terms of Service', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      final response = await authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
      );

      if (!mounted) return;

      // Check if email confirmation is required
      final user = response.user;
      if (user != null && user.emailConfirmedAt == null) {
        // Email confirmation required — show message and go to sign-in
        context.showSnackBar(
          'Account created! Please check your email to verify your account, then sign in.',
        );
        context.go('/sign-in');
      } else {
        // Auto-confirmed or already confirmed — go to home
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        context.showSnackBar(_cleanErrorMessage(e.toString()), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final passwordStrength = _passwordStrength(_passwordController.text);
    final strengthColor = passwordStrength == 'Strong'
      ? KinrelColors.success
      : passwordStrength == 'Medium'
        ? KinrelColors.warning
        : KinrelColors.error;
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [KinrelColors.darkBackground, KinrelColors.darkCard],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Center(
                      child: KinrelLogo(
                        size: LogoSize.md,
                        layout: LogoLayout.horizontal,
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      'Create Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Name
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Name is required' : null,
                    ),

                    const SizedBox(height: 16),

                    // Email
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 8) return 'Password must be at least 8 characters';
                        return null;
                      },
                    ),

                    if (_passwordController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Strength: ',
                            style: TextStyle(
                              color: KinrelColors.textDim,
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            passwordStrength ?? '',
                            style: TextStyle(
                              color: strengthColor,
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Confirm Password
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please confirm your password';
                        if (v != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Terms
                    Row(
                      children: [
                        Checkbox(
                          value: _agreedToTerms,
                          onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                          activeColor: KinrelColors.orange,
                        ),
                        Expanded(
                          child: Text(
                            'I agree to the Terms of Service and Privacy Policy',
                            style: TextStyle(
                              color: KinrelColors.textSilver,
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Create Account button
                    FilledButton(
                      onPressed: _isLoading ? null : _signUp,
                      style: FilledButton.styleFrom(
                        backgroundColor: KinrelColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Creating account...',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Create Account',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                    ),

                    const SizedBox(height: 24),

                    // Sign In link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: TextStyle(
                            color: KinrelColors.textSilver,
                            fontFamily: KinrelTypography.bodyFont,
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/sign-in'),
                          child: Text(
                            'Sign In',
                            style: TextStyle(
                              color: KinrelColors.orange,
                              fontFamily: KinrelTypography.displayFont,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
