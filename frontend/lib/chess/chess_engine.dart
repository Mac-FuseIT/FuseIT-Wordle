import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

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
      if (data == null) return;
      // Nuclear fix: in dart2js, Worker.postMessage strings arrive as native
      // JS strings. The package:web type system exposes them as JSAny?, and
      // every strongly-typed cast (isA<JSString>(), `as JSString`, dynamic
      // cast) has proven unreliable at runtime. String interpolation compiles
      // to JS's `'' + value` which calls the JS engine's implicit toString —
      // for a plain JS string this returns the string itself, and it cannot
      // throw. For non-string messages it returns '[object Object]', which
      // won't match any UCI keyword so _onMessage will safely ignore it.
      final line = '$data';
      if (line.isEmpty || line == 'null') return;
      _onMessage(line);
    }.toJS;

    // Kick off UCI handshake.
    _sendCommand('uci');

    await _readyCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        // Engine took too long — mark as timed-out but don't crash.
        _readyCompleter = null;
      },
    );

    _ready = true;
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
    // Use startsWith rather than equality so that engines which append '\n'
    // or trailing whitespace still match correctly.
    if (line.startsWith('uciok')) {
      // Engine acknowledged UCI mode — ask if it's ready to accept commands.
      _sendCommand('isready');
    } else if (line.startsWith('readyok')) {
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
      if (_moveCompleter != null && !_moveCompleter!.isCompleted) {
        _moveCompleter!.complete(move);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ELO / strength configuration
  // ---------------------------------------------------------------------------

  /// Sends UCI options to match the target [elo] strength.
  ///
  /// Stockfish supports `UCI_Elo` only above ~1320; below that we fall back to
  /// the discrete `Skill Level` option (0–20).
  void _configureElo(int elo) {
    if (elo >= 1320) {
      _sendCommand('setoption name UCI_LimitStrength value true');
      _sendCommand('setoption name UCI_Elo value $elo');
    } else {
      _sendCommand('setoption name UCI_LimitStrength value false');
      _sendCommand(
        'setoption name Skill Level value ${_eloToSkillLevel(elo)}',
      );
    }
    // No 'isready' here — we don't want the 'readyok' reply to accidentally
    // complete the init completer, and we don't need to wait before sending
    // 'position'+'go' because Stockfish processes commands sequentially.
  }

  /// Maps ELO (100–1319) to Stockfish Skill Level (0–20).
  int _eloToSkillLevel(int elo) {
    if (elo < 200) return 0;
    if (elo < 400) return 2;
    if (elo < 600) return 5;
    if (elo < 800) return 8;
    if (elo < 1000) return 11;
    if (elo < 1200) return 14;
    return 17;
  }

  /// Think time in milliseconds, scaled to ELO so weaker bots feel snappier.
  int _getMoveTime(int elo) {
    if (elo < 400) return 100;
    if (elo < 800) return 200;
    if (elo < 1000) return 400;
    if (elo < 1320) return 600;
    return 1000;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _sendCommand(String cmd) {
    _worker?.postMessage(cmd.toJS);
  }
}
