import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class IceWebSocket {
  WebSocketChannel? _channel;
  final String sessionId;
  final Function(Map<String, dynamic>) onMessage;
  final String? userName;

  IceWebSocket({required this.sessionId, required this.onMessage, this.userName});

  void connect() {
    final host = Uri.base.host;
    final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri.parse('$scheme://$host/api/ice/join/$sessionId');
    print('Connecting to: $uri');
    _channel = WebSocketChannel.connect(uri);
    
    // Send name after connection
    if (userName != null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        sendMessage({'type': 'set_name', 'name': userName});
      });
    }
    
    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data);
          print('Received: $msg');
          onMessage(msg);
        } catch (e) {
          print('Error parsing message: $e');
        }
      },
      onError: (error) => print('WebSocket error: $error'),
      onDone: () => print('WebSocket closed'),
    );
  }

  void sendPaddleMove(double x, double y) {
    _channel?.sink.add(jsonEncode({'type': 'paddle_move', 'x': x, 'y': y}));
  }

  void sendMessage(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void dispose() {
    _channel?.sink.close();
  }
}
