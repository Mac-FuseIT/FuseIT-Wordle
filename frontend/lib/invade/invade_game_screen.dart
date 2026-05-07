import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import '../services/api_service.dart';
import '../models/app_theme.dart';
import '../widgets/wavy_background.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _Enemy {
  double x, y;
  double dx, dy; // movement direction
  final int tier;
  int hp;
  bool flashing = false;
  double fireTimer = 0;

  _Enemy(this.x, this.y, this.tier, Random rng)
      : hp = tier == 3 ? 2 : 1,
        dx = (rng.nextDouble() * 2 - 1) * 2,
        dy = rng.nextDouble() * 1.5 + 0.5;

  int get points => tier == 1 ? 10 : tier == 2 ? 25 : 50;
  double get fireInterval => tier == 1 ? 3.0 : tier == 2 ? 2.0 : 1.2; // seconds between shots
}

class _Bullet {
  double x, y;
  final bool fromPlayer;
  _Bullet(this.x, this.y, this.fromPlayer);
}

class _Explosion {
  double x, y;
  double radius = 0;
  final double maxRadius;
  _Explosion(this.x, this.y, this.maxRadius);
}

class _HealthPack {
  double x, y;
  _HealthPack(this.x, this.y);
}



class InvadeGameScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final VoidCallback onBack;

  const InvadeGameScreen({
    super.key,
    required this.nickname,
    required this.userId,
    required this.theme,
    required this.onBack,
  });

  @override
  State<InvadeGameScreen> createState() => _InvadeGameScreenState();
}

class _InvadeGameScreenState extends State<InvadeGameScreen> with SingleTickerProviderStateMixin {
  static const double W = 800, H = 600;

  double _px = W / 2, _py = H - 60;
  int _lives = 2;
  bool _invincible = false, _playerFlash = false;

  int _score = 0, _level = 1, _bestScore = 0;
  bool _gameOver = false;
  String? _levelMessage;
  String? _sessionToken;

  final List<_Enemy> _enemies = [];
  final List<_Bullet> _playerBullets = [];
  final List<_Bullet> _enemyBullets = [];
  final List<_Explosion> _explosions = [];
  final List<_HealthPack> _healthPacks = [];

  bool _leftDown = false, _rightDown = false, _upDown = false, _downDown = false, _spaceDown = false;
  Timer? _shootTimer;
  Timer? _spawnTimer;
  Timer? _healthPackTimer;

  late Ticker _ticker;
  DateTime _lastTick = DateTime.now();
  final Random _rng = Random();

  // Spawn tracking
  int _enemiesKilled = 0;
  int get _killsToNextLevel => 10 + (_level - 1) * 5;

