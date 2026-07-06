import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class ChessPvpWebSocket {
  WebSocketChannel? _channel;
  void Function(Map<String, dynamic>)? onMessage;

  void connect(String sessionId, int userId, String name, {String? colorChoice, String? timeControl}) {
    _sessionId = sessionId;
    _userId = userId;
    _name = name;
    _colorChoice = colorChoice;
    _timeControl = timeControl;
    _doConnect();
  }

  String? _sessionId;
  int? _userId;
  String? _name;
  String? _colorChoice;
  String? _timeControl;
  bool _intentionallyClosed = false;

  void _doConnect() {
    final loc = Uri.base;
    final scheme = loc.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri.parse('$scheme://${loc.host}/api/chess-pvp/join/$_sessionId');

    print('[Chess PvP WS] Connecting to: $uri');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen((msg) {
      print('[Chess PvP WS] Received: $msg');
      final data = jsonDecode(msg as String);
      onMessage?.call(data);
    }, onError: (e) {
      print('[Chess PvP WS] Error: $e');
    }, onDone: () {
      print('[Chess PvP WS] Connection closed');
      if (!_intentionallyClosed) {
        // Auto-reconnect after 2s
        print('[Chess PvP WS] Reconnecting in 2s...');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_intentionallyClosed) _doConnect();
        });
      }
      onMessage?.call({'type': 'connection_lost'});
    });

    final joinMsg = {'type': 'join', 'userId': _userId, 'name': _name, 'sessionId': _sessionId, 'colorChoice': _colorChoice, 'timeControl': _timeControl};
    print('[Chess PvP WS] Sending join: $joinMsg');
    send(joinMsg);
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void ready() => send({'type': 'ready'});

  void makeMove(String move, {bool gameOver = false, String? winner, String? reason}) {
    send({'type': 'move', 'move': move, 'gameOver': gameOver, 'winner': winner, 'reason': reason});
  }

  void forfeit() => send({'type': 'forfeit'});

  void requestRedo() => send({'type': 'redo_request'});

  void voteRedo(bool accept) => send({'type': 'redo_vote', 'accept': accept});

  void dispose() {
    _intentionallyClosed = true;
    _channel?.sink.close();
  }
}
