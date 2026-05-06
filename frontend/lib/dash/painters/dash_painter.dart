import 'package:flutter/material.dart';
import 'dart:math';
import '../models/level.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../../models/app_theme.dart';

class DashPainter extends CustomPainter {
  final DashLevel level;
  final DashPlayer player;
  final List<DashEnemy> enemies;
  final List<Fireball> fireballs;
  final List<Hammer> hammers;
  final List<ActiveMovingPlatform> platforms;
  final List<QuestionBlock> questionBlocks;
  final Set<int> collectedCoins; // encoded as col*1000+row
  final double cameraX;
  final AppTheme theme;
  final int timeBonus;
  final bool gameOver;
  final bool won;
  final bool playerFlash;

  static const double T = 40.0; // tile size
  static const double CW = 1200, CH = 500;

  DashPainter({
    required this.level,
    required this.player,
    required this.enemies,
    required this.fireballs,
    required this.hammers,
    required this.platforms,
    required this.questionBlocks,
    required this.collectedCoins,
    required this.cameraX,
    required this.theme,
    required this.timeBonus,
    required this.gameOver,
    required this.won,
    required this.playerFlash,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / CW;
    final sy = size.height / CH;

    canvas.save();
    canvas.scale(sx, sy);

    _drawBackground(canvas);
    _drawTiles(canvas);
    _drawMovingPlatforms(canvas);
    _drawEnemies(canvas);
    _drawFireballs(canvas);
    _drawHammers(canvas);
    _drawPlayer(canvas);
    _drawHUD(canvas);

    canvas.restore();
  }

  void _drawBackground(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(0, 0, CW, CH),
        Paint()..color = theme.background);
    // Simple sky gradient bands
    final skyColor = theme.correct.withValues(alpha: 0.05);
    canvas.drawRect(const Rect.fromLTWH(0, 0, CW, CH * 0.7), Paint()..color = skyColor);
  }

  void _drawTiles(Canvas canvas) {
    final startCol = (cameraX / T).floor().clamp(0, level.width - 1);
    final endCol = ((cameraX + CW) / T).ceil().clamp(0, level.width);

    for (int row = 0; row < level.height; row++) {
      for (int col = startCol; col < endCol; col++) {
        final id = level.tileAt(col, row);
        if (id == 0) continue;
        final rx = col * T - cameraX;
        final ry = row * T;
        _drawTile(canvas, id, rx, ry, col, row);
      }
    }
  }

