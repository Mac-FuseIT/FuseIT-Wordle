import 'dart:async';
import 'dart:math';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:chess/chess.dart' as chess;

/// Chess engine service that communicates with Stockfish.js via a Web Worker.
///
/// The worker file (`stockfish_worker.js`) must be present in the web root.
///
/// Usage:
///   final engine = ChessEngine();
///   await engine.init();
///   final bestMove = await engine.getBestMove(fen, eloLevel);
///   engine.dispose();
class ChessEngine {
  web.Worker? _worker;

  /// Completer resolved once the engine sends 'readyok' during [init].
  Completer<void>? _readyCompleter;

  /// Completer resolved when the engine replies with a 'bestmove' line.
  Completer<String>? _moveCompleter;

  bool _ready = false;
  bool _disposed = false;

  final Random _rng = Random();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Spawns the Stockfish Web Worker and performs the UCI handshake.
  ///
  /// The handshake sequence is:
  ///   1. Engine starts → we send 'uci'
  ///   2. Engine replies 'uciok' → we send 'isready'
  ///   3. Engine replies 'readyok' → init complete
  Future<void> init() async {
    // The hash tells the Stockfish engine where to find its WASM file.
    // When stockfish-18-lite-single.js runs inside the worker via importScripts,
    // it reads self.location.hash to locate the WASM:
    //   e = self.location.hash.substr(1).split(",")
    //   a = decodeURIComponent(e[0] || fallback)
    // Passing the path here avoids copying the WASM to the web root.
    _worker = web.Worker(
      'stockfish_worker.js#stockfish/stockfish-18-lite-single.wasm'.toJS,
    );
    _readyCompleter = Completer<void>();

    _worker!.onmessage = (web.MessageEvent event) {
      final data = event.data;
      if (data == null) {
        print('[ChessEngine] onmessage: data is null');
        return;
      }
      final line = '$data';
      print('[ChessEngine] received: "$line" (length=${line.length})');
      if (line.isEmpty || line == 'null') return;
      _onMessage(line);
    }.toJS;

    // Kick off UCI handshake AFTER onmessage is attached so no reply is missed.
    _sendCommand('uci');

    await _readyCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        print('[ChessEngine] TIMEOUT: engine did not respond in 15s');
        _readyCompleter = null;
      },
    );

    _ready = true;
    print('[ChessEngine] init complete, ready=$_ready');
  }

  /// Returns the best UCI move string (e.g. `'e2e4'`, `'e7e8q'`) for [fen]
  /// at the given [eloLevel].
  ///
  /// Returns an empty string if the engine is not ready, has been disposed,
  /// or times out.
  Future<String> getBestMove(String fen, int eloLevel) async {
    if (!_ready || _disposed) return '';

    _configureElo(eloLevel);
    _sendCommand('position fen $fen');

    final moveTime = _getMoveTime(eloLevel);
    _moveCompleter = Completer<String>();
    _sendCommand('go movetime $moveTime');

    return _moveCompleter!.future.timeout(
      Duration(milliseconds: moveTime + 5000),
      onTimeout: () => '',
    );
  }

  /// Returns a move for amateur mode. Uses a mix of random moves and
  /// Stockfish's best move (at Skill Level 0) based on the ELO level.
  ///
  /// Random move probability:
  ///   100 ELO: 80% random
  ///   200 ELO: 70% random
  ///   300 ELO: 60% random
  ///   400 ELO: 50% random
  ///   500 ELO: 40% random
  ///   600 ELO: 30% random
  ///   700 ELO: 25% random
  ///   800 ELO: 18% random
  ///   900 ELO: 15% random
  Future<String> getBestMoveAmateur(String fen, int eloLevel) async {
    if (!_ready || _disposed) return '';

    // Calculate random move probability based on ELO
    final randomChance = _getRandomChance(eloLevel);

    // Get all legal moves from the current position
    final game = chess.Chess.fromFEN(fen);
    final legalMoves = game.moves({'verbose': true});

    if (legalMoves.isEmpty) return '';

    // Roll the dice: pick random move or ask Stockfish
    if (_rng.nextDouble() < randomChance) {
      // Pick a random legal move, return as UCI format
      final randomMove = legalMoves[_rng.nextInt(legalMoves.length)];
      final from = randomMove['from'] as String;
      final to = randomMove['to'] as String;
      final promotion = randomMove['promotion'] as String?;
      return '$from$to${promotion ?? ''}';
    }

    // Use Stockfish at Skill Level 0 for a weak but not random move
    _configureElo(0);
    _sendCommand('position fen $fen');
    _moveCompleter = Completer<String>();
    _sendCommand('go movetime 200');

    return _moveCompleter!.future.timeout(
      const Duration(milliseconds: 5200),
      onTimeout: () {
        // Fallback to random move on timeout
        final randomMove = legalMoves[_rng.nextInt(legalMoves.length)];
        final from = randomMove['from'] as String;
        final to = randomMove['to'] as String;
        final promotion = randomMove['promotion'] as String?;
        return '$from$to${promotion ?? ''}';
      },
    );
  }

  /// Terminates the Web Worker and releases resources.
  void dispose() {
    _disposed = true;
    _worker?.terminate();
    _worker = null;
  }

  // ---------------------------------------------------------------------------
  // Internal message handler
  // ---------------------------------------------------------------------------

  void _onMessage(String line) {
    print('[ChessEngine] _onMessage: "$line"');
    // Use startsWith rather than equality so that engines which append '\n'
    // or trailing whitespace still match correctly.
    if (line.startsWith('uciok')) {
      print('[ChessEngine] Got uciok! Sending isready...');
      // Engine acknowledged UCI mode — ask if it's ready to accept commands.
      _sendCommand('isready');
    } else if (line.startsWith('readyok')) {
      print('[ChessEngine] Got readyok! Init complete.');
      // Only complete the init handshake once; ignore subsequent 'readyok'
      // responses (e.g. those triggered inside _configureElo).
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
        _readyCompleter = null;
      }
    } else if (line.startsWith('bestmove')) {
      // "bestmove e2e4 ponder d7d5"  →  parts[1] == 'e2e4'
      final parts = line.split(' ');
      final move = parts.length > 1 ? parts[1] : '';
      print('[ChessEngine] Got bestmove: $move');
      if (_moveCompleter != null && !_moveCompleter!.isCompleted) {
        _moveCompleter!.complete(move);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ELO / strength configuration
  // ---------------------------------------------------------------------------

  /// Sends UCI options to configure the Stockfish Skill Level (0-20).
  ///
  /// botLevel is now directly a Stockfish Skill Level, so we set it directly.
  void _configureElo(int skillLevel) {
    // botLevel is now directly a Stockfish Skill Level (0-20)
    if (skillLevel >= 20) {
      // Full strength
      _sendCommand('setoption name UCI_LimitStrength value false');
      _sendCommand('setoption name Skill Level value 20');
    } else {
      _sendCommand('setoption name UCI_LimitStrength value false');
      _sendCommand('setoption name Skill Level value $skillLevel');
    }
    // No 'isready' here — we don't want the 'readyok' reply to accidentally
    // complete the init completer, and we don't need to wait before sending
    // 'position'+'go' because Stockfish processes commands sequentially.
  }

  /// Think time in milliseconds, scaled to skill level so weaker bots feel snappier.
  int _getMoveTime(int skillLevel) {
    if (skillLevel < 3) return 200;
    if (skillLevel < 6) return 400;
    if (skillLevel < 10) return 600;
    if (skillLevel < 15) return 800;
    return 1000;
  }

  /// Returns the probability of making a random move for amateur mode.
  double _getRandomChance(int eloLevel) {
    if (eloLevel <= 100) return 0.80;
    if (eloLevel <= 200) return 0.70;
    if (eloLevel <= 300) return 0.60;
    if (eloLevel <= 400) return 0.50;
    if (eloLevel <= 500) return 0.40;
    if (eloLevel <= 600) return 0.30;
    if (eloLevel <= 700) return 0.25;
    if (eloLevel <= 800) return 0.18;
    return 0.15; // 900 ELO
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _sendCommand(String cmd) {
    print('[ChessEngine] sending: "$cmd"');
    _worker?.postMessage(cmd.toJS);
  }
}
