import 'dart:ui';

class DashPlayer {
  static const double width = 32, height = 40;
  static const double speed = 4, jumpVelocity = -12, gravity = 0.5;
  static const double maxFallSpeed = 14;

  double x, y;
  double vx = 0, vy = 0;
  bool onGround = false;
  bool facingRight = true;
  int lives;
  int score;
  int coins;
  bool invincible = false;
  double invincibleTimer = 0;
  bool big = false;
  bool hasFire = false;
  bool starActive = false;
  double starTimer = 0;

  DashPlayer({required this.x, required this.y, this.lives = 3, this.score = 0, this.coins = 0});

  void applyGravity() {
    vy = (vy + gravity).clamp(-30, maxFallSpeed);
  }

  void jump() {
    if (onGround) {
      vy = jumpVelocity;
      onGround = false;
    }
  }

  void springJump() {
    vy = jumpVelocity * 2;
    onGround = false;
  }

  Rect get rect => Rect.fromLTWH(x, y, width, height);
}
