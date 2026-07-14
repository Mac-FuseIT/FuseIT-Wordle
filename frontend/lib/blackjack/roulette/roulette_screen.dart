import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/app_theme.dart';
import 'roulette_websocket.dart';
import 'models/roulette_state.dart';
import 'widgets/roulette_wheel.dart';

class RouletteScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const RouletteScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> {
  late RouletteWebSocket _ws;

  String _phase = 'idle';
  int _timeRemaining = 0;
  List<Map<String, dynamic>> _players = [];
  int _balance = 0;
  List<Map<String, dynamic>> _myBets = [];
  int? _winningNumber;
  String? _winningColor;
  List<int> _history = [];
  List<Map<String, dynamic>>? _payouts;
  String? _error;
  bool _connected = true;
  int _roundNumber = 0;

  // Betting UI state
  int _selectedChip = 5;
  Timer? _countdownTimer;
  Timer? _errorTimer;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _ws = RouletteWebSocket();
    _ws.onMessage = _handleMessage;
    _ws.connect(widget.userId, widget.nickname);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timeRemaining > 0) {
        setState(
          () =>
              _timeRemaining = (_timeRemaining - 1000).clamp(0, _timeRemaining),
        );
      }
    });
  }

  @override
  void dispose() {
    _ws.dispose();
    _countdownTimer?.cancel();
    _errorTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Message handler
  // ---------------------------------------------------------------------------

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    switch (type) {
      case 'game_state':
        setState(() {
          _phase = data['phase'] ?? _phase;
          _timeRemaining = data['timeRemaining'] ?? 0;
          _players = List<Map<String, dynamic>>.from(data['players'] ?? []);
          _balance = data['yourBalance'] ?? 0;
          _myBets = List<Map<String, dynamic>>.from(data['yourBets'] ?? []);
          final lastResult = data['lastResult'];
          if (lastResult != null) {
            _winningNumber = lastResult['winningNumber'];
            _winningColor = lastResult['color'];
          }
          _history = List<int>.from(data['history'] ?? []);
          _roundNumber = data['roundNumber'] ?? 0;
        });
        break;

      case 'betting':
        setState(() {
          _phase = 'betting';
          _timeRemaining = data['timeRemaining'] ?? 20000;
          _roundNumber = data['roundNumber'] ?? _roundNumber;
          _myBets = [];
          _payouts = null;
        });
        break;

      case 'player_joined':
        setState(() {
          final newPlayer = <String, dynamic>{
            'userId': data['userId'],
            'name': data['name'],
            'bets': <dynamic>[],
          };
          if (!_players.any((p) => p['userId'] == newPlayer['userId'])) {
            _players.add(newPlayer);
          }
        });
        break;

      case 'player_left':
        setState(() {
          _players.removeWhere((p) => p['userId'] == data['userId']);
        });
        break;

      case 'bet_placed':
        setState(() {
          final uid = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == uid);
          if (idx != -1) {
            final updated = Map<String, dynamic>.from(_players[idx]);
            final bets = List<Map<String, dynamic>>.from(updated['bets'] ?? []);
            bets.add({
              'betType': data['betType'],
              'betValue': data['betValue'],
              'amount': data['amount'],
            });
            updated['bets'] = bets;
            _players[idx] = updated;
          }
          // If it's our own bet confirmation, add to _myBets too
          if (uid == widget.userId) {
            _myBets.add({
              'type': data['betType'],
              'value': data['betValue'],
              'amount': data['amount'],
            });
          }
        });
        break;

      case 'bets_cleared':
        setState(() {
          final uid = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == uid);
          if (idx != -1) {
            final updated = Map<String, dynamic>.from(_players[idx]);
            updated['bets'] = <dynamic>[];
            _players[idx] = updated;
          }
          if (uid == widget.userId) {
            _myBets = [];
          }
        });
        break;

      case 'spinning':
        setState(() {
          _phase = 'spinning';
          _winningNumber = data['winningNumber'];
          _winningColor = data['winningColor'];
          _timeRemaining = 5000;
        });
        break;

      case 'result':
        setState(() {
          _phase = 'result';
          _payouts = List<Map<String, dynamic>>.from(data['payouts'] ?? []);
          _balance = data['yourNewBalance'] ?? _balance;
          _winningNumber = data['winningNumber'] ?? _winningNumber;
          _winningColor = data['winningColor'] ?? _winningColor;
          if (_winningNumber != null) {
            _history = [_winningNumber!, ..._history].take(10).toList();
          }
          _timeRemaining = 5000;
        });
        break;

      case 'error':
        setState(
          () => _error = data['message']?.toString() ?? 'An error occurred',
        );
        _errorTimer?.cancel();
        _errorTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _error = null);
        });
        break;

      case 'connection_lost':
        setState(() => _connected = false);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Helper methods
  // ---------------------------------------------------------------------------

  double _getProgress() {
    switch (_phase) {
      case 'betting':
        return (_timeRemaining / 20000).clamp(0.0, 1.0);
      case 'spinning':
        return (_timeRemaining / 5000).clamp(0.0, 1.0);
      case 'result':
        return (_timeRemaining / 5000).clamp(0.0, 1.0);
      default:
        return 0.0;
    }
  }

  Color _getPhaseColor() {
    switch (_phase) {
      case 'betting':
        return Colors.green;
      case 'spinning':
        return Colors.amber;
      case 'result':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getPhaseLabel() {
    switch (_phase) {
      case 'betting':
        final secs = (_timeRemaining / 1000).ceil();
        return 'Betting: ${secs}s';
      case 'spinning':
        return 'Spinning...';
      case 'result':
        return 'Results';
      default:
        return 'Waiting...';
    }
  }

  int _totalMyBets() {
    return _myBets.fold(0, (sum, b) => sum + (b['amount'] as int? ?? 0));
  }

  int _playerTotalBets(Map<String, dynamic> player) {
    final bets = List<Map<String, dynamic>>.from(player['bets'] ?? []);
    return bets.fold(0, (sum, b) => sum + (b['amount'] as int? ?? 0));
  }

  String _betLabel(Map<String, dynamic> bet) {
    final type = bet['type'] ?? bet['betType'] ?? '';
    final value = bet['value'] ?? bet['betValue'];
    final amount = bet['amount'] ?? 0;
    if (type == 'straight' && value != null) {
      return '\$$amount on #$value';
    }
    return '\$$amount on ${type.toString().toUpperCase()}';
  }

  Color _historyDotColor(int number) {
    final color = getNumberColor(number);
    if (color == 'red') return Colors.red.shade700;
    if (color == 'green') return Colors.green.shade700;
    return Colors.grey.shade800;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildConnectionBanner(),
                    _buildErrorBanner(),
                    const SizedBox(height: 8),
                    _buildWheelPlaceholder(),
                    const SizedBox(height: 12),
                    _buildPhaseTimerBar(),
                    const SizedBox(height: 16),
                    _buildBettingTable(),
                    const SizedBox(height: 12),
                    _buildMyBetsSummary(),
                    const SizedBox(height: 12),
                    _buildPlayersSection(),
                    const SizedBox(height: 12),
                    _buildHistory(),
                    const SizedBox(height: 12),
                    if (_phase == 'result' && _payouts != null) ...[
                      _buildPayouts(),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBack,
          ),
          const Text(
            'Roulette',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF3A3A3C)),
            ),
            child: Text(
              '\$$_balance',
              style: TextStyle(
                color: widget.theme.correct,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Banners
  // ---------------------------------------------------------------------------

  Widget _buildConnectionBanner() {
    if (_connected) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.amber.withOpacity(0.85),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.black87, size: 16),
          SizedBox(width: 8),
          Text(
            'Reconnecting...',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(Icons.close, color: Colors.red, size: 16),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Wheel
  // ---------------------------------------------------------------------------

  Widget _buildWheelPlaceholder() {
    return Center(
      child: RouletteWheel(winningNumber: _winningNumber, phase: _phase),
    );
  }

  // ---------------------------------------------------------------------------
  // Phase timer bar
  // ---------------------------------------------------------------------------

  Widget _buildPhaseTimerBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            _getPhaseLabel(),
            style: TextStyle(
              color: _getPhaseColor(),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _getProgress(),
            minHeight: 8,
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation<Color>(_getPhaseColor()),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Betting table
  // ---------------------------------------------------------------------------

  Widget _buildBettingTable() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Betting Table',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildChipSelector(),
          const SizedBox(height: 12),
          _buildOutsideBets(),
          const SizedBox(height: 8),
          _buildNumberGrid(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Chip selector
  // ---------------------------------------------------------------------------

  Widget _buildChipSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [1, 5, 10, 25].map((amount) {
        final selected = _selectedChip == amount;
        return GestureDetector(
          onTap: () => setState(() => _selectedChip = amount),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? widget.theme.correct : const Color(0xFF3A3A3C),
              border: Border.all(
                color: selected ? widget.theme.correct : Colors.white24,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '\$$amount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Outside bets
  // ---------------------------------------------------------------------------

  Widget _buildOutsideBets() {
    final enabled = _phase == 'betting';
    return Column(
      children: [
        Row(
          children: [
            _buildOutsideBet('RED', 'red', null, Colors.red.shade700, enabled),
            const SizedBox(width: 4),
            _buildOutsideBet(
              'BLACK',
              'black',
              null,
              Colors.grey.shade900,
              enabled,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildOutsideBet(
              'ODD',
              'odd',
              null,
              const Color(0xFF2C2C2E),
              enabled,
            ),
            const SizedBox(width: 4),
            _buildOutsideBet(
              'EVEN',
              'even',
              null,
              const Color(0xFF2C2C2E),
              enabled,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildOutsideBet(
              'LOW 1-18',
              'low',
              null,
              const Color(0xFF2C2C2E),
              enabled,
            ),
            const SizedBox(width: 4),
            _buildOutsideBet(
              'HIGH 19-36',
              'high',
              null,
              const Color(0xFF2C2C2E),
              enabled,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutsideBet(
    String label,
    String betType,
    dynamic betValue,
    Color bg,
    bool enabled,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled
            ? () => _ws.placeBet(betType, betValue, _selectedChip)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Number grid
  // ---------------------------------------------------------------------------

  Widget _buildNumberGrid() {
    final enabled = _phase == 'betting';
    return Column(
      children: [
        // Zero at top — full width
        _buildNumberCell(0, enabled),
        const SizedBox(height: 4),
        // 12 rows of 3 numbers
        for (int row = 0; row < 12; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                for (int col = 1; col <= 3; col++)
                  Expanded(child: _buildNumberCell(row * 3 + col, enabled)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNumberCell(int number, bool enabled) {
    final color = getNumberColor(number);
    final bgColor = color == 'red'
        ? Colors.red.shade700
        : color == 'green'
        ? Colors.green.shade700
        : Colors.grey.shade900;

    return GestureDetector(
      onTap: enabled
          ? () => _ws.placeBet('straight', number, _selectedChip)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: enabled ? null : Border.all(color: Colors.white10),
        ),
        child: Text(
          '$number',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white38,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // My bets summary
  // ---------------------------------------------------------------------------

  Widget _buildMyBetsSummary() {
    if (_myBets.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your bets:',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          ..._myBets.map(
            (bet) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _betLabel(bet),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Total: \$${_totalMyBets()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _phase == 'betting' ? _ws.clearBets : null,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(60, 32),
                ),
                child: const Text('Clear All', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Players section
  // ---------------------------------------------------------------------------

  Widget _buildPlayersSection() {
    if (_players.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Players (${_players.length})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ..._players.map((player) {
            final isMe = player['userId'] == widget.userId;
            final name = isMe
                ? 'You'
                : (player['name'] ?? player['nickname'] ?? 'Player');
            final total = _playerTotalBets(player);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: isMe ? widget.theme.correct : Colors.white,
                        fontSize: 13,
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (total > 0)
                    Text(
                      'Bet: \$$total',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  Widget _buildHistory() {
    if (_history.isEmpty) return const SizedBox.shrink();
    final recent = _history.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent results:',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          children: recent
              .map(
                (n) => Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _historyDotColor(n),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Center(
                    child: Text(
                      '$n',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Payouts (result phase)
  // ---------------------------------------------------------------------------

  Widget _buildPayouts() {
    if (_payouts == null || _payouts!.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.theme.correct.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Round Results',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ..._payouts!.map((payout) {
            final isMe = payout['userId'] == widget.userId;
            final name = isMe
                ? 'You'
                : (payout['name'] ?? payout['nickname'] ?? 'Player');
            final netProfit = payout['netProfit'] as int? ?? 0;
            final newBalance = payout['newBalance'] as int?;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: isMe ? widget.theme.correct : Colors.white70,
                        fontSize: 14,
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    netProfit >= 0 ? '+\$$netProfit' : '-\$${netProfit.abs()}',
                    style: TextStyle(
                      color: netProfit >= 0 ? Colors.green : Colors.redAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isMe && newBalance != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '→ \$$newBalance',
                      style: TextStyle(
                        color: widget.theme.correct,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
