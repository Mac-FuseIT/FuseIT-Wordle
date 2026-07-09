import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class BlackjackMpWebSocket {
  WebSocketChannel? _channel;
  void Function(Map<String, dynamic>)? onMessage;

  String? _gameId;
  int? _userId;
  String? _name;
  bool _intentionallyClosed = false;

  void connect(String gameId, int userId, String name) {
    _gameId = gameId;
    _userId = userId;
    _name = name;
    _intentionallyClosed = false;
    _doConnect();
  }

  void _doConnect() {
    final loc = Uri.base;
    final scheme = loc.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri.parse('$scheme://${loc.host}/api/blackjack-mp/join/$_gameId');

    print('[Blackjack MP WS] Connecting to: $uri');
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen((msg) {
      print('[Blackjack MP WS] Received: $msg');
      final data = jsonDecode(msg as String);
      onMessage?.call(data);
    }, onError: (e) {
      print('[Blackjack MP WS] Error: $e');
    }, onDone: () {
      print('[Blackjack MP WS] Connection closed');
      if (!_intentionallyClosed) {
        print('[Blackjack MP WS] Reconnecting in 2s...');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_intentionallyClosed) _doConnect();
        });
      }
      onMessage?.call({'type': 'connection_lost'});
    });

    // Auto-send join on connect
    send({'type': 'join', 'userId': _userId, 'name': _name, 'gameId': _gameId});
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void startRound() => send({'type': 'start_round'});

  void placeBet(int amount) => send({'type': 'place_bet', 'amount': amount});

  void hit() => send({'type': 'hit'});

  void stand() => send({'type': 'stand'});

  void doubleBet() => send({'type': 'double'});

  void leave() => send({'type': 'leave'});

  void dispose() {
    _intentionallyClosed = true;
    _channel?.sink.close();
  }
}
