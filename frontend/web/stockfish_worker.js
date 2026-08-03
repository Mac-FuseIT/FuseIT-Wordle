// Stockfish.js Web Worker for Chess.IT
//
// The Stockfish 18 engine (stockfish-18-lite-single.js), when loaded
// inside a Web Worker, automatically hooks into onmessage/postMessage.
// This shim only needs to load the script.
//
// The engine resolves the .wasm file path from self.location.hash or
// by replacing .js with .wasm in its own URL.

try {
  importScripts('./stockfish/stockfish-18-lite-single.js');
} catch (e) {
  postMessage('info string Failed to load Stockfish: ' + (e.message || e));
  self.onmessage = function() {
    postMessage('info string Engine not available');
  };
}
