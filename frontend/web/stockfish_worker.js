// Stockfish.js Web Worker shim for Chess.IT
//
// This file is spawned as a Web Worker by chess_engine.dart.
// It loads the Stockfish WASM engine and bridges UCI messages between
// the Dart main thread and the engine.
//
// Expected assets (must be placed manually by user):
//   frontend/web/stockfish/stockfish-nnue-16-single.js   (~1.8 MB)
//   frontend/web/stockfish/stockfish-nnue-16-single.wasm (~1.8 MB)
//
// Download from: https://github.com/nmrugg/stockfish.js/releases
//
// How this works (nmrugg/stockfish.js v16+ API):
//
// The stockfish-nnue-16-single.js engine script, when loaded inside a Web
// Worker via importScripts, reads the WASM path from self.location.hash.
// The engine then sets up its own onmessage/postMessage hooks directly on
// the Worker global scope:
//   - Incoming messages (UCI commands as strings) → engine.processCommand()
//   - Engine output lines → postMessage(line) back to the main thread
//
// Because the engine wires itself into the Worker's messaging system, this
// shim only needs to pass the correct WASM URL via the hash and then load
// the script. The Dart caller must spawn this worker with the WASM path
// appended as a URL hash fragment:
//
//   Worker('stockfish_worker.js#./stockfish/stockfish-nnue-16-single.wasm')
//
// If no hash is provided, the engine will attempt to resolve the WASM file
// relative to the worker script location using the default naming convention
// (replacing .js with .wasm), which may or may not work depending on the
// server configuration.
//
// Fallback behaviour: if the engine exports a Stockfish() factory function
// (older nmrugg/stockfish.js API used in some forks), this shim handles
// that case too by wiring the factory's message listener to postMessage.

(function () {
  'use strict';

  var engineLoaded = false;

  try {
    // The engine JS resolves the WASM path from self.location.hash.
    // If the hash is not set, set a sensible default so the engine can find
    // the .wasm file sitting next to the .js in the same directory.
    if (!self.location.hash || self.location.hash === '#') {
      // Engine uses self.location.hash to find the WASM; we cannot mutate
      // self.location.hash in a Worker, so we rely on the caller passing it.
      // Log a warning but attempt to load anyway — the engine may resolve the
      // WASM path on its own if both files live in the same directory.
      postMessage('info string stockfish_worker: no WASM path in hash; engine will attempt auto-resolve');
    }

    // Load the Stockfish engine script.
    // After this call, the engine has hooked itself into self.onmessage and
    // will call postMessage() for all UCI output lines.
    importScripts('./stockfish/stockfish-nnue-16-single.js');
    engineLoaded = true;

    // --- Newer API fallback ---
    // Some builds (or older nmrugg versions) expose a global Stockfish()
    // factory instead of hooking the worker messaging directly.
    // If the factory is present, wire it up manually.
    if (typeof Stockfish === 'function') {
      var engine = Stockfish();

      // Route engine output to the main thread
      if (typeof engine.addMessageListener === 'function') {
        engine.addMessageListener(function (line) {
          postMessage(line);
        });
      } else if (typeof engine.print === 'undefined') {
        // Some emscripten builds use a 'print' callback
        engine.print = function (line) {
          postMessage(line);
        };
      }

      // Forward incoming UCI commands from the main thread to the engine.
      // Overrides any onmessage the engine may have set on the worker scope.
      self.onmessage = function (event) {
        if (event.data && typeof engine.postMessage === 'function') {
          engine.postMessage(event.data);
        } else if (event.data && typeof engine.processCommand === 'function') {
          engine.processCommand(event.data);
        }
      };

      // Kick off UCI handshake
      if (typeof engine.postMessage === 'function') {
        engine.postMessage('uci');
      } else if (typeof engine.processCommand === 'function') {
        engine.processCommand('uci');
      }
    }
    // If Stockfish() factory is NOT present, the engine already hooked itself
    // into self.onmessage/postMessage when importScripts ran (standard v16+ behaviour).
    // Nothing more to do — UCI commands from the main thread will flow through
    // self.onmessage automatically, and engine output will arrive via postMessage.

  } catch (e) {
    // Report load failure back to the main thread as a UCI info string so the
    // Dart side can detect and surface the error to the user.
    postMessage('info string stockfish_worker: failed to load engine — ' + (e && e.message ? e.message : String(e)));

    // Also set up a no-op onmessage so the worker doesn't crash on subsequent
    // messages from the main thread after the failure.
    if (!engineLoaded) {
      self.onmessage = function (_event) {
        postMessage('info string stockfish_worker: engine not available');
      };
    }
  }
}());
