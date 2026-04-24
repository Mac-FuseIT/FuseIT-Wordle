import 'package:flutter/material.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  final Function(int userId, String name) onLogin;
  final Function(Map<String, dynamic>?)? onThemeLoaded;
  final Color accentColor;
  const LoginScreen({super.key, required this.onLogin, this.onThemeLoaded, this.accentColor = const Color(0xFF6AAA64)});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginMode { login, register, forgot }

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _LoginMode _mode = _LoginMode.login;
  bool _loading = false;
  String? _error;
  String? _info;

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email');
      return;
    }
    setState(() { _loading = true; _error = null; _info = null; });

    try {
      if (_mode == _LoginMode.register) {
        final res = await ApiService.register(email);
        if (res['error'] != null) {
          setState(() { _error = res['error']; _loading = false; });
        } else {
          final pw = res['password'];
          setState(() {
            _info = pw != null
                ? '${res['message']}\n\nYour password: $pw'
                : res['message'];
            _mode = _LoginMode.login;
            _loading = false;
          });
        }
      } else if (_mode == _LoginMode.forgot) {
        final res = await ApiService.forgotPassword(email);
        if (res['error'] != null) {
          setState(() { _error = res['error']; _loading = false; });
        } else {
          final pw = res['password'];
          setState(() {
            _info = pw != null
                ? '${res['message']}\n\nYour new password: $pw'
                : res['message'];
            _mode = _LoginMode.login;
            _loading = false;
          });
        }
      } else {
        final password = _passwordController.text.trim();
        if (password.isEmpty) {
          setState(() { _error = 'Enter your password'; _loading = false; });
          return;
        }
        final res = await ApiService.login(email, password);
        if (res['error'] != null) {
          setState(() { _error = res['error']; _loading = false; });
        } else {
          widget.onThemeLoaded?.call(res['theme'] as Map<String, dynamic>?);
          await widget.onLogin(res['userId'] as int, res['name'] as String);
        }
      }
    } catch (e) {
      setState(() { _error = 'Something went wrong. Try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fuse Arcade',
              style: TextStyle(
                fontFamily: 'Trebuchet MS',
                color: Colors.white,
                fontSize: 62,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: widget.accentColor, blurRadius: 12),
                  Shadow(color: widget.accentColor, blurRadius: 24),
                ],
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Daily games for FuseIT',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 40),

            // Email
            SizedBox(
              width: 320,
              child: TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'you@gofuseit.com',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _mode == _LoginMode.login ? null : _submit(),
              ),
            ),

            // Password (only for login mode)
            if (_mode == _LoginMode.login) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],

            if (_info != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 320,
                child: Text(_info!, style: TextStyle(color: widget.accentColor, fontSize: 13), textAlign: TextAlign.center),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 320,
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: 320,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _mode == _LoginMode.login ? 'Login' : _mode == _LoginMode.register ? 'Register' : 'Reset Password',
                        style: const TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // Toggle links
            if (_mode == _LoginMode.login) ...[
              TextButton(
                onPressed: () => setState(() { _mode = _LoginMode.forgot; _error = null; _info = null; }),
                child: const Text('Forgot password?', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              TextButton(
                onPressed: () => setState(() { _mode = _LoginMode.register; _error = null; _info = null; }),
                child: Text("Don't have an account? Register", style: TextStyle(color: widget.accentColor, fontSize: 13)),
              ),
            ] else ...[
              TextButton(
                onPressed: () => setState(() { _mode = _LoginMode.login; _error = null; _info = null; }),
                child: const Text('Back to login', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
