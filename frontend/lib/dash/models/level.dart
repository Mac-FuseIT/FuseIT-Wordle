class DashLevel {
  final int width;
  final int height;
  final List<List<int>> tiles;
  final List<EnemySpawn> enemies;
  final List<MovingPlatform> movingPlatforms;
  final List<WarpPipe> warpPipes;
  final List<QuestionBlock> questionBlocks;
  final String zoneName;

  const DashLevel({
    required this.width,
    required this.height,
    required this.tiles,
    required this.enemies,
    required this.movingPlatforms,
    required this.warpPipes,
    required this.questionBlocks,
    required this.zoneName,
  });

  factory DashLevel.fromJson(Map<String, dynamic> j) => DashLevel(
        width: j['width'] as int,
        height: j['height'] as int,
        tiles: (j['tiles'] as List).map((row) => List<int>.from(row as List)).toList(),
        enemies: (j['enemies'] as List? ?? []).map((e) => EnemySpawn.fromJson(e as Map<String, dynamic>)).toList(),
        movingPlatforms: (j['movingPlatforms'] as List? ?? []).map((e) => MovingPlatform.fromJson(e as Map<String, dynamic>)).toList(),
        warpPipes: (j['warpPipes'] as List? ?? []).map((e) => WarpPipe.fromJson(e as Map<String, dynamic>)).toList(),
        questionBlocks: (j['questionBlocks'] as List? ?? []).map((e) => QuestionBlock.fromJson(e as Map<String, dynamic>)).toList(),
        zoneName: j['zoneName'] as String? ?? 'grassland',
      );

  int tileAt(int col, int row) {
    if (row < 0 || row >= height || col < 0 || col >= width) return 4;
    return tiles[row][col];
  }
}

class EnemySpawn {
  final String type;
  final int x, y;
  const EnemySpawn({required this.type, required this.x, required this.y});
  factory EnemySpawn.fromJson(Map<String, dynamic> j) =>
      EnemySpawn(type: j['type'] as String, x: j['x'] as int, y: j['y'] as int);
}

class MovingPlatform {
  final int x, y, width;
  final String axis;
  final int range;
  final double speed;
  const MovingPlatform({required this.x, required this.y, required this.width, required this.axis, required this.range, required this.speed});
  factory MovingPlatform.fromJson(Map<String, dynamic> j) => MovingPlatform(
        x: j['x'] as int, y: j['y'] as int, width: j['width'] as int,
        axis: j['axis'] as String? ?? 'x',
        range: j['range'] as int? ?? 4,
        speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
      );
}

class WarpPipe {
  final int entranceX, entranceY, exitX, exitY;
  const WarpPipe({required this.entranceX, required this.entranceY, required this.exitX, required this.exitY});
  factory WarpPipe.fromJson(Map<String, dynamic> j) {
    final en = j['entrance'] as Map<String, dynamic>;
    final ex = j['exit'] as Map<String, dynamic>;
    return WarpPipe(entranceX: en['x'] as int, entranceY: en['y'] as int, exitX: ex['x'] as int, exitY: ex['y'] as int);
  }
}

class QuestionBlock {
  final int x, y;
  final String content;
  bool hit;
  QuestionBlock({required this.x, required this.y, required this.content, this.hit = false});
  factory QuestionBlock.fromJson(Map<String, dynamic> j) =>
      QuestionBlock(x: j['x'] as int, y: j['y'] as int, content: j['content'] as String? ?? 'coin');
}
