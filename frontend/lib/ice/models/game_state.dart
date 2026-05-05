class IceSession {
  final String sessionId;
  final Map<String, dynamic> settings;
  final String status;
  final String createdAt;

  IceSession({
    required this.sessionId,
    required this.settings,
    required this.status,
    required this.createdAt,
  });

  factory IceSession.fromJson(Map<String, dynamic> json) {
    return IceSession(
      sessionId: json['session_id'],
      settings: json['settings'],
      status: json['status'],
      createdAt: json['created_at'],
    );
  }
}

class GameState {
  final Puck puck;
  final List<Paddle> paddles;
  final Score score;
  final int round;
  final String status;

  GameState({
    required this.puck,
    required this.paddles,
    required this.score,
    required this.round,
    required this.status,
  });

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      puck: Puck.fromJson(json['puck']),
      paddles: (json['paddles'] as List).map((p) => Paddle.fromJson(p)).toList(),
      score: Score.fromJson(json['score']),
      round: json['round'],
      status: json['status'],
    );
  }
}

class Puck {
  final double x, y, vx, vy;
  Puck({required this.x, required this.y, required this.vx, required this.vy});
  factory Puck.fromJson(Map<String, dynamic> json) =>
      Puck(x: json['x'].toDouble(), y: json['y'].toDouble(), vx: json['vx'].toDouble(), vy: json['vy'].toDouble());
}

class Paddle {
  final double x, y;
  final int team;
  Paddle({required this.x, required this.y, required this.team});
  factory Paddle.fromJson(Map<String, dynamic> json) =>
      Paddle(x: json['x'].toDouble(), y: json['y'].toDouble(), team: json['team']);
}

class Score {
  final int team1, team2;
  Score({required this.team1, required this.team2});
  factory Score.fromJson(Map<String, dynamic> json) =>
      Score(team1: json['team1'], team2: json['team2']);
}