  @override
  void initState() {
    super.initState();
    _loadBest();
    _loadSession();
    _startSpawnTimer();
    _startHealthPackTimer();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _shootTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_spaceDown && !_gameOver && _playerBullets.length < 2) {
        setState(() => _playerBullets.add(_Bullet(_px, _py - 20, true)));
      }
    });
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _shootTimer?.cancel();
    _spawnTimer?.cancel();
    _healthPackTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _startSpawnTimer() {
    _spawnTimer?.cancel();
    // Spawn interval decreases with level: 2s → 1.2s → 0.8s → 0.5s
    final ms = max(500, 2000 - (_level - 1) * 400);
    _spawnTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!_gameOver) _spawnEnemy();
    });
  }

  void _startHealthPackTimer() {
    _healthPackTimer?.cancel();
    _healthPackTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_gameOver) setState(() => _healthPacks.add(_HealthPack(30 + _rng.nextDouble() * (W - 60), -20)));
    });
  }

  void _spawnEnemy() {
    // Higher levels spawn higher-tier enemies more often
    int tier;
    final r = _rng.nextDouble();
    if (_level >= 4) {
      tier = r < 0.2 ? 1 : r < 0.5 ? 2 : 3;
    } else if (_level == 3) {
      tier = r < 0.4 ? 1 : r < 0.7 ? 2 : 3;
    } else if (_level == 2) {
      tier = r < 0.6 ? 1 : r < 0.9 ? 2 : 3;
    } else {
      tier = r < 0.8 ? 1 : r < 0.95 ? 2 : 3;
    }
    final x = 30 + _rng.nextDouble() * (W - 60);
    setState(() => _enemies.add(_Enemy(x, -20, tier, _rng)));
  }

  Future<void> _loadSession() async {
    _sessionToken = await ApiService.startInvadeSession();
  }

  Future<void> _loadBest() async {
    try {
      final data = await ApiService.getInvadeLeaderboard();
      if (mounted) setState(() => _bestScore = data['best'] ?? 0);
    } catch (_) {}
  }

  Future<void> _submitScore() async {
    if (_score <= _bestScore || _sessionToken == null) return;
    try {
      await ApiService.submitInvadeScore(_score, _level, _sessionToken!);
    } catch (_) {}
  }

  bool _handleKey(KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final up = event is KeyUpEvent;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft)  { _leftDown  = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _rightDown = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp)    { _upDown    = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown)  { _downDown  = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.space)      { _spaceDown = down || !up; return true; }
    return false;
  }

  void _onTick(Duration _) {
    if (_gameOver) return;
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMicroseconds / 16667.0;
    _lastTick = now;

    setState(() {
      const speed = 4.0;
      if (_leftDown)  _px = (_px - speed * dt).clamp(15, W - 15);
      if (_rightDown) _px = (_px + speed * dt).clamp(15, W - 15);
      if (_upDown)    _py = (_py - speed * dt).clamp(15, H - 15);
      if (_downDown)  _py = (_py + speed * dt).clamp(15, H - 15);

      // Move player bullets
      for (final b in _playerBullets) b.y -= 8 * dt;
      _playerBullets.removeWhere((b) => b.y < 0);

      // Move enemies randomly
      for (final e in _enemies) {
        e.x += e.dx * dt * (1 + (_level - 1) * 0.2);
        e.y += e.dy * dt * (1 + (_level - 1) * 0.2);
        // Bounce off walls
        if (e.x < 15 || e.x > W - 15) e.dx *= -1;
        // Random direction change
        if (_rng.nextDouble() < 0.01 * dt) {
          e.dx = (_rng.nextDouble() * 2 - 1) * 2;
          e.dy = _rng.nextDouble() * 1.5 + 0.3;
        }
        // Enemy shooting
        e.fireTimer += dt / 60.0;
        if (e.fireTimer >= e.fireInterval) {
          e.fireTimer = 0;
          // Aim roughly toward player
          final angle = atan2(_py - e.y, _px - e.x);
          _enemyBullets.add(_Bullet(e.x, e.y + 15, false)
            ..x = e.x
            ..y = e.y + 15);
          // Store direction in bullet via subclass trick - just use angle-based velocity
          _enemyBullets.last; // we'll handle direction in movement below
          _aimBullets.add(_AimBullet(e.x, e.y + 15, cos(angle) * 3, sin(angle) * 3));
          _enemyBullets.removeLast(); // remove the plain one, use aimed
        }
      }
      _enemies.removeWhere((e) => e.y > H + 30);

      // Move aimed bullets
      for (final b in _aimBullets) { b.x += b.vx * dt; b.y += b.vy * dt; }
      _aimBullets.removeWhere((b) => b.x < 0 || b.x > W || b.y < 0 || b.y > H);

      // Move enemy bullets (legacy - keep empty)
      _enemyBullets.removeWhere((b) => b.y > H);

      // Explosions
      for (final ex in _explosions) ex.radius += 3 * dt;
      _explosions.removeWhere((ex) => ex.radius >= ex.maxRadius);

      // Collision: player bullets vs enemies
      final toRemoveBullets = <_Bullet>{};
      final toRemoveEnemies = <_Enemy>{};
      for (final b in _playerBullets) {
        for (final e in _enemies) {
          if ((b.x - e.x).abs() < 20 && (b.y - e.y).abs() < 15) {
            toRemoveBullets.add(b);
            e.hp--;
            if (e.hp <= 0) {
              toRemoveEnemies.add(e);
              _score += e.points;
              _explosions.add(_Explosion(e.x, e.y, 25));
              _enemiesKilled++;
              // Level up
              if (_enemiesKilled >= _killsToNextLevel) {
                _enemiesKilled = 0;
                _level++;
                _lives = max(_lives, 2);
                _score += 100;
                _startSpawnTimer();
                _levelMessage = 'LEVEL $_level';
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _levelMessage = null);
                });
              }
            } else {
              e.flashing = true;
              Future.delayed(const Duration(milliseconds: 200), () { if (mounted) setState(() => e.flashing = false); });
            }
          }
        }
      }
      _playerBullets.removeWhere(toRemoveBullets.contains);
      _enemies.removeWhere(toRemoveEnemies.contains);

      // Move health packs & collect
      for (final h in _healthPacks) h.y += 1.0 * dt;
      final collected = _healthPacks.where((h) => (h.x - _px).abs() < 22 && (h.y - _py).abs() < 22).toList();
      if (collected.isNotEmpty) {
        _healthPacks.removeWhere(collected.contains);
        _lives += collected.length;
      }
      _healthPacks.removeWhere((h) => h.y > H + 30);

      // Collision: aimed bullets vs player
      if (!_invincible) {
        final hit = _aimBullets.where((b) => (b.x - _px).abs() < 18 && (b.y - _py).abs() < 18).toList();
        if (hit.isNotEmpty) {
          _aimBullets.removeWhere(hit.contains);
          _lives--;
          _playerFlash = true;
          _invincible = true;
          Future.delayed(const Duration(milliseconds: 200), () { if (mounted) setState(() => _playerFlash = false); });
          Future.delayed(const Duration(seconds: 1), () { if (mounted) setState(() => _invincible = false); });
          if (_lives <= 0) { _gameOver = true; _submitScore(); }
        }
      }
    });
  }

  final List<_AimBullet> _aimBullets = [];

  void _restart() {
    _enemies.clear(); _playerBullets.clear(); _enemyBullets.clear();
    _aimBullets.clear(); _explosions.clear(); _healthPacks.clear();
    _score = 0; _level = 1; _lives = 2; _gameOver = false;
    _enemiesKilled = 0; _sessionToken = null;
    _px = W / 2; _py = H - 60;
    _startSpawnTimer();
    _startHealthPackTimer();
    _loadSession();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct),
        Column(
          children: [
            Container(
              color: const Color(0xFF0A0A0B).withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
                  Text('Invade.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: widget.theme.correct, blurRadius: 8)])),
              ]),
            ),
            const Divider(color: Color(0xFF3A3A3C), height: 1),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: W / H,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0B),
                          border: Border.all(color: widget.theme.correct.withValues(alpha: 0.3), width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CustomPaint(
                          painter: _InvadePainter(
                            px: _px, py: _py, playerFlash: _playerFlash,
                            enemies: _enemies,
                            playerBullets: _playerBullets,
                            aimBullets: _aimBullets,
                            explosions: _explosions,
                            healthPacks: _healthPacks,
                            lives: _lives,
                            score: _score,
                            level: _level,
                            theme: widget.theme,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_levelMessage != null)
          Center(
            child: IgnorePointer(
              child: Text(
                _levelMessage!,
                style: TextStyle(
                  color: widget.theme.correct.withValues(alpha: 0.35),
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
            ),
          ),
        if (_gameOver)          Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF121213).withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.theme.correct, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('GAME OVER', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('Your Score: $_score', style: TextStyle(color: widget.theme.correct, fontSize: 20)),
                  const SizedBox(height: 4),
                  Text('Best Score: ${max(_score, _bestScore)}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  if (_score > _bestScore) ...[
                    const SizedBox(height: 8),
                    Text('🎉 New High Score!', style: TextStyle(color: widget.theme.present, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(_restart),
                        style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Play Again', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: widget.onBack,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3A3C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Menu', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Aimed Bullet ─────────────────────────────────────────────────────────────

class _AimBullet {
  double x, y, vx, vy;
  _AimBullet(this.x, this.y, this.vx, this.vy);
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _InvadePainter extends CustomPainter {
  final double px, py;
  final bool playerFlash;
  final List<_Enemy> enemies;
  final List<_Bullet> playerBullets;
  final List<_AimBullet> aimBullets;
  final List<_Explosion> explosions;
  final List<_HealthPack> healthPacks;
  final int lives, score, level;
  final AppTheme theme;

  _InvadePainter({
    required this.px, required this.py, required this.playerFlash,
    required this.enemies, required this.playerBullets,
    required this.aimBullets, required this.explosions,
    required this.healthPacks,
    required this.lives, required this.score, required this.level,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 800, sy = size.height / 600;

    // Score & level at top-center
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: 'Score: $score    Level: $level',
      style: TextStyle(color: theme.correct.withValues(alpha: 0.9), fontSize: 14 * sx * 2, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width / 2 - textPainter.width / 2, 10 * sy));

    // Player
    if (!playerFlash) {
      final path = Path()
        ..moveTo(px * sx, (py - 18) * sy)
        ..lineTo((px - 12) * sx, (py + 12) * sy)
        ..lineTo((px + 12) * sx, (py + 12) * sy)
        ..close();
      canvas.drawPath(path, Paint()..color = theme.correct);
      canvas.drawRect(Rect.fromLTWH((px - 4) * sx, (py + 12) * sy, 8 * sx, 6 * sy), Paint()..color = theme.present);
    }

    // Player bullets
    for (final b in playerBullets) {
      canvas.drawRect(Rect.fromLTWH((b.x - 2) * sx, (b.y - 8) * sy, 4 * sx, 16 * sy), Paint()..color = theme.correct);
    }

    // Enemies
    for (final e in enemies) {
      final ex = e.x * sx, ey = e.y * sy;
      final color = e.flashing ? Colors.white : (e.tier == 1 ? theme.absent : e.tier == 2 ? theme.present : theme.correct);
      final paint = Paint()..color = color;
      if (e.tier == 1) {
        canvas.drawRect(Rect.fromLTWH(ex - 14 * sx, ey - 8 * sy, 28 * sx, 16 * sy), paint);
        canvas.drawRect(Rect.fromLTWH(ex - 8 * sx, ey - 14 * sy, 16 * sx, 8 * sy), paint);
        canvas.drawRect(Rect.fromLTWH(ex - 18 * sx, ey, 6 * sx, 8 * sy), paint);
        canvas.drawRect(Rect.fromLTWH(ex + 12 * sx, ey, 6 * sx, 8 * sy), paint);
      } else if (e.tier == 2) {
        canvas.drawOval(Rect.fromLTWH(ex - 12 * sx, ey - 10 * sy, 24 * sx, 20 * sy), paint);
        canvas.drawRect(Rect.fromLTWH(ex - 16 * sx, ey - 2 * sy, 6 * sx, 10 * sy), paint);
        canvas.drawRect(Rect.fromLTWH(ex + 10 * sx, ey - 2 * sy, 6 * sx, 10 * sy), paint);
      } else {
        canvas.drawOval(Rect.fromLTWH(ex - 18 * sx, ey - 8 * sy, 36 * sx, 16 * sy), paint);
        canvas.drawOval(Rect.fromLTWH(ex - 10 * sx, ey - 16 * sy, 20 * sx, 12 * sy), paint);
        if (e.hp == 2) canvas.drawCircle(Offset(ex, ey), 4 * sx, Paint()..color = Colors.white);
      }
    }

    // Aimed bullets
    for (final b in aimBullets) {
      canvas.drawCircle(Offset(b.x * sx, b.y * sy), 4 * sx, Paint()..color = theme.present);
    }

    // Explosions
    for (final ex in explosions) {
      canvas.drawCircle(
        Offset(ex.x * sx, ex.y * sy), ex.radius * sx,
        Paint()..color = theme.present.withValues(alpha: 1 - ex.radius / ex.maxRadius),
      );
    }

    // Health packs
    for (final h in healthPacks) {
      final hx = h.x * sx, hy = h.y * sy;
      final r = 10 * sx;
      canvas.drawRect(Rect.fromLTWH(hx - r * 0.3, hy - r, r * 0.6, r * 2), Paint()..color = Colors.redAccent);
      canvas.drawRect(Rect.fromLTWH(hx - r, hy - r * 0.3, r * 2, r * 0.6), Paint()..color = Colors.redAccent);
    }

    // Hearts at bottom-center of canvas
    final heartSpacing = 30 * sx;
    final heartsStartX = size.width / 2 - (lives - 1) * heartSpacing / 2;
    for (int i = 0; i < lives; i++) {
      final cx = heartsStartX + i * heartSpacing;
      final cy = (580) * sy;
      final r = 10 * sx;
      final paint = Paint()
        ..color = theme.present.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      final path = Path();
      path.moveTo(cx, cy + r * 0.3);
      path.cubicTo(cx, cy - r * 0.5, cx - r * 1.2, cy - r * 0.5, cx - r * 1.2, cy + r * 0.2);
      path.cubicTo(cx - r * 1.2, cy + r * 0.8, cx, cy + r * 1.4, cx, cy + r * 1.4);
      path.cubicTo(cx, cy + r * 1.4, cx + r * 1.2, cy + r * 0.8, cx + r * 1.2, cy + r * 0.2);
      path.cubicTo(cx + r * 1.2, cy - r * 0.5, cx, cy - r * 0.5, cx, cy + r * 0.3);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}
