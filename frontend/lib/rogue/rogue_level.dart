// Tile types
enum Tile { empty, wall, floor, ladder, spike, door }

// Weapon types
enum WeaponType { sword, hammer, bow, crossbow }

class Weapon {
  final WeaponType type;
  final String name;
  final int lightDamage;
  final int heavyDamage;
  final bool ranged;
  final double range; // pixels
  const Weapon({required this.type, required this.name, required this.lightDamage, required this.heavyDamage, required this.ranged, required this.range});

  static const sword   = Weapon(type: WeaponType.sword,    name: 'Sword',    lightDamage: 15, heavyDamage: 35, ranged: false, range: 55);
  static const hammer  = Weapon(type: WeaponType.hammer,   name: 'Hammer',   lightDamage: 10, heavyDamage: 60, ranged: false, range: 50);
  static const bow     = Weapon(type: WeaponType.bow,      name: 'Bow',      lightDamage: 20, heavyDamage: 40, ranged: true,  range: 400);
  static const crossbow= Weapon(type: WeaponType.crossbow, name: 'Crossbow', lightDamage: 30, heavyDamage: 30, ranged: true,  range: 500);

  static Weapon fromType(WeaponType t) => switch(t) {
    WeaponType.sword    => sword,
    WeaponType.hammer   => hammer,
    WeaponType.bow      => bow,
    WeaponType.crossbow => crossbow,
  };
}

class RogueLevel {
  final int cols;
  final int rows;
  final List<List<Tile>> tiles;
  final List<EnemySpawn> enemies;
  final List<WeaponPickup> pickups;
  final List<_Rect> rooms;
  final int spawnCol, spawnRow;
  final int exitCol, exitRow;

  const RogueLevel({
    required this.cols, required this.rows,
    required this.tiles, required this.enemies, required this.pickups,
    required this.rooms,
    required this.spawnCol, required this.spawnRow,
    required this.exitCol, required this.exitRow,
  });

  Tile tileAt(int col, int row) {
    if (col < 0 || col >= cols || row < 0 || row >= rows) return Tile.wall;
    return tiles[row][col];
  }

  bool isSolid(int col, int row) {
    final t = tileAt(col, row);
    return t == Tile.wall;
  }

  // Deterministic level generator from a seed string (e.g. date)
  static RogueLevel generate(String seed) {
    final rng = _SeededRng(seed);
    const cols = 60, rows = 30;
    final tiles = List.generate(rows, (_) => List.filled(cols, Tile.wall));

    // Carve rooms using BSP-lite: divide into sections and carve a room in each
    final rooms = <_Rect>[];
    _carveRooms(tiles, rng, 0, 0, cols, rows, rooms);

    // Connect rooms with corridors
    for (int i = 1; i < rooms.length; i++) {
      _connectRooms(tiles, rooms[i - 1], rooms[i], rng);
    }

    // Add ladders between vertically adjacent floor tiles
    _addLadders(tiles, rng, cols, rows);

    // Player spawns in first room center
    final spawn = rooms.first;
    final spawnCol = spawn.cx, spawnRow = spawn.cy;

    // Exit in last room
    final exitRoom = rooms.last;
    final exitCol = exitRoom.cx, exitRow = exitRoom.cy;
    tiles[exitRow][exitCol] = Tile.door;

    // Enemies: 1 per room (skip first and last)
    final enemies = <EnemySpawn>[];
    for (int i = 1; i < rooms.length - 1; i++) {
      final r = rooms[i];
      final type = rng.nextInt(3); // 0=grunt, 1=archer, 2=brute
      enemies.add(EnemySpawn(col: r.cx, row: r.cy, type: EnemyType.values[type]));
    }

    // Weapon pickups: one every 3 rooms
    final pickups = <WeaponPickup>[];
    for (int i = 2; i < rooms.length - 1; i += 3) {
      final r = rooms[i];
      final wt = WeaponType.values[rng.nextInt(WeaponType.values.length)];
      pickups.add(WeaponPickup(col: r.cx + 1, row: r.cy, type: wt));
    }

    return RogueLevel(
      cols: cols, rows: rows, tiles: tiles,
      enemies: enemies, pickups: pickups,
      rooms: rooms,
      spawnCol: spawnCol, spawnRow: spawnRow,
      exitCol: exitCol, exitRow: exitRow,
    );
  }

