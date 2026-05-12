import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../models/app_theme.dart';
import '../widgets/wavy_background.dart';
import 'rogue_level.dart';
import 'rogue_world.dart';

class RogueGameScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  const RogueGameScreen({super.key, required this.theme, required this.onBack});

  @override
  State<RogueGameScreen> createState() => _RogueGameScreenState();
}

class _RogueGameScreenState extends State<RogueGameScreen> with SingleTickerProviderStateMixin {
  late RogueWorld _world;
  late Ticker _ticker;
  DateTime _lastTick = DateTime.now();

  bool _leftDown = false, _rightDown = false, _upDown = false, _downDown = false;
  bool _jumpPressed = false; // single-frame flag

  // Camera offset
  double _camX = 0, _camY = 0;

  @override
  void initState() {
    super.initState();
    _initWorld();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _ticker = createTicker(_onTick)..start();
  }

  void _initWorld() {
    final today = DateTime.now();
    final seed = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    final level = RogueLevel.generate(seed);
    _world = RogueWorld.fromLevel(level);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _ticker.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final up = event is KeyUpEvent;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:  _leftDown  = down || !up; return true;
      case LogicalKeyboardKey.arrowRight: _rightDown = down || !up; return true;
      case LogicalKeyboardKey.arrowUp:
        if (event is KeyDownEvent) _jumpPressed = true;
        _upDown = down || !up;
        return true;
      case LogicalKeyboardKey.arrowDown:  _downDown  = down || !up; return true;
      case LogicalKeyboardKey.space:
        if (event is KeyDownEvent) _jumpPressed = true;
        return true;
      default: return false;
    }
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMilliseconds;
    _lastTick = now;
    if (dt > 100) return; // skip big gaps

    setState(() {
      _world.tick(
        leftDown: _leftDown, rightDown: _rightDown,
        upDown: _upDown, downDown: _downDown,
        jumpPressed: _jumpPressed,
      );
      _jumpPressed = false;

      // Camera follows player
      final p = _world.player;
      _camX = p.x - 400 + p.w / 2;
      _camY = p.y - 250 + p.h / 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WavyBackground(backgroundColor: widget.theme.background, accentColor: widget.theme.correct),
        Column(children: [
          // Header
          Container(
            color: const Color(0xFF0A0A0B).withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: widget.onBack),
              Text('Rogue.IT', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: widget.theme.correct, blurRadius: 8)])),
              const Spacer(),
              // HP bar
              _HpBar(hp: _world.player.hp, maxHp: _world.player.maxHp, color: widget.theme.present),
              const SizedBox(width: 12),
              Text(_world.player.weapon.name, style: TextStyle(color: widget.theme.correct, fontSize: 13)),
            ]),
          ),
          const Divider(color: Color(0xFF3A3A3C), height: 1),
          // Game canvas
          Expanded(
            child: GestureDetector(
              onTapDown: (_) => setState(() { _world.lightAttack(); }),
              onSecondaryTapDown: (_) => setState(() { _world.heavyAttack(); }),
              child: ClipRect(
                child: CustomPaint(
                  painter: _RoguePainter(world: _world, camX: _camX, camY: _camY, theme: widget.theme),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          // Mobile controls
          _MobileControls(
            onLeft: (d) => setState(() => _leftDown = d),
            onRight: (d) => setState(() => _rightDown = d),
            onUp: (d) => setState(() => _upDown = d),
            onDown: (d) => setState(() => _downDown = d),
            onJump: () => setState(() => _jumpPressed = true),
            onLight: () => setState(() => _world.lightAttack()),
            onHeavy: () => setState(() => _world.heavyAttack()),
            theme: widget.theme,
          ),
        ]),
        // Overlays
        if (_world.levelComplete)
          _Overlay(title: '🏆 Level Complete!', subtitle: 'You cleared all enemies and reached the exit.', buttonLabel: 'Play Again', onButton: () => setState(_initWorld), theme: widget.theme),
        if (_world.gameOver)
          _Overlay(title: '💀 Game Over', subtitle: 'You were defeated.', buttonLabel: 'Try Again', onButton: () => setState(_initWorld), theme: widget.theme),
      ],
    );
  }
}

