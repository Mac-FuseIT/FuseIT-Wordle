import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'models/app_theme.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_menu_screen.dart';
import 'screens/game_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/profile_screen.dart';
import 'crossword/screens/crossword_screen.dart';
import 'crossword/screens/crossword_leaderboard.dart';
import 'widgets/wavy_background.dart';

void main() => runApp(const FuseArcadeApp());

class FuseArcadeApp extends StatelessWidget {
  const FuseArcadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuse Arcade',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF121213)),
      home: const AppShell(),
    );
  }
}

enum AppView { login, menu, guessGame, guessLeaderboard, crossGame, crossLeaderboard, profile }

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppView _view = AppView.login;
  int? _userId;
  String? _name;
  AppTheme _theme = AppTheme.defaultTheme;
  bool _checkingSession = true;

  @override
  void initState() { super.initState(); _restoreSession(); }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('userId');
    final name = prefs.getString('userName');
    final themeJson = prefs.getString('userTheme');
    if (id != null && name != null) {
      if (themeJson != null) { try { _theme = AppTheme.fromJson(jsonDecode(themeJson)); } catch (_) {} }
      setState(() { _userId = id; _name = name; _view = AppView.menu; });
    }
    setState(() => _checkingSession = false);
  }

  Future<void> _onLogin(int userId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userId', userId);
    await prefs.setString('userName', name);
    setState(() { _userId = userId; _name = name; _view = AppView.menu; });
  }

  void _applyLoginTheme(Map<String, dynamic>? themeData) async {
    if (themeData != null) {
      try {
        final t = AppTheme.fromJson(themeData);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userTheme', jsonEncode(themeData));
        setState(() => _theme = t);
      } catch (_) {}
    }
  }

  Future<void> _logout() async {
    await ApiService.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userTheme');
    setState(() { _userId = null; _name = null; _theme = AppTheme.defaultTheme; _view = AppView.login; });
  }

  void _onNameUpdated(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', newName);
    setState(() { _name = newName; });
  }

  void _onThemeUpdated(AppTheme newTheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userTheme', jsonEncode(newTheme.toJson()));
    setState(() => _theme = newTheme);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6AAA64))));
    }

    return Scaffold(
      backgroundColor: _theme.background,
      body: Stack(
        children: [
          Positioned.fill(child: WavyBackground(backgroundColor: _theme.background, accentColor: _theme.correct)),
          SafeArea(
            child: switch (_view) {
              AppView.login => LoginScreen(onLogin: _onLogin, onThemeLoaded: _applyLoginTheme, accentColor: _theme.correct),
              AppView.menu => MainMenuScreen(
                name: _name!,
                theme: _theme,
                onGuessIT: () => setState(() => _view = AppView.guessGame),
                onCrossIT: () => setState(() => _view = AppView.crossGame),
                onProfile: () => setState(() => _view = AppView.profile),
                onLogout: _logout,
              ),
              AppView.guessGame => GameScreen(
                userId: _userId!, name: _name!, theme: _theme,
                onShowLeaderboard: () => setState(() => _view = AppView.guessLeaderboard),
                onShowProfile: () => setState(() => _view = AppView.profile),
                onLogout: () => setState(() => _view = AppView.menu),
              ),
              AppView.guessLeaderboard => LeaderboardScreen(
                onBack: () => setState(() => _view = AppView.guessGame),
                userId: _userId!, theme: _theme,
              ),
              AppView.crossGame => CrosswordScreen(
                theme: _theme,
                onBack: () => setState(() => _view = AppView.menu),
                onLeaderboard: () => setState(() => _view = AppView.crossLeaderboard),
              ),
              AppView.crossLeaderboard => CrosswordLeaderboard(
                theme: _theme,
                onBack: () => setState(() => _view = AppView.crossGame),
              ),
              AppView.profile => ProfileScreen(
                userId: _userId!, currentName: _name!, currentTheme: _theme,
                onBack: () => setState(() => _view = AppView.menu),
                onNameUpdated: _onNameUpdated, onThemeUpdated: _onThemeUpdated,
              ),
            },
          ),
        ],
      ),
    );
  }
}
