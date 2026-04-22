import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/game_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/profile_screen.dart';

void main() => runApp(const GuessITApp());

class GuessITApp extends StatelessWidget {
  const GuessITApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guess.IT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121213),
      ),
      home: const AppShell(),
    );
  }
}

enum AppView { login, game, leaderboard, profile }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppView _view = AppView.login;
  int? _userId;
  String? _name;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('userId');
    final name = prefs.getString('userName');
    if (id != null && name != null) {
      setState(() { _userId = id; _name = name; _view = AppView.game; });
    }
    setState(() => _checkingSession = false);
  }

  Future<void> _onLogin(int userId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userId', userId);
    await prefs.setString('userName', name);
    setState(() { _userId = userId; _name = name; _view = AppView.game; });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    setState(() { _userId = null; _name = null; _view = AppView.login; });
  }

  void _onNameUpdated(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', newName);
    setState(() { _name = newName; _view = AppView.game; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6AAA64))));
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SvgPicture.asset('assets/bg.svg', fit: BoxFit.cover),
          ),
          SafeArea(
            child: switch (_view) {
              AppView.login => LoginScreen(onLogin: _onLogin),
              AppView.game => GameScreen(
                userId: _userId!,
                name: _name!,
                onShowLeaderboard: () => setState(() => _view = AppView.leaderboard),
                onShowProfile: () => setState(() => _view = AppView.profile),
                onLogout: _logout,
              ),
              AppView.leaderboard => LeaderboardScreen(
                onBack: () => setState(() => _view = AppView.game),
                userId: _userId!,
              ),
              AppView.profile => ProfileScreen(
                userId: _userId!,
                currentName: _name!,
                onBack: () => setState(() => _view = AppView.game),
                onNameUpdated: _onNameUpdated,
              ),
            },
          ),
        ],
      ),
    );
  }
}
