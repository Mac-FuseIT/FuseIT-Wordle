class GameState {
  final String date;
  final int wordLength;
  final int maxAttempts;
  final List<GuessResult> guesses;
  final bool completed;
  final bool solved;
  final String? answer;

  GameState({
    required this.date,
    required this.wordLength,
    required this.maxAttempts,
    this.guesses = const [],
    this.completed = false,
    this.solved = false,
    this.answer,
  });
}

class GuessResult {
  final String guess;
  final List<LetterResult> result;

  GuessResult({required this.guess, required this.result});

  factory GuessResult.fromJson(Map<String, dynamic> json) {
    return GuessResult(
      guess: json['guess'],
      result: (json['result'] as List).map((r) => LetterResult.fromJson(r)).toList(),
    );
  }
}

class LetterResult {
  final String letter;
  final String status; // 'correct', 'present', 'absent'

  LetterResult({required this.letter, required this.status});

  factory LetterResult.fromJson(Map<String, dynamic> json) {
    return LetterResult(letter: json['letter'], status: json['status']);
  }
}

class LeaderboardEntry {
  final String name;
  final int numGuesses;
  final bool? solved;
  final int? totalGuesses;
  final int? daysPlayed;
  final String? email;

  LeaderboardEntry({required this.name, required this.numGuesses, this.solved, this.totalGuesses, this.daysPlayed, this.email});

  factory LeaderboardEntry.fromJsonDaily(Map<String, dynamic> json) {
    return LeaderboardEntry(
      name: json['name'],
      numGuesses: json['numGuesses'],
      solved: json['solved'] == 1 || json['solved'] == true,
    );
  }

  factory LeaderboardEntry.fromJsonMonthly(Map<String, dynamic> json) {
    return LeaderboardEntry(
      name: json['name'],
      numGuesses: json['totalGuesses'],
      totalGuesses: json['totalGuesses'],
      daysPlayed: json['daysPlayed'],
      email: json['email'],
    );
  }
}
