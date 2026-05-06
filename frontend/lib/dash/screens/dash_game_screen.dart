import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/app_theme.dart';
import '../../widgets/wavy_background.dart';
import '../models/level.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../painters/dash_painter.dart';

class DashGameScreen extends StatefulWidget {
  final String nickname;
  final int userId;
  final AppTheme theme;
  final DashLevel level;
  final VoidCallback onBack;

  const DashGameScreen({
    super.key,
    required this.nickname,
    required this.userId,
    required this.theme,
    required this.level,
    required this.onBack,
  });

  @override
  State<DashGameScreen> createState() => _DashGameScreenState();
}

class _DashGameScreenState extends State<DashGameScreen> with SingleTickerProviderStateMixin {
  static const double T = 40.0;
  static const double CW = 1200, CH = 500;

  late DashPlayer _player;
  late List<DashEnemy> _enemies;
  late List<ActiveMovingPlatform> _platforms;
  late List<QuestionBlock> _questionBlocks;
  final List<Fireball> _fireballs = [];
  final List<Hammer> _hammers = [];
  final Set<int> _collectedCoins = {};

  double _cameraX = 0;
  int _timeBonus = 500;
  double _timeBonusTimer = 0;
  double _startTime = 0;
  bool _gameOver = false;
  bool _won = false;
  bool _playerFlash = false;
  double _invincibleTimer = 0;
  bool _submitted = false;

  bool _leftDown = false, _rightDown = false, _jumpDown = false, _downDown = false;
  bool _jumpConsumed = false;

