import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Minimal email/password sign-in and sign-up. No payment info, no
/// subscription tier selection — every feature is available to every
/// account.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSignUp = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  bool get _showAppleButton =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _runAuthAction(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await action();
    } catch (e) {
      if (e is FirebaseAuthException) {
        final message = e.message ?? e.code;
        final hint = e.code == 'invalid-api-key'
            ? 'The Firebase API key in your project config is invalid or does not belong to this project.'
            : e.code == 'network-request-failed'
                ? 'Network error. Check your connection and try again.'
                : e.code == 'user-not-found' || e.code == 'wrong-password'
                    ? 'The email or password is incorrect.'
                    : e.code == 'email-already-in-use'
                        ? 'That email is already registered.'
                        : e.code == 'aborted-by-user'
                            ? 'Sign in was canceled.'
                            : 'Firebase authentication failed.';
        debugPrint('FirebaseAuthException code=${e.code} message=${e.message}');
        setState(() => _error = '$message\n\n$hint');
      } else if (e is FirebaseException) {
        setState(() => _error = e.message ?? e.code);
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    await _runAuthAction(() async {
      final appState = context.read<AppState>();
      if (_isSignUp) {
        await appState.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );
      } else {
        await appState.auth.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    });
  }

  Future<void> _continueWithGoogle() async {
    await _runAuthAction(() async {
      await context.read<AppState>().auth.signInWithGoogle();
    });
  }

  Future<void> _continueWithApple() async {
    await _runAuthAction(() async {
      await context.read<AppState>().auth.signInWithApple();
    });
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: _loading ? null : _continueWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDADCE0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/google_g.svg',
              width: 18,
              height: 18,
            ),
            const SizedBox(width: 10),
            const Text(
              'Continue with Google',
              style: TextStyle(
                color: Color(0xFF1F1F1F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppleButton() {
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: _loading ? null : _continueWithApple,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(Icons.apple, size: 20),
        label: const Text(
          'Continue with Apple',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.family_restroom, size: 64),
              const SizedBox(height: 12),
              Text(_isSignUp ? 'Create your account' : 'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text('Every feature, free. No subscription.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              if (_isSignUp)
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                ),
              if (_isSignUp) const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator())
                    : Text(_isSignUp ? 'Sign up' : 'Sign in'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'or continue with',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              _buildGoogleButton(),
              if (_showAppleButton) ...[
                const SizedBox(height: 10),
                _buildAppleButton(),
              ],
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(_isSignUp
                    ? 'Already have an account? Sign in'
                    : "Don't have an account? Sign up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
