import 'dart:math';
import 'rogue_level.dart';

const double tileSize = 32.0;
const double gravity = 0.5;
const double jumpVel = -11.0;
const double moveSpeed = 3.5;

// ─── Projectile ───────────────────────────────────────────────────────────────
class Projectile {
  double x, y, vx, vy;
  final int damage;
  final bool fromPlayer;
  bool dead = false;
  Projectile({required this.x, required this.y, required this.vx, required this.vy, required this.damage, required this.fromPlayer});
}

// ─── Attack hitbox ────────────────────────────────────────────────────────────
class AttackHitbox {
  double x, y, w, h;
  final int damage;
  int framesLeft;
  AttackHitbox({required this.x, required this.y, required this.w, required this.h, required this.damage, required this.framesLeft});
}

// ─── Enemy ────────────────────────────────────────────────────────────────────
class RogueEnemy {
  double x, y;
  double vx = 0, vy = 0;
  int hp;
  final int maxHp;
  final EnemyType type;
  bool onGround = false;
  bool facingRight = true;
  bool dead = false;
  int flashFrames = 0;
  double aiTimer = 0;
  double shootTimer = 0;

  RogueEnemy({required this.x, required this.y, required this.type})
      : hp = _maxHp(type), maxHp = _maxHp(type);

  static int _maxHp(EnemyType t) => switch(t) {
    EnemyType.grunt  => 40,
    EnemyType.archer => 30,
    EnemyType.brute  => 100,
  };

  double get w => type == EnemyType.brute ? 28 : 20;
  double get h => type == EnemyType.brute ? 40 : 32;
}

// ─── Pickup ───────────────────────────────────────────────────────────────────
class ActivePickup {
  double x, y;
  final WeaponType type;
  bool collected = false;
  ActivePickup({required this.x, required this.y, required this.type});
}

// ─── Player ───────────────────────────────────────────────────────────────────
enum PlayerState { idle, run, jump, crouch, attack, hurt, dead }

class RoguePlayer {
  double x, y;
  double vx = 0, vy = 0;
  bool onGround = false;
  bool onLadder = false;
  bool facingRight = true;
  bool crouching = false;
  PlayerState state = PlayerState.idle;
  int hp = 100;
  int maxHp = 100;
  int invincibleFrames = 0;
  int attackFrames = 0;
  int heavyAttackFrames = 0;
  Weapon weapon = Weapon.sword;

  double get w => 20.0;
  double get h => crouching ? 20.0 : 32.0;

  RoguePlayer({required this.x, required this.y});
}

// ─── Game World ───────────────────────────────────────────────────────────────
class RogueWorld {
  final RogueLevel level;
  final RoguePlayer player;
  final List<RogueEnemy> enemies;
  final List<ActivePickup> pickups;
  final List<Projectile> projectiles;
  final List<AttackHitbox> hitboxes;
  bool levelComplete = false;
  bool gameOver = false;
  int frameCount = 0;

  RogueWorld({required this.level, required this.player, required this.enemies, required this.pickups})
      : projectiles = [], hitboxes = [];

  static RogueWorld fromLevel(RogueLevel lvl) {
    final px = lvl.spawnCol * tileSize;
    final py = (lvl.spawnRow - 1) * tileSize;
    final player = RoguePlayer(x: px, y: py);

    final enemies = lvl.enemies.map((e) => RogueEnemy(
      x: e.col * tileSize,
      y: (e.row - 1) * tileSize,
      type: e.type,
    )).toList();

    final pickups = lvl.pickups.map((p) => ActivePickup(
      x: p.col * tileSize,
      y: (p.row - 1) * tileSize,
      type: p.type,
    )).toList();

    return RogueWorld(level: lvl, player: player, enemies: enemies, pickups: pickups);
  }

  void tick({
    required bool leftDown, required bool rightDown,
    required bool upDown, required bool downDown,
    required bool jumpPressed, // single-frame
  }) {
    if (gameOver || levelComplete) return;
    frameCount++;
    _updatePlayer(leftDown: leftDown, rightDown: rightDown, upDown: upDown, downDown: downDown, jumpPressed: jumpPressed);
    _updateEnemies();
    _updateProjectiles();
    _resolveHitboxes();
    _checkPickups();
    _checkExit();
  }