// ─── HUD ──────────────────────────────────────────────────────────────────────
class _HpBar extends StatelessWidget {
  final int hp, maxHp;
  final Color color;
  const _HpBar({required this.hp, required this.maxHp, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(Icons.favorite, color: color, size: 16),
      const SizedBox(width: 4),
      SizedBox(
        width: 80, height: 8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: hp / maxHp,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text('$hp', style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

// ─── Overlay ──────────────────────────────────────────────────────────────────
class _Overlay extends StatelessWidget {
  final String title, subtitle, buttonLabel;
  final VoidCallback onButton;
  final AppTheme theme;
  const _Overlay({required this.title, required this.subtitle, required this.buttonLabel, required this.onButton, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Center(child: Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF121213).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.correct, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 14)),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onButton,
          style: ElevatedButton.styleFrom(backgroundColor: theme.correct, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: Text(buttonLabel, style: const TextStyle(color: Colors.white)),
        ),
      ]),
    ));
  }
}

// ─── Mobile Controls ──────────────────────────────────────────────────────────
class _MobileControls extends StatelessWidget {
  final void Function(bool) onLeft, onRight, onUp, onDown;
  final VoidCallback onJump, onLight, onHeavy;
  final AppTheme theme;
  const _MobileControls({required this.onLeft, required this.onRight, required this.onUp, required this.onDown, required this.onJump, required this.onLight, required this.onHeavy, required this.theme});

  Widget _btn(String label, Color color, VoidCallback? onTap, {void Function(bool)? onHold}) {
    return GestureDetector(
      onTapDown: onHold != null ? (_) => onHold(true) : null,
      onTapUp: onHold != null ? (_) => onHold(false) : null,
      onTapCancel: onHold != null ? () => onHold(false) : null,
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Center(child: Text(label, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0A0B).withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          _btn('←', Colors.white70, null, onHold: onLeft),
          const SizedBox(width: 8),
          _btn('→', Colors.white70, null, onHold: onRight),
          const SizedBox(width: 8),
          _btn('↑', Colors.white70, null, onHold: onUp),
          const SizedBox(width: 8),
          _btn('↓', Colors.white70, null, onHold: onDown),
        ]),
        Row(children: [
          _btn('⬆', theme.correct, onJump),
          const SizedBox(width: 8),
          _btn('⚔', theme.present, onLight),
          const SizedBox(width: 8),
          _btn('💥', theme.absent, onHeavy),
        ]),
      ]),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────
class _RoguePainter extends CustomPainter {
  final RogueWorld world;
  final double camX, camY;
  final AppTheme theme;
  _RoguePainter({required this.world, required this.camX, required this.camY, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-camX, -camY);

    final level = world.level;
    final ts = tileSize;

    // Visible tile range
    final startCol = max(0, (camX / ts).floor() - 1);
    final endCol   = min(level.cols, ((camX + size.width) / ts).ceil() + 1);
    final startRow = max(0, (camY / ts).floor() - 1);
    final endRow   = min(level.rows, ((camY + size.height) / ts).ceil() + 1);

    // Draw tiles
    final walkableFill = Paint()..color = theme.correct.withValues(alpha: 0.08);
    final walkableEdge = Paint()..color = theme.correct.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (int row = startRow; row < endRow; row++) {
      for (int col = startCol; col < endCol; col++) {
        final tile = level.tileAt(col, row);
        final rx = col * ts, ry = row * ts;
        switch (tile) {
          case Tile.wall:
            canvas.drawRect(Rect.fromLTWH(rx, ry, ts, ts), Paint()..color = const Color(0xFF2A2A2E));
            canvas.drawRect(Rect.fromLTWH(rx + 1, ry + 1, ts - 2, ts - 2), Paint()..color = const Color(0xFF1A1A1E));
          case Tile.floor:
            canvas.drawRect(Rect.fromLTWH(rx, ry, ts, ts), walkableFill);
            canvas.drawRect(Rect.fromLTWH(rx, ry, ts, ts), walkableEdge);
          case Tile.ladder:
            canvas.drawRect(Rect.fromLTWH(rx, ry, ts, ts), walkableFill);
            final rungPaint = Paint()..color = theme.correct.withValues(alpha: 0.6)..strokeWidth = 2;
            canvas.drawLine(Offset(rx + 8, ry), Offset(rx + 8, ry + ts), rungPaint);
            canvas.drawLine(Offset(rx + ts - 8, ry), Offset(rx + ts - 8, ry + ts), rungPaint);
            for (double ry2 = ry + 6; ry2 < ry + ts; ry2 += 8) {
              canvas.drawLine(Offset(rx + 8, ry2), Offset(rx + ts - 8, ry2), rungPaint);
            }
          case Tile.spike:
            canvas.drawRect(Rect.fromLTWH(rx, ry, ts, ts), walkableFill);
            final spikePaint = Paint()..color = Colors.redAccent;
            for (int s = 0; s < 4; s++) {
              final sx = rx + 4 + s * 7.0;
              final path = Path()..moveTo(sx, ry + ts)..lineTo(sx + 3.5, ry + ts - 10)..lineTo(sx + 7, ry + ts)..close();
              canvas.drawPath(path, spikePaint);
            }
          case Tile.door:
            canvas.drawRect(Rect.fromLTWH(rx, ry, ts, ts), walkableFill);
            canvas.drawRect(Rect.fromLTWH(rx + 2, ry + 2, ts - 4, ts - 4), Paint()..color = theme.correct.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 2);
            final tp = TextPainter(text: const TextSpan(text: '🚪', style: TextStyle(fontSize: 20)), textDirection: TextDirection.ltr)..layout();
            tp.paint(canvas, Offset(rx + 6, ry + 6));
          case Tile.empty: break;
        }
      }
    }

    // Room borders
    final borderPaint = Paint()
      ..color = theme.correct.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final room in level.rooms) {
      canvas.drawRect(
        Rect.fromLTWH(room.x * ts, room.y * ts, room.w * ts, room.h * ts),
        borderPaint,
      );
    }

