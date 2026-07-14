import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class RouletteWebSocket {
  WebSocketChannel? _channel;
  void Function(Map<String, dynamic>)? onMessage;

  int? _userId;
  String? _name;
  bool _intentionallyClosed = false;

  void connect(int userId, String name) {
    _userId = userId;
    _name = name;
    _intentionallyClosed = false;
    _doConnect();
  }

  void _doConnect() {
    final loc = Uri.base;
    final scheme = loc.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri.parse('$scheme://${loc.host}/api/roulette/join');

    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen((msg) {
      final data = jsonDecode(msg as String) as Map<String, dynamic>;
      onMessage?.call(data);
    }, onError: (e) {
      // ignore
    }, onDone: () {
      if (!_intentionallyClosed) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!_intentionallyClosed) _doConnect();
        });
      }
      onMessage?.call({'type': 'connection_lost'});
    });

    send({'type': 'join', 'userId': _userId, 'name': _name});
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void placeBet(String betType, dynamic betValue, int amount) {
    send({
      'type': 'place_bet',
      'betType': betType,
      'betValue': betValue,
      'amount': amount,
    });
  }

  void clearBets() => send({'type': 'clear_bets'});

  void leave() => send({'type': 'leave'});

  void dispose() {
    _intentionallyClosed = true;
    _channel?.sink.close();
  }
}