  // ── Player physics ──────────────────────────────────────────────────────────
  void _updatePlayer({required bool leftDown, required bool rightDown, required bool upDown, required bool downDown, required bool jumpPressed}) {
    final p = player;
    if (p.invincibleFrames > 0) p.invincibleFrames--;
    if (p.attackFrames > 0) p.attackFrames--;
    if (p.heavyAttackFrames > 0) p.heavyAttackFrames--;

    p.crouching = downDown && p.onGround;

    // Ladder
    final midCol = ((p.x + p.w / 2) / tileSize).floor();
    final midRow = ((p.y + p.h / 2) / tileSize).floor();
    final onLadderTile = level.tileAt(midCol, midRow) == Tile.ladder;
    if (onLadderTile && (upDown || downDown)) {
      p.onLadder = true;
      p.vy = upDown ? -2.5 : 2.5;
      p.vx = 0;
    } else if (!onLadderTile) {
      p.onLadder = false;
    }

    if (!p.onLadder) {
      // Horizontal
      if (!p.crouching) {
        if (leftDown)  { p.vx = -moveSpeed; p.facingRight = false; }
        else if (rightDown) { p.vx = moveSpeed; p.facingRight = true; }
        else p.vx = 0;
      } else {
        p.vx = 0;
      }
      // Jump
      if (jumpPressed && p.onGround) p.vy = jumpVel;
      // Gravity
      p.vy = (p.vy + gravity).clamp(-20.0, 20.0);
    }

    _moveEntity(p.x, p.y, p.vx, p.vy, p.w, p.h, (nx, ny, onGround) {
      p.x = nx; p.y = ny; p.onGround = onGround;
      if (onGround) p.vy = 0;
    });

    // State
    if (p.attackFrames > 0 || p.heavyAttackFrames > 0) p.state = PlayerState.attack;
    else if (!p.onGround && !p.onLadder) p.state = PlayerState.jump;
    else if (p.crouching) p.state = PlayerState.crouch;
    else if (p.vx.abs() > 0.1) p.state = PlayerState.run;
    else p.state = PlayerState.idle;

    // Spike damage
    final footCol = ((p.x + p.w / 2) / tileSize).floor();
    final footRow = ((p.y + p.h) / tileSize).floor();
    if (level.tileAt(footCol, footRow) == Tile.spike && p.invincibleFrames == 0) {
      _hurtPlayer(10);
    }
  }

  void _hurtPlayer(int dmg) {
    if (player.invincibleFrames > 0) return;
    player.hp -= dmg;
    player.invincibleFrames = 60;
    if (player.hp <= 0) { player.hp = 0; player.state = PlayerState.dead; gameOver = true; }
  }

  // ── Enemy AI ────────────────────────────────────────────────────────────────
  void _updateEnemies() {
    final p = player;
    for (final e in enemies) {
      if (e.dead) continue;
      if (e.flashFrames > 0) e.flashFrames--;

      final dx = p.x - e.x;
      e.facingRight = dx > 0;
      final dist = dx.abs();

      e.aiTimer++;
      e.vy = (e.vy + gravity).clamp(-20.0, 20.0);

      switch (e.type) {
        case EnemyType.grunt:
          // Walk toward player
          if (dist < 300) e.vx = e.facingRight ? 2.0 : -2.0;
          else e.vx = 0;
          // Melee damage
          if (dist < 30 && (p.y - e.y).abs() < 30 && p.invincibleFrames == 0) _hurtPlayer(8);

        case EnemyType.archer:
          e.vx = 0;
          e.shootTimer++;
          if (dist < 350 && e.shootTimer >= 90) {
            e.shootTimer = 0;
            final angle = atan2((p.y + p.h / 2) - (e.y + e.h / 2), dx);
            projectiles.add(Projectile(x: e.x + e.w / 2, y: e.y + e.h / 2, vx: cos(angle) * 5, vy: sin(angle) * 5, damage: 12, fromPlayer: false));
          }

        case EnemyType.brute:
          if (dist < 200) e.vx = e.facingRight ? 1.5 : -1.5;
          else e.vx = 0;
          if (e.onGround && dist < 60 && e.aiTimer % 80 == 0) e.vy = jumpVel * 0.8;
          if (dist < 40 && (p.y - e.y).abs() < 40 && p.invincibleFrames == 0) _hurtPlayer(20);
      }

      _moveEntity(e.x, e.y, e.vx, e.vy, e.w, e.h, (nx, ny, onGround) {
        e.x = nx; e.y = ny; e.onGround = onGround;
        if (onGround) e.vy = 0;
      });
    }
    enemies.removeWhere((e) => e.dead);
  }

  // ── Projectiles ─────────────────────────────────────────────────────────────
  void _updateProjectiles() {
    final p = player;
    for (final proj in projectiles) {
      proj.x += proj.vx;
      proj.y += proj.vy;
      final col = (proj.x / tileSize).floor();
      final row = (proj.y / tileSize).floor();
      if (level.isSolid(col, row)) { proj.dead = true; continue; }

      if (proj.fromPlayer) {
        for (final e in enemies) {
          if (e.dead) continue;
          if (_overlaps(proj.x, proj.y, 6, 6, e.x, e.y, e.w, e.h)) {
            _damageEnemy(e, proj.damage);
            proj.dead = true;
          }
        }
      } else {
        if (_overlaps(proj.x, proj.y, 6, 6, p.x, p.y, p.w, p.h)) {
          _hurtPlayer(proj.damage);
          proj.dead = true;
        }
      }
    }
    projectiles.removeWhere((p) => p.dead);
  }