    // Pickups
    for (final pk in world.pickups) {
      final icon = switch(pk.type) {
        WeaponType.sword    => '🗡',
        WeaponType.hammer   => '🔨',
        WeaponType.bow      => '🏹',
        WeaponType.crossbow => '⚙',
      };
      canvas.drawCircle(Offset(pk.x + 12, pk.y + 12), 14, Paint()..color = theme.present.withValues(alpha: 0.2));
      canvas.drawCircle(Offset(pk.x + 12, pk.y + 12), 14, Paint()..color = theme.present..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final tp = TextPainter(text: TextSpan(text: icon, style: const TextStyle(fontSize: 16)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(pk.x + 4, pk.y + 4));
    }

    // Enemies
    for (final e in world.enemies) {
      final color = e.flashFrames > 0 ? Colors.white : switch(e.type) {
        EnemyType.grunt  => theme.absent,
        EnemyType.archer => theme.present,
        EnemyType.brute  => Colors.deepOrange,
      };
      // Body
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(e.x, e.y, e.w, e.h), const Radius.circular(4)), Paint()..color = color);
      // Eyes
      final eyeX = e.facingRight ? e.x + e.w - 7 : e.x + 3;
      canvas.drawCircle(Offset(eyeX, e.y + 8), 3, Paint()..color = Colors.white);
      // HP bar
      final hpFrac = e.hp / e.maxHp;
      canvas.drawRect(Rect.fromLTWH(e.x, e.y - 6, e.w, 3), Paint()..color = Colors.white24);
      canvas.drawRect(Rect.fromLTWH(e.x, e.y - 6, e.w * hpFrac, 3), Paint()..color = Colors.redAccent);
    }

    // Attack hitboxes (debug-style flash)
    for (final hb in world.hitboxes) {
      canvas.drawRect(Rect.fromLTWH(hb.x, hb.y, hb.w, hb.h), Paint()..color = theme.correct.withValues(alpha: 0.25));
    }

    // Projectiles
    for (final proj in world.projectiles) {
      canvas.drawCircle(Offset(proj.x, proj.y), 4, Paint()..color = proj.fromPlayer ? theme.correct : theme.absent);
    }

    // Player
    final p = world.player;
    final flash = p.invincibleFrames > 0 && (p.invincibleFrames % 6 < 3);
    if (!flash) {
      final playerColor = p.state == PlayerState.hurt ? Colors.white : theme.correct;
      // Body
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(p.x, p.y, p.w, p.h), const Radius.circular(4)), Paint()..color = playerColor);
      // Eye
      final eyeX = p.facingRight ? p.x + p.w - 5 : p.x + 3;
      canvas.drawCircle(Offset(eyeX, p.y + 8), 3, Paint()..color = Colors.white);
      // Weapon indicator
      final wColor = p.weapon.ranged ? theme.present : theme.absent;
      canvas.drawRect(Rect.fromLTWH(p.facingRight ? p.x + p.w : p.x - 8, p.y + p.h / 2 - 2, 8, 4), Paint()..color = wColor);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RoguePainter old) => true;
}
