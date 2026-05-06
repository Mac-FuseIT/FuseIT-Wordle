import 'dart:ui';

enum EnemyType { goomba, koopa, piranha, spiny, buzzyBeetle, hammerBro, boo }

class DashEnemy {
  final EnemyType type;
  double x, y;
  double vx, vy;
  bool alive = true;
  bool inShell = false;
  bool shellMoving = false;
  double animTimer = 0;
  double actionTimer = 0;
  bool facingRight = false;

  static const double width = 32, height = 32;

  DashEnemy({required this.type, required this.x, required this.y})
      : vx = -1.0,
        vy = 0;

  int get points {
    switch (type) {
      case EnemyType.goomba: return 100;
      case EnemyType.koopa: return 200;
      case EnemyType.piranha: return 200;
      case EnemyType.spiny: return 150;
      case EnemyType.buzzyBeetle: return 150;
      case EnemyType.hammerBro: return 300;
      case EnemyType.boo: return 200;
    }
  }

  bool get canBeStopped => type != EnemyType.spiny && type != EnemyType.piranha;
  bool get canBeFireballed => type != EnemyType.buzzyBeetle && type != EnemyType.boo;

  Rect get rect => Rect.fromLTWH(x, y, width, height);
}

class Hammer {
  double x, y, vx, vy;
  Hammer({required this.x, required this.y, required this.vx, required this.vy});
  Rect get rect => Rect.fromLTWH(x - 6, y - 6, 12, 12);
}

class Fireball {
  double x, y, vx, vy;
  bool fromPlayer;
  Fireball({required this.x, required this.y, required this.vx, required this.vy, required this.fromPlayer});
  Rect get rect => Rect.fromLTWH(x - 6, y - 6, 12, 12);
}

class ActiveMovingPlatform {
  double x, y;
  final int tileWidth;
  final String axis;
  final double range;
  final double speed;
  final double originX, originY;
  double dir = 1;

  ActiveMovingPlatform({
    required this.x, required this.y,
    required this.tileWidth, required this.axis,
    required this.range, required this.speed,
  }) : originX = x, originY = y;

  double get pixelWidth => tileWidth * 40.0;
  Rect get rect => Rect.fromLTWH(x, y, pixelWidth, 10);
}
