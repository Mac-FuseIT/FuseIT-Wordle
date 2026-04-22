import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String currentName;
  final AppTheme currentTheme;
  final VoidCallback onBack;
  final Function(String) onNameUpdated;
  final Function(AppTheme) onThemeUpdated;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.currentName,
    required this.currentTheme,
    required this.onBack,
    required this.onNameUpdated,
    required this.onThemeUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nicknameController;
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;
  late AppTheme _selectedTheme;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.currentName);
    _selectedTheme = widget.currentTheme;
  }

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty || nickname.length > 20) {
      setState(() => _error = 'Nickname must be 1-20 characters');
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final res = await ApiService.updateProfile(widget.userId, nickname: nickname);
      if (res['error'] != null) {
        setState(() { _error = res['error']; _loading = false; });
      } else {
        widget.onNameUpdated(res['name']);
        setState(() { _success = 'Nickname updated!'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Failed to update. Try again.'; _loading = false; });
    }
  }

  Future<void> _savePassword() async {
    final pw = _passwordController.text.trim();
    if (pw.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters');
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final res = await ApiService.updateProfile(widget.userId, newPassword: pw);
      if (res['error'] != null) {
        setState(() { _error = res['error']; _loading = false; });
      } else {
        _passwordController.clear();
        setState(() { _success = 'Password updated!'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Failed to update. Try again.'; _loading = false; });
    }
  }

  Future<void> _saveTheme(AppTheme theme) async {
    setState(() { _selectedTheme = theme; _loading = true; _error = null; _success = null; });
    try {
      final res = await ApiService.updateProfile(widget.userId, theme: theme.toJson());
      if (res['error'] != null) {
        setState(() { _error = res['error']; _loading = false; });
      } else {
        widget.onThemeUpdated(theme);
        setState(() { _success = 'Theme updated!'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Failed to update. Try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
              const Text('Edit Profile', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nickname
                    const Text('Nickname', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nicknameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter nickname',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _saveNickname(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveNickname,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.currentTheme.correct,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Save Nickname', style: TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Divider(color: Color(0xFF3A3A3C)),
                    const SizedBox(height: 16),

                    // Password
                    const Text('Change Password', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.white),
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'New password',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _savePassword(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _savePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3A3A3C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Update Password', style: TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Divider(color: Color(0xFF3A3A3C)),
                    const SizedBox(height: 16),

                    // Theme picker
                    const Text('Theme', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: AppTheme.allThemes.map((theme) {
                        final isSelected = _selectedTheme.name == theme.name;
                        return GestureDetector(
                          onTap: _loading ? null : () => _saveTheme(theme),
                          child: Container(
                            width: 130,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? theme.correct : const Color(0xFF3A3A3C),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                // Mini tile preview
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _miniTile(theme.correct, 'G', theme.textColor),
                                    const SizedBox(width: 4),
                                    _miniTile(theme.present, 'U', theme.textColor),
                                    const SizedBox(width: 4),
                                    _miniTile(theme.absent, 'E', theme.textColor),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  theme.name,
                                  style: TextStyle(color: theme.textColor, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                if (isSelected)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(Icons.check_circle, color: theme.correct, size: 16),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                    ],
                    if (_success != null) ...[
                      const SizedBox(height: 16),
                      Text(_success!, style: TextStyle(color: widget.currentTheme.correct, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniTile(Color bg, String letter, Color textColor) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}