  // ── Hitboxes ─────────────────────────────────────────────────────────────────
  void _resolveHitboxes() {
    for (final hb in hitboxes) {
      hb.framesLeft--;
      for (final e in enemies) {
        if (e.dead) continue;
        if (_overlaps(hb.x, hb.y, hb.w, hb.h, e.x, e.y, e.w, e.h)) {
          _damageEnemy(e, hb.damage);
        }
      }
    }
    hitboxes.removeWhere((hb) => hb.framesLeft <= 0);
  }

  void _damageEnemy(RogueEnemy e, int dmg) {
    e.hp -= dmg;
    e.flashFrames = 8;
    if (e.hp <= 0) e.dead = true;
  }

  // ── Pickups ──────────────────────────────────────────────────────────────────
  void _checkPickups() {
    final p = player;
    for (final pk in pickups) {
      if (pk.collected) continue;
      if (_overlaps(p.x, p.y, p.w, p.h, pk.x, pk.y, 24, 24)) {
        pk.collected = true;
        p.weapon = Weapon.fromType(pk.type);
      }
    }
    pickups.removeWhere((pk) => pk.collected);
  }

  // ── Exit ─────────────────────────────────────────────────────────────────────
  void _checkExit() {
    final p = player;
    final col = ((p.x + p.w / 2) / tileSize).floor();
    final row = ((p.y + p.h / 2) / tileSize).floor();
    if (level.tileAt(col, row) == Tile.door && enemies.isEmpty) levelComplete = true;
  }

  // ── Combat actions ───────────────────────────────────────────────────────────
  void lightAttack() {
    if (player.attackFrames > 0 || player.heavyAttackFrames > 0) return;
    final w = player.weapon;
    player.attackFrames = 12;
    if (w.ranged) {
      _fireProjectile(w.lightDamage);
    } else {
      _spawnMeleeHitbox(w.lightDamage, w.range, 8);
    }
  }

  void heavyAttack() {
    if (player.attackFrames > 0 || player.heavyAttackFrames > 0) return;
    final w = player.weapon;
    player.heavyAttackFrames = 20;
    if (w.ranged) {
      _fireProjectile(w.heavyDamage);
    } else {
      _spawnMeleeHitbox(w.heavyDamage, w.range * 1.2, 14);
    }
  }

  void _fireProjectile(int damage) {
    final p = player;
    final vx = p.facingRight ? 9.0 : -9.0;
    projectiles.add(Projectile(x: p.x + p.w / 2, y: p.y + p.h / 2, vx: vx, vy: 0, damage: damage, fromPlayer: true));
  }

  void _spawnMeleeHitbox(int damage, double range, int frames) {
    final p = player;
    final hx = p.facingRight ? p.x + p.w : p.x - range;
    hitboxes.add(AttackHitbox(x: hx, y: p.y, w: range, h: p.h, damage: damage, framesLeft: frames));
  }

  // ── Collision helper ─────────────────────────────────────────────────────────
  void _moveEntity(double x, double y, double vx, double vy, double w, double h, void Function(double nx, double ny, bool onGround) done) {
    // Move X
    double nx = x + vx;
    final leftCol  = (nx / tileSize).floor();
    final rightCol = ((nx + w - 1) / tileSize).floor();
    final topRow   = (y / tileSize).floor();
    final botRow   = ((y + h - 1) / tileSize).floor();
    if (vx < 0 && (level.isSolid(leftCol, topRow) || level.isSolid(leftCol, botRow))) {
      nx = (leftCol + 1) * tileSize.toDouble();
    } else if (vx > 0 && (level.isSolid(rightCol, topRow) || level.isSolid(rightCol, botRow))) {
      nx = rightCol * tileSize - w;
    }

    // Move Y
    double ny = y + vy;
    bool onGround = false;
    final lCol = (nx / tileSize).floor();
    final rCol = ((nx + w - 1) / tileSize).floor();
    if (vy < 0) {
      final topR = (ny / tileSize).floor();
      if (level.isSolid(lCol, topR) || level.isSolid(rCol, topR)) {
        ny = (topR + 1) * tileSize.toDouble();
      }
    } else if (vy >= 0) {
      final botR = ((ny + h) / tileSize).floor();
      if (level.isSolid(lCol, botR) || level.isSolid(rCol, botR)) {
        ny = botR * tileSize - h;
        onGround = true;
      }
    }

    done(nx, ny, onGround);
  }

  bool _overlaps(double ax, double ay, double aw, double ah, double bx, double by, double bw, double bh) =>
      ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}