  static void _carveRooms(List<List<Tile>> tiles, _SeededRng rng, int x, int y, int w, int h, List<_Rect> rooms, [int depth = 0]) {
    const minSize = 7;
    final canSplitH = w >= minSize * 2 + 2;
    final canSplitV = h >= minSize * 2 + 2;

    if (depth >= 4 || (!canSplitH && !canSplitV)) {
      // Carve a room inside this section
      final rw = minSize + rng.nextInt((w - minSize - 2).clamp(1, 8));
      final rh = minSize - 2 + rng.nextInt((h - minSize - 2).clamp(1, 4));
      final rx = x + 1 + rng.nextInt((w - rw - 1).clamp(1, 3));
      final ry = y + 1 + rng.nextInt((h - rh - 1).clamp(1, 3));
      for (int row = ry; row < (ry + rh).clamp(0, tiles.length); row++) {
        for (int col = rx; col < (rx + rw).clamp(0, tiles[0].length); col++) {
          tiles[row][col] = Tile.floor;
        }
      }
      rooms.add(_Rect(rx, ry, rw, rh));
      return;
    }

    if (canSplitH && (!canSplitV || rng.nextBool())) {
      final split = minSize + 1 + rng.nextInt((w - minSize * 2 - 2).clamp(1, w ~/ 2));
      _carveRooms(tiles, rng, x, y, split, h, rooms, depth + 1);
      _carveRooms(tiles, rng, x + split, y, w - split, h, rooms, depth + 1);
    } else {
      final split = minSize + 1 + rng.nextInt((h - minSize * 2 - 2).clamp(1, h ~/ 2));
      _carveRooms(tiles, rng, x, y, w, split, rooms, depth + 1);
      _carveRooms(tiles, rng, x, y + split, w, h - split, rooms, depth + 1);
    }
  }

  static void _connectRooms(List<List<Tile>> tiles, _Rect a, _Rect b, _SeededRng rng) {
    // L-shaped corridor
    int x1 = a.cx, y1 = a.cy, x2 = b.cx, y2 = b.cy;
    // Horizontal then vertical
    final minX = x1 < x2 ? x1 : x2;
    final maxX = x1 < x2 ? x2 : x1;
    for (int x = minX; x <= maxX; x++) {
      if (y1 >= 0 && y1 < tiles.length && x >= 0 && x < tiles[0].length) tiles[y1][x] = Tile.floor;
    }
    final minY = y1 < y2 ? y1 : y2;
    final maxY = y1 < y2 ? y2 : y1;
    for (int y = minY; y <= maxY; y++) {
      if (y >= 0 && y < tiles.length && x2 >= 0 && x2 < tiles[0].length) tiles[y][x2] = Tile.floor;
    }
  }

  static void _addLadders(List<List<Tile>> tiles, _SeededRng rng, int cols, int rows) {
    // Place ladders on floor tiles that have floor above them (multi-level feel)
    for (int row = 2; row < rows - 1; row++) {
      for (int col = 1; col < cols - 1; col++) {
        if (tiles[row][col] == Tile.floor && tiles[row - 1][col] == Tile.floor && rng.nextInt(20) == 0) {
          tiles[row][col] = Tile.ladder;
          tiles[row - 1][col] = Tile.ladder;
        }
      }
    }
  }
}

class RoomRect {
  final int x, y, w, h;
  RoomRect(this.x, this.y, this.w, this.h);
  int get cx => x + w ~/ 2;
  int get cy => y + h ~/ 2;
}

// Keep private alias for internal use
typedef _Rect = RoomRect;

class EnemySpawn {
  final int col, row;
  final EnemyType type;
  const EnemySpawn({required this.col, required this.row, required this.type});
}

enum EnemyType { grunt, archer, brute }

class WeaponPickup {
  final int col, row;
  final WeaponType type;
  const WeaponPickup({required this.col, required this.row, required this.type});
}

// Simple seeded PRNG (xorshift32)
class _SeededRng {
  int _state;
  _SeededRng(String seed) : _state = _hashSeed(seed);

  static int _hashSeed(String s) {
    int h = 0xdeadbeef;
    for (int i = 0; i < s.length; i++) {
      h = ((h ^ s.codeUnitAt(i)) * 2654435761) & 0xFFFFFFFF;
    }
    return h == 0 ? 1 : h;
  }

  int next() {
    _state ^= _state << 13;
    _state ^= (_state >> 17) & 0x7FFF;
    _state ^= _state << 5;
    return _state & 0x7FFFFFFF;
  }

  int nextInt(int max) => max <= 0 ? 0 : next() % max;
  bool nextBool() => next() % 2 == 0;
}