  void _drawTile(Canvas canvas, int id, double rx, double ry, int col, int row) {
    final r = Rect.fromLTWH(rx, ry, T, T);
    switch (id) {
      case 1: // ground
        canvas.drawRect(r, Paint()..color = const Color(0xFF8B6914));
        canvas.drawRect(Rect.fromLTWH(rx, ry, T, 4), Paint()..color = const Color(0xFF5A8A3C));
        break;
      case 2: // brick
        canvas.drawRect(r, Paint()..color = theme.absent);
        canvas.drawRect(r, Paint()..color = Colors.black.withValues(alpha: 0.3)..style = PaintingStyle.stroke..strokeWidth = 1);
        break;
      case 3: // question block
        final qb = questionBlocks.firstWhere((q) => q.x == col && q.y == row, orElse: () => QuestionBlock(x: col, y: row, content: 'coin'));
        final color = qb.hit ? theme.absent : theme.correct;
        canvas.drawRect(r, Paint()..color = color);
        final tp = TextPainter(text: TextSpan(text: qb.hit ? '·' : '?', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(rx + T / 2 - tp.width / 2, ry + T / 2 - tp.height / 2));
        break;
      case 4: // solid
        canvas.drawRect(r, Paint()..color = const Color(0xFF555555));
        break;
      case 5: // pipe top
        canvas.drawRect(r, Paint()..color = const Color(0xFF2E7D32));
        canvas.drawRect(Rect.fromLTWH(rx - 2, ry, T + 4, 8), Paint()..color = const Color(0xFF1B5E20));
        break;
      case 6: // pipe body
        canvas.drawRect(r, Paint()..color = const Color(0xFF388E3C));
        canvas.drawRect(Rect.fromLTWH(rx + 4, ry, 4, T), Paint()..color = const Color(0xFF1B5E20).withValues(alpha: 0.5));
        break;
      case 7: // coin
        final coinKey = col * 1000 + row;
        if (!collectedCoins.contains(coinKey)) {
          canvas.drawCircle(Offset(rx + T / 2, ry + T / 2), 8, Paint()..color = theme.present);
          canvas.drawCircle(Offset(rx + T / 2, ry + T / 2), 5, Paint()..color = theme.present.withValues(alpha: 0.5));
        }
        break;
      case 8: // platform
        canvas.drawRect(Rect.fromLTWH(rx, ry, T, 10), Paint()..color = const Color(0xFF795548));
        break;
      case 9: // spike
        final path = Path()
          ..moveTo(rx + T / 2, ry)
          ..lineTo(rx + T, ry + T)
          ..lineTo(rx, ry + T)
          ..close();
        canvas.drawPath(path, Paint()..color = Colors.grey.shade400);
        break;
      case 10: // lava
        canvas.drawRect(r, Paint()..color = const Color(0xFFFF3D00));
        canvas.drawRect(Rect.fromLTWH(rx, ry, T, 6), Paint()..color = const Color(0xFFFF6D00));
        break;
      case 11: // flag pole
        canvas.drawRect(Rect.fromLTWH(rx + T / 2 - 2, ry, 4, T), Paint()..color = Colors.grey);
        final flag = Path()
          ..moveTo(rx + T / 2 + 2, ry + 4)
          ..lineTo(rx + T / 2 + 18, ry + 12)
          ..lineTo(rx + T / 2 + 2, ry + 20)
          ..close();
        canvas.drawPath(flag, Paint()..color = theme.correct);
        break;
      case 13: // spring
        canvas.drawRect(Rect.fromLTWH(rx + 4, ry + T - 12, T - 8, 12), Paint()..color = Colors.orange);
        canvas.drawRect(Rect.fromLTWH(rx + 8, ry + T - 20, T - 16, 10), Paint()..color = Colors.orange.shade300);
        break;
      case 14: // ice
        canvas.drawRect(r, Paint()..color = const Color(0xFF80DEEA).withValues(alpha: 0.7));
        canvas.drawRect(r, Paint()..color = Colors.white.withValues(alpha: 0.2)..style = PaintingStyle.stroke..strokeWidth = 1);
        break;
    }
  }

  void _drawMovingPlatforms(Canvas canvas) {
    for (final p in platforms) {
      final rx = p.x - cameraX;
      canvas.drawRect(Rect.fromLTWH(rx, p.y, p.pixelWidth, 10), Paint()..color = const Color(0xFF795548));
      canvas.drawRect(Rect.fromLTWH(rx, p.y, p.pixelWidth, 4), Paint()..color = const Color(0xFFA1887F));
    }
  }

  void _drawEnemies(Canvas canvas) {
    for (final e in enemies) {
      if (!e.alive) continue;
      final ex = e.x - cameraX;
      final ey = e.y;
      _drawEnemy(canvas, e, ex, ey);
    }
  }

  void _drawEnemy(Canvas canvas, DashEnemy e, double ex, double ey) {
    if (e.inShell) {
      canvas.drawOval(Rect.fromLTWH(ex, ey + 8, 32, 24), Paint()..color = const Color(0xFF4CAF50));
      return;
    }
    switch (e.type) {
      case EnemyType.goomba:
        canvas.drawOval(Rect.fromLTWH(ex, ey + 8, 32, 24), Paint()..color = const Color(0xFF8D6E63));
        canvas.drawOval(Rect.fromLTWH(ex + 4, ey, 24, 20), Paint()..color = const Color(0xFF6D4C41));
        canvas.drawCircle(Offset(ex + 10, ey + 8), 3, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(ex + 22, ey + 8), 3, Paint()..color = Colors.white);
        break;
      case EnemyType.koopa:
        canvas.drawOval(Rect.fromLTWH(ex + 4, ey + 4, 24, 28), Paint()..color = const Color(0xFF4CAF50));
        canvas.drawOval(Rect.fromLTWH(ex + 8, ey, 16, 16), Paint()..color = const Color(0xFFFFF176));
        break;
      case EnemyType.piranha:
        canvas.drawOval(Rect.fromLTWH(ex + 4, ey, 24, 28), Paint()..color = const Color(0xFFE53935));
        canvas.drawRect(Rect.fromLTWH(ex + 2, ey + 20, 28, 8), Paint()..color = Colors.white);
        for (int i = 0; i < 4; i++) {
          canvas.drawRect(Rect.fromLTWH(ex + 4 + i * 7.0, ey + 18, 4, 6), Paint()..color = Colors.white);
        }
        break;
      case EnemyType.spiny:
        canvas.drawOval(Rect.fromLTWH(ex + 4, ey + 8, 24, 20), Paint()..color = const Color(0xFFE53935));
        for (int i = 0; i < 5; i++) {
          final sx2 = ex + 6 + i * 5.0;
          canvas.drawRect(Rect.fromLTWH(sx2, ey + 4, 3, 8), Paint()..color = Colors.red.shade900);
        }
        break;
      case EnemyType.buzzyBeetle:
        canvas.drawOval(Rect.fromLTWH(ex + 2, ey + 4, 28, 26), Paint()..color = const Color(0xFF37474F));
        canvas.drawOval(Rect.fromLTWH(ex + 6, ey, 20, 16), Paint()..color = const Color(0xFF546E7A));
        break;
      case EnemyType.hammerBro:
        canvas.drawRect(Rect.fromLTWH(ex + 4, ey + 8, 24, 24), Paint()..color = const Color(0xFF4CAF50));
        canvas.drawOval(Rect.fromLTWH(ex + 6, ey, 20, 18), Paint()..color = const Color(0xFFFFF176));
        // hammer
        canvas.drawRect(Rect.fromLTWH(ex + 22, ey + 2, 12, 6), Paint()..color = const Color(0xFF795548));
        canvas.drawRect(Rect.fromLTWH(ex + 28, ey - 2, 6, 14), Paint()..color = const Color(0xFF5D4037));
        break;
      case EnemyType.boo:
        canvas.drawOval(Rect.fromLTWH(ex + 2, ey + 2, 28, 26), Paint()..color = Colors.white.withValues(alpha: 0.85));
        canvas.drawCircle(Offset(ex + 11, ey + 12), 4, Paint()..color = Colors.black);
        canvas.drawCircle(Offset(ex + 21, ey + 12), 4, Paint()..color = Colors.black);
        final mouthPath = Path()
          ..moveTo(ex + 8, ey + 20)
          ..quadraticBezierTo(ex + 16, ey + 28, ex + 24, ey + 20);
        canvas.drawPath(mouthPath, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
        break;
    }
  }

  void _drawFireballs(Canvas canvas) {
    for (final f in fireballs) {
      canvas.drawCircle(Offset(f.x - cameraX, f.y), 6, Paint()..color = Colors.orange);
      canvas.drawCircle(Offset(f.x - cameraX, f.y), 3, Paint()..color = Colors.yellow);
    }
  }

  void _drawHammers(Canvas canvas) {
    for (final h in hammers) {
      canvas.drawRect(Rect.fromLTWH(h.x - cameraX - 6, h.y - 6, 12, 12), Paint()..color = const Color(0xFF795548));
    }
  }

  void _drawPlayer(Canvas canvas) {
    if (playerFlash) return;
    final px = player.x - cameraX;
    final py = player.y;
    final color = player.starActive ? theme.present : theme.correct;

    // Body
    canvas.drawRect(Rect.fromLTWH(px + 4, py + 16, 24, 24), Paint()..color = color);
    // Head
    canvas.drawOval(Rect.fromLTWH(px + 6, py, 20, 20), Paint()..color = color.withValues(alpha: 0.9));
    // Eyes
    final eyeX = player.facingRight ? px + 20 : px + 8;
    canvas.drawCircle(Offset(eyeX, py + 8), 3, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(eyeX + (player.facingRight ? 1 : -1), py + 9), 1.5, Paint()..color = Colors.black);
    // Cap
    canvas.drawRect(Rect.fromLTWH(px + 4, py + 2, 24, 6), Paint()..color = color.withValues(alpha: 0.7));
    if (player.big) {
      canvas.drawRect(Rect.fromLTWH(px + 2, py - 4, 28, 8), Paint()..color = color.withValues(alpha: 0.5));
    }
  }

  void _drawHUD(Canvas canvas) {
    // Lives
    _drawText(canvas, '❤️ ${player.lives}', 12, 8, Colors.white, 16);
    // Score
    _drawText(canvas, '⭐ ${player.score}', CW / 2 - 40, 8, theme.correct, 16);
    // Coins
    _drawText(canvas, '🪙 ${player.coins}', CW / 2 + 40, 8, theme.present, 16);
    // Time bonus
    _drawText(canvas, '⏱ $timeBonus', CW - 80, 8, Colors.white70, 16);
  }

  void _drawText(Canvas canvas, String text, double x, double y, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant DashPainter old) => true;
}