  late Ticker _ticker;
  DateTime _lastTick = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initGame();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _ticker = createTicker(_onTick)..start();
    _startTime = DateTime.now().millisecondsSinceEpoch.toDouble();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _ticker.dispose();
    super.dispose();
  }

  void _initGame() {
    final level = widget.level;
    // Find start position: column 2, standing on ground
    double startY = (level.height - 3) * T;
    _player = DashPlayer(x: 2 * T, y: startY);

    _enemies = level.enemies.map((s) {
      final type = _parseEnemyType(s.type);
      return DashEnemy(type: type, x: s.x * T, y: s.y * T);
    }).toList();

    _platforms = level.movingPlatforms.map((mp) => ActiveMovingPlatform(
      x: mp.x * T, y: mp.y * T,
      tileWidth: mp.width, axis: mp.axis,
      range: mp.range * T, speed: mp.speed,
    )).toList();

    _questionBlocks = level.questionBlocks.map((qb) => QuestionBlock(x: qb.x, y: qb.y, content: qb.content)).toList();
  }

  EnemyType _parseEnemyType(String s) {
    switch (s) {
      case 'koopa': return EnemyType.koopa;
      case 'piranha': return EnemyType.piranha;
      case 'spiny': return EnemyType.spiny;
      case 'buzzyBeetle': return EnemyType.buzzyBeetle;
      case 'hammerBro': return EnemyType.hammerBro;
      case 'boo': return EnemyType.boo;
      default: return EnemyType.goomba;
    }
  }

  bool _handleKey(KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final up = event is KeyUpEvent;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) { _leftDown = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _rightDown = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) { _downDown = down || !up; return true; }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.space) {
      if (down && !_jumpConsumed) { _jumpConsumed = true; _player.jump(); }
      if (up) _jumpConsumed = false;
      return true;
    }
    return false;
  }

  void _onTick(Duration _) {
    if (_gameOver || _won) return;
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMicroseconds / 16667.0;
    _lastTick = now;

    setState(() {
      _update(dt.clamp(0.5, 3.0));
    });
  }

  void _update(double dt) {
    final level = widget.level;

    // Time bonus
    _timeBonusTimer += dt / 60.0;
    if (_timeBonusTimer >= 1.0) {
      _timeBonusTimer = 0;
      if (_timeBonus > 0) _timeBonus = max(0, _timeBonus - 1);
    }

    // Invincibility
    if (_player.invincible) {
      _invincibleTimer -= dt / 60.0;
      if (_invincibleTimer <= 0) { _player.invincible = false; _playerFlash = false; }
      else { _playerFlash = ((_invincibleTimer * 10).floor() % 2 == 0); }
    }

    // Star timer
    if (_player.starActive) {
      _player.starTimer -= dt / 60.0;
      if (_player.starTimer <= 0) _player.starActive = false;
    }

    // Player horizontal movement
    if (_leftDown) { _player.vx = -DashPlayer.speed; _player.facingRight = false; }
    else if (_rightDown) { _player.vx = DashPlayer.speed; _player.facingRight = true; }
    else _player.vx = 0;

    // Gravity
    _player.applyGravity();

    // Move player
    _player.x += _player.vx * dt;
    _player.x = _player.x.clamp(0, (level.width - 1) * T);
    _player.y += _player.vy * dt;

    // Tile collisions
    _player.onGround = false;
    _resolveTileCollisions();

    // Moving platforms
    for (final p in _platforms) {
      if (p.axis == 'x') {
        p.x += p.speed * p.dir * dt;
        if ((p.x - p.originX).abs() >= p.range) p.dir *= -1;
      } else {
        p.y += p.speed * p.dir * dt;
        if ((p.y - p.originY).abs() >= p.range) p.dir *= -1;
      }
      // Player on platform
      final pr = _player.rect;
      final plr = p.rect;
      if (_player.vy >= 0 &&
          pr.bottom >= plr.top && pr.bottom <= plr.top + 12 &&
          pr.right > plr.left && pr.left < plr.right) {
        _player.y = plr.top - DashPlayer.height;
        _player.vy = 0;
        _player.onGround = true;
        if (p.axis == 'x') _player.x += p.speed * p.dir * dt;
      }
    }

    // Enemies
    _updateEnemies(dt);

    // Fireballs
    _updateFireballs(dt);

    // Hammers
    _updateHammers(dt);

    // Coins
    _checkCoins();

    // Pipe entry
    if (_downDown) _checkPipeEntry();

    // Death conditions
    if (_player.y > level.height * T) _loseLife();

    // Win condition
    _checkWin();

    // Camera
    _cameraX = (_player.x - CW / 3).clamp(0, max(0, level.width * T - CW));
  }

  void _resolveTileCollisions() {
    final level = widget.level;
    final p = _player;

    // Check tiles around player
    final left = (p.x / T).floor();
    final right = ((p.x + DashPlayer.width) / T).floor();
    final top = (p.y / T).floor();
    final bottom = ((p.y + DashPlayer.height) / T).floor();

    for (int row = top - 1; row <= bottom + 1; row++) {
      for (int col = left - 1; col <= right + 1; col++) {
        final id = level.tileAt(col, row);
        if (!_isSolid(id)) continue;
        final tr = Rect.fromLTWH(col * T, row * T, T, T);
        final pr = p.rect;
        if (!pr.overlaps(tr)) continue;

        final overlapX = min(pr.right - tr.left, tr.right - pr.left);
        final overlapY = min(pr.bottom - tr.top, tr.bottom - pr.top);

        if (overlapX < overlapY) {
          if (pr.center.dx < tr.center.dx) p.x = tr.left - DashPlayer.width;
          else p.x = tr.right;
          p.vx = 0;
        } else {
          if (pr.center.dy < tr.center.dy) {
            // Landing on top
            p.y = tr.top - DashPlayer.height;
            p.vy = 0;
            p.onGround = true;
            // Spring
            if (id == 13) p.springJump();
          } else {
            // Hitting from below
            p.y = tr.bottom;
            if (p.vy < 0) {
              p.vy = 0;
              _hitBlockFromBelow(col, row, id);
            }
          }
        }
      }
    }

    // One-way platforms (id=8): only land on top
    for (int row = top; row <= bottom + 1; row++) {
      for (int col = left; col <= right; col++) {
        if (level.tileAt(col, row) != 8) continue;
        final tr = Rect.fromLTWH(col * T, row * T, T, 10);
        final pr = p.rect;
        if (p.vy >= 0 && pr.bottom >= tr.top && pr.bottom <= tr.top + 12 && pr.right > tr.left && pr.left < tr.right) {
          p.y = tr.top - DashPlayer.height;
          p.vy = 0;
          p.onGround = true;
        }
      }
    }

    // Spike/lava death
    final centerCol = ((p.x + DashPlayer.width / 2) / T).floor();
    final feetRow = ((p.y + DashPlayer.height) / T).floor();
    final feetId = level.tileAt(centerCol, feetRow);
    if (feetId == 9 || feetId == 10) _loseLife();
  }

  bool _isSolid(int id) => id == 1 || id == 2 || id == 3 || id == 4 || id == 5 || id == 6 || id == 13 || id == 14;

  void _hitBlockFromBelow(int col, int row, int id) {
    if (id == 2) {
      // Break brick
      widget.level.tiles[row][col] = 0;
      _player.score += 10;
    } else if (id == 3) {
      // Question block
      final qb = _questionBlocks.firstWhere((q) => q.x == col && q.y == row, orElse: () => QuestionBlock(x: col, y: row, content: 'coin'));
      if (!qb.hit) {
        qb.hit = true;
        widget.level.tiles[row][col] = 4;
        if (qb.content == 'coin') {
          _player.coins++;
          _player.score += 10;
        } else if (qb.content == 'mushroom') {
          _player.big = true;
        } else if (qb.content == 'fireFlower') {
          _player.hasFire = true;
        } else if (qb.content == 'star') {
          _player.starActive = true;
          _player.starTimer = 8.0;
        }
      }
    }
  }

  void _updateEnemies(double dt) {
    for (final e in _enemies) {
      if (!e.alive) continue;
      e.animTimer += dt / 60.0;

      if (e.type == EnemyType.piranha) {
        e.actionTimer += dt / 60.0;
        if (e.actionTimer > 2.0) e.actionTimer = 0;
        e.y = e.y; // stays in pipe
        continue;
      }

      if (e.type == EnemyType.boo) {
        // Move toward player when player faces away
        if (!_player.facingRight) {
          final dx = _player.x - e.x;
          final dy = _player.y - e.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist > 0) { e.x += dx / dist * 1.5 * dt; e.y += dy / dist * 1.5 * dt; }
        }
        continue;
      }

      if (e.inShell && !e.shellMoving) continue;

      // Gravity
      e.vy = (e.vy + DashPlayer.gravity).clamp(-30, 14);
      e.x += e.vx * dt;
      e.y += e.vy * dt;

      // Simple tile collision for enemies
      final col = (e.x / T).floor();
      final row = ((e.y + DashEnemy.height) / T).floor();
      final tileBelow = widget.level.tileAt(col, row);
      if (_isSolid(tileBelow)) {
        e.y = row * T - DashEnemy.height;
        e.vy = 0;
        // Turn at edges
        final tileAhead = widget.level.tileAt(col + (e.vx > 0 ? 1 : -1), row - 1);
        if (_isSolid(tileAhead)) e.vx *= -1;
        // Turn at ledge
        final tileFloorAhead = widget.level.tileAt(col + (e.vx > 0 ? 1 : -1), row);
        if (!_isSolid(tileFloorAhead) && e.type != EnemyType.koopa) e.vx *= -1;
      }

      // Hammer bro throws hammers
      if (e.type == EnemyType.hammerBro) {
        e.actionTimer += dt / 60.0;
        if (e.actionTimer >= 2.0) {
          e.actionTimer = 0;
          final dir = _player.x > e.x ? 1.0 : -1.0;
          _hammers.add(Hammer(x: e.x, y: e.y, vx: dir * 4, vy: -8));
        }
      }

      // Player-enemy collision
      if (!_player.invincible && !_player.starActive) {
        final pr = _player.rect;
        final er = e.rect;
        if (pr.overlaps(er)) {
          // Stomp check
          if (_player.vy > 0 && pr.bottom < er.center.dy + 8 && e.canBeStopped) {
            _stompEnemy(e);
          } else {
            _loseLife();
          }
        }
      } else if (_player.starActive) {
        if (_player.rect.overlaps(e.rect)) {
          e.alive = false;
          _player.score += e.points;
        }
      }
    }
  }

  void _stompEnemy(DashEnemy e) {
    _player.vy = DashPlayer.jumpVelocity * 0.6;
    if (e.type == EnemyType.koopa && !e.inShell) {
      e.inShell = true;
      e.vx = 0;
    } else {
      e.alive = false;
      _player.score += e.points;
    }
  }

  void _updateFireballs(double dt) {
    for (final f in _fireballs) {
      f.x += f.vx * dt;
      f.vy = (f.vy + 0.3).clamp(-20, 10);
      f.y += f.vy * dt;
      // Bounce off ground
      final col = (f.x / T).floor();
      final row = (f.y / T).floor();
      if (_isSolid(widget.level.tileAt(col, row))) f.vy = -6;
    }
    _fireballs.removeWhere((f) => f.x < 0 || f.x > widget.level.width * T || f.y > widget.level.height * T);

    // Fireball-enemy collision
    for (final f in List.of(_fireballs)) {
      for (final e in _enemies) {
        if (!e.alive || !e.canBeFireballed) continue;
        if (f.rect.overlaps(e.rect)) {
          e.alive = false;
          _player.score += e.points;
          _fireballs.remove(f);
          break;
        }
      }
    }
  }

  void _updateHammers(double dt) {
    for (final h in _hammers) {
      h.x += h.vx * dt;
      h.vy = (h.vy + 0.4).clamp(-20, 14);
      h.y += h.vy * dt;
      if (!_player.invincible && !_player.starActive && h.rect.overlaps(_player.rect)) {
        _loseLife();
        _hammers.remove(h);
        break;
      }
    }
    _hammers.removeWhere((h) => h.y > widget.level.height * T);
  }

  void _checkCoins() {
    final level = widget.level;
    final col = ((_player.x + DashPlayer.width / 2) / T).floor();
    final row = ((_player.y + DashPlayer.height / 2) / T).floor();
    for (int r = row - 1; r <= row + 1; r++) {
      for (int c = col - 1; c <= col + 1; c++) {
        if (level.tileAt(c, r) == 7) {
          final key = c * 1000 + r;
          if (!_collectedCoins.contains(key)) {
            _collectedCoins.add(key);
            _player.coins++;
            _player.score += 10;
          }
        }
      }
    }
  }

  void _checkPipeEntry() {
    final level = widget.level;
    final col = ((_player.x + DashPlayer.width / 2) / T).floor();
    final row = ((_player.y + DashPlayer.height) / T).floor();
    if (level.tileAt(col, row) == 5 || level.tileAt(col, row) == 6) {
      for (final wp in level.warpPipes) {
        if (wp.entranceX == col && wp.entranceY == row) {
          _player.x = wp.exitX * T;
          _player.y = wp.exitY * T - DashPlayer.height;
          break;
        }
      }
    }
  }

  void _checkWin() {
    final level = widget.level;
    final col = ((_player.x + DashPlayer.width / 2) / T).floor();
    final row = ((_player.y + DashPlayer.height / 2) / T).floor();
    if (level.tileAt(col, row) == 11 || level.tileAt(col + 1, row) == 11) {
      _won = true;
      _player.score += 1000 + _timeBonus + _player.lives * 200;
      if (!_submitted) { _submitted = true; _submitScore(); }
    }
  }

  void _loseLife() {
    if (_player.invincible) return;
    _player.lives--;
    if (_player.lives <= 0) {
      _gameOver = true;
      return;
    }
    _player.invincible = true;
    _invincibleTimer = 2.0;
    _playerFlash = true;
    // Reset position
    _player.x = 2 * T;
    _player.y = (widget.level.height - 3) * T;
    _player.vx = 0;
    _player.vy = 0;
  }

  Future<void> _submitScore() async {
    final elapsed = ((DateTime.now().millisecondsSinceEpoch - _startTime) / 1000).round();
    try {
      await http.post(
        Uri.parse('/api/dash/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.userId,
          'nickname': widget.nickname,
          'score': _player.score,
          'timeSeconds': elapsed,
          'coins': _player.coins,
        }),
      );
    } catch (_) {}
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
                  Text('Dash.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: widget.theme.correct, blurRadius: 8)])),
                ],
              ),
            ),
            const Divider(color: Color(0xFF3A3A3C), height: 1),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: CW / CH,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 500),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: widget.theme.correct.withValues(alpha: 0.3), width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CustomPaint(
                          painter: DashPainter(
                            level: widget.level,
                            player: _player,
                            enemies: _enemies,
                            fireballs: _fireballs,
                            hammers: _hammers,
                            platforms: _platforms,
                            questionBlocks: _questionBlocks,
                            collectedCoins: _collectedCoins,
                            cameraX: _cameraX,
                            theme: widget.theme,
                            timeBonus: _timeBonus,
                            gameOver: _gameOver,
                            won: _won,
                            playerFlash: _playerFlash,
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
        if (_won)
          Center(
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
                  Text('🎉 Level Complete!', style: TextStyle(color: widget.theme.correct, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('Score: ${_player.score}', style: const TextStyle(color: Colors.white, fontSize: 20)),
                  Text('Coins: ${_player.coins}', style: TextStyle(color: widget.theme.present, fontSize: 16)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: widget.onBack,
                    style: ElevatedButton.styleFrom(backgroundColor: widget.theme.correct, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: const Text('Back to Menu', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        if (_gameOver)
          Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF121213).withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.theme.absent, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Game Over', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('No score submitted — complete the level to rank!', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: widget.onBack,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3A3C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: const Text('Back', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
