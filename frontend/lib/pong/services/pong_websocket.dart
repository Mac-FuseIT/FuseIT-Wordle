import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class PongWebSocket {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessage;

  void connect(String sessionId, String nickname) {
    final uri = Uri.parse('${_getBaseWsUrl()}/api/pong/join/$sessionId');
    print('[Pong WS] Connecting to: $uri');
    
    _channel = WebSocketChannel.connect(uri);
    print('[Pong WS] WebSocket channel created');
    
    _channel!.stream.listen(
      (data) {
        print('[Pong WS] Received: $data');
        final msg = jsonDecode(data);
        onMessage?.call(msg);
      },
      onError: (error) {
        print('[Pong WS] Error: $error');
      },
      onDone: () {
        print('[Pong WS] Connection closed');
      },
    );

    send({'type': 'set_name', 'name': nickname});
    print('[Pong WS] Sent set_name with nickname: $nickname');
  }

  void send(Map<String, dynamic> msg) {
    final data = jsonEncode(msg);
    print('[Pong WS] Sending: $data');
    _channel?.sink.add(data);
  }

  void close() {
    print('[Pong WS] Closing connection');
    _channel?.sink.close();
  }

  String _getBaseWsUrl() {
    final loc = Uri.base;
    final scheme = loc.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${loc.host}';
  }

  String getBaseUrl() {
    final loc = Uri.base;
    return '${loc.scheme}://${loc.host}';
  }
}
