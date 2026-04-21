import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  final Function(int userId, String name) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final name = _controller.text.trim();
    if (name.isEmpty || name.length > 20) {
      setState(() => _error = 'Enter a name (1-20 characters)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.onLogin(0, name); // userId resolved in parent
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WordIT',
              style: TextStyle(
                fontFamily: 'Trebuchet MS',
                color: Colors.white,
                fontSize: 62,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Color(0xFF6AAA64), blurRadius: 12),
                  Shadow(color: Color(0xFF6AAA64), blurRadius: 24),
                ],
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'A daily word game with varying word lengths (4-8)',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 5),
            const Text(
              'The winner at the end of the Month, gets double their Salary 😏 (Pending Approval)',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _login(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: 300,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6AAA64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Play', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
