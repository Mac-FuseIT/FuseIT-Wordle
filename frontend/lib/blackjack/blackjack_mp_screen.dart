import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import 'blackjack_mp_websocket.dart';
import 'widgets/animated_hand.dart';

class BlackjackMpScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;
  final String gameId;

  const BlackjackMpScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
    required this.gameId,
  });

  @override
  State<BlackjackMpScreen> createState() => _BlackjackMpScreenState();
}

class _BlackjackMpScreenState extends State<BlackjackMpScreen> {
  late BlackjackMpWebSocket _ws;

  String _phase = 'waiting';
  List<Map<String, dynamic>> _players = [];
  Map<String, dynamic> _dealer = {'hand': [], 'value': 0};
  int _currentTurn = 0;
  int? _creatorId;
  int _myBalance = 0;
  String? _error;
  bool _connected = true;
  int _betAmount = 10;
  List<Map<String, dynamic>>? _roundResults;
  bool _myBetPlaced = false;
  bool _canDouble = false;

  int _deckRemaining = 52;

  // Animation state
  Map<int, int> _displayedPlayerValues = {}; // keyed by player userId
  int _displayedDealerValue = 0;
  Map<int, int> _previousCardCounts = {}; // keyed by player userId
  int _previousDealerCardCount = 0;
  bool _isInitialState = true; // true = show all cards instantly (reconnection)
  bool _isAnimating = false;

  Timer? _errorTimer;
  Timer? _resultsTimer;

  // SECTION: lifecycle
  @override
  void initState() {
    super.initState();
    _ws = BlackjackMpWebSocket();
    _ws.onMessage = _handleMessage;
    _ws.connect(widget.gameId, widget.userId, widget.nickname);
  }

  @override
  void dispose() {
    _ws.dispose();
    _errorTimer?.cancel();
    _resultsTimer?.cancel();
    super.dispose();
  }

  // SECTION: message handler
  void _handleMessage(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'game_state':
        setState(() {
          _phase = data['phase'] ?? _phase;
          _players = List<Map<String, dynamic>>.from(data['players'] ?? []);
          _dealer = Map<String, dynamic>.from(data['dealer'] ?? {'hand': [], 'value': 0});
          _currentTurn = data['currentTurn'] ?? 0;
          _creatorId = data['creatorId'];
          _deckRemaining = data['deckRemaining'] ?? _deckRemaining;
          final me = _getMyPlayer();
          if (me != null) {
            _myBalance = me['balance'] ?? 0;
            _myBetPlaced = (me['bet'] ?? 0) > 0;
          }
          // Reconnection: show all existing cards instantly, snapshot counts
          _isInitialState = true;
          _previousDealerCardCount = (_dealer['hand'] as List?)?.length ?? 0;
          _displayedDealerValue = _dealer['value'] ?? 0;
          for (final p in _players) {
            final uid = p['userId'] as int;
            final handLen = (p['hand'] as List?)?.length ?? 0;
            _previousCardCounts[uid] = handLen;
            _displayedPlayerValues[uid] = p['value'] ?? 0;
          }
        });
        break;

      case 'player_joined':
        setState(() {
          final newPlayer = <String, dynamic>{
            'userId': data['userId'],
            'name': data['name'],
            'seatIndex': data['seatIndex'] ?? _players.length,
            'balance': 0,
            'bet': 0,
            'hand': <dynamic>[],
            'value': 0,
            'status': 'waiting',
            'disconnected': false,
          };
          if (!_players.any((p) => p['userId'] == newPlayer['userId'])) {
            _players.add(newPlayer);
          }
        });
        break;

      case 'player_left':
        setState(() {
          final leftId = data['userId'];
          _players.removeWhere((p) => p['userId'] == leftId);
        });
        break;

      case 'betting_phase':
        setState(() {
          _phase = 'betting';
          _myBetPlaced = false;
        });
        break;

      case 'bet_placed':
        setState(() {
          final betUserId = data['userId'];
          final betAmount = data['amount'] ?? 0;
          final idx = _players.indexWhere((p) => p['userId'] == betUserId);
          if (idx != -1) {
            _players[idx] = Map<String, dynamic>.from(_players[idx])
              ..['bet'] = betAmount;
          }
        });
        break;

      case 'cards_dealt':
        setState(() {
          // Snapshot previous counts before updating (should all be 0)
          for (final p in _players) {
            final uid = p['userId'] as int;
            _previousCardCounts[uid] = (p['hand'] as List?)?.length ?? 0;
          }
          _previousDealerCardCount = (_dealer['hand'] as List?)?.length ?? 0;

          final dealtPlayers = data['players'] as List? ?? [];
          for (final dealt in dealtPlayers) {
            final dMap = Map<String, dynamic>.from(dealt);
            final idx = _players.indexWhere((p) => p['userId'] == dMap['userId']);
            if (idx != -1) {
              _players[idx] = Map<String, dynamic>.from(_players[idx])
                ..['hand'] = dMap['hand'] ?? []
                ..['value'] = dMap['value'] ?? 0
                ..['status'] = 'playing';
            }
          }
          if (data['dealer'] != null) {
            _dealer = Map<String, dynamic>.from(data['dealer']);
          }
          // Each player gets 2 cards + dealer gets 2 cards
          final playerCount = dealtPlayers.length;
          _deckRemaining -= (playerCount * 2 + 2);
          if (_deckRemaining < 0) _deckRemaining = 0;
          _phase = 'playing';
          _isInitialState = false;
          _isAnimating = true;
        });
        // Safety timeout: clear _isAnimating if callbacks never fire (spectator edge case)
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted && _isAnimating) setState(() => _isAnimating = false);
        });
        break;

      case 'turn_start':
        setState(() {
          final turnUserId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == turnUserId);
          if (idx != -1) _currentTurn = idx;
          _canDouble = data['canDouble'] ?? false;
        });
        break;

      case 'card_drawn':
        setState(() {
          final cardUserId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == cardUserId);
          if (idx != -1) {
            // Snapshot previous count before update
            _previousCardCounts[cardUserId as int] =
                (_players[idx]['hand'] as List?)?.length ?? 0;

            final updated = Map<String, dynamic>.from(_players[idx]);
            if (data['hand'] != null) {
              updated['hand'] = List<Map<String, dynamic>>.from(data['hand']);
            } else if (data['card'] != null) {
              final hand = List<Map<String, dynamic>>.from(updated['hand'] ?? []);
              hand.add(Map<String, dynamic>.from(data['card']));
              updated['hand'] = hand;
            }
            updated['value'] = data['value'] ?? updated['value'];
            _players[idx] = updated;
          }
          _deckRemaining--;
          if (_deckRemaining < 0) _deckRemaining = 0;
          _isAnimating = true;
        });
        break;

      case 'player_stood':
        setState(() {
          final stoodId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == stoodId);
          if (idx != -1) {
            _players[idx] = Map<String, dynamic>.from(_players[idx])
              ..['status'] = 'stood';
          }
        });
        break;

      case 'player_doubled':
        setState(() {
          final pId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == pId);
          if (idx != -1) {
            final updated = Map<String, dynamic>.from(_players[idx]);
            updated['hand'] = data['hand'] ?? updated['hand'];
            updated['value'] = data['value'] ?? updated['value'];
            updated['bet'] = data['newBet'] ?? data['bet'] ?? updated['bet'];
            updated['status'] = (updated['value'] ?? 0) > 21 ? 'bust' : 'stood';
            _players[idx] = updated;
          }
          // Double draws exactly one card
          _deckRemaining--;
          if (_deckRemaining < 0) _deckRemaining = 0;
        });
        break;

      case 'player_bust':
        setState(() {
          final bustId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == bustId);
          if (idx != -1) {
            _players[idx] = Map<String, dynamic>.from(_players[idx])
              ..['status'] = 'bust';
          }
        });
        break;

      case 'dealer_turn':
        setState(() {
          // Snapshot previous dealer card count before update
          _previousDealerCardCount =
              (_dealer['hand'] as List?)?.length ?? 0;

          final hand = data['finalHand'] ?? data['hand'] ?? data['cards'];
          final value = data['finalValue'] ?? data['value'];
          if (hand != null) _dealer['hand'] = List<Map<String, dynamic>>.from((hand as List).map((c) => Map<String, dynamic>.from(c)));
          if (value != null) _dealer['value'] = value;
          // Dealer draws any cards beyond the initial 2
          final dealerCardCount = _dealer['hand'] is List ? (_dealer['hand'] as List).length : 0;
          if (dealerCardCount > 2) {
            _deckRemaining -= (dealerCardCount - 2);
            if (_deckRemaining < 0) _deckRemaining = 0;
          }
          _phase = 'dealer_turn';
          _isAnimating = true;
        });
        // Safety timeout: clear _isAnimating if callbacks never fire (spectator edge case)
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted && _isAnimating) setState(() => _isAnimating = false);
        });
        break;

      case 'round_result':
        setState(() {
          _phase = 'round_over';
          final results = data['results'] as List? ?? [];
          _roundResults = List<Map<String, dynamic>>.from(results.map((r) => Map<String, dynamic>.from(r)));
          // Update player balances from results
          for (final result in _roundResults!) {
            final rId = result['userId'];
            final idx = _players.indexWhere((p) => p['userId'] == rId);
            if (idx != -1 && result['newBalance'] != null) {
              _players[idx] = Map<String, dynamic>.from(_players[idx])..['balance'] = result['newBalance'];
            }
            if (rId == widget.userId && result['newBalance'] != null) {
              _myBalance = result['newBalance'];
            }
          }
          // Update dealer
          if (data['dealerHand'] != null) {
            _dealer['hand'] = List<Map<String, dynamic>>.from((data['dealerHand'] as List).map((c) => Map<String, dynamic>.from(c)));
          }
          if (data['dealerValue'] != null) {
            _dealer['value'] = data['dealerValue'];
          }
        });
        _resultsTimer?.cancel();
        _resultsTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _roundResults = null);
        });
        break;

      case 'error':
        setState(() => _error = data['message']?.toString() ?? 'An error occurred');
        _errorTimer?.cancel();
        _errorTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _error = null);
        });
        break;

      case 'player_disconnected':
        setState(() {
          final dcId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == dcId);
          if (idx != -1) {
            _players[idx] = Map<String, dynamic>.from(_players[idx])
              ..['disconnected'] = true;
          }
        });
        break;

      case 'player_reconnected':
        setState(() {
          final rcId = data['userId'];
          final idx = _players.indexWhere((p) => p['userId'] == rcId);
          if (idx != -1) {
            _players[idx] = Map<String, dynamic>.from(_players[idx])
              ..['disconnected'] = false;
          }
          _connected = true;
        });
        break;

      case 'connection_lost':
        setState(() => _connected = false);
        break;
    }
  }

  // SECTION: helpers
  bool _isMyTurn() {
    if (_phase != 'playing') return false;
    if (_currentTurn < 0 || _currentTurn >= _players.length) return false;
    return _players[_currentTurn]['userId'] == widget.userId;
  }

  Map<String, dynamic>? _getMyPlayer() {
    try {
      return _players.firstWhere((p) => p['userId'] == widget.userId);
    } catch (_) {
      return null;
    }
  }

  // SECTION: build
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildConnectionBanner(),
                    _buildErrorBanner(),
                    _buildDealerArea(),
                    _buildPlayerSeats(),
                    _buildActionArea(),
                    _buildBalanceBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // SECTION: header
  Widget _buildHeader() {
    final tableId = widget.gameId.length >= 8
        ? widget.gameId.substring(0, 8)
        : widget.gameId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              _ws.leave();
              widget.onBack();
            },
          ),
          Text(
            'Table: $tableId',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              _ws.leave();
              widget.onBack();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
            ),
            child: const Text('Leave', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // SECTION: banners
  Widget _buildConnectionBanner() {
    if (_connected) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.amber.withOpacity(0.85),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.black87, size: 16),
          SizedBox(width: 8),
          Text(
            'Reconnecting...',
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // SECTION: dealer area
  Widget _buildDealerArea() {
    final dealerHand = List<Map<String, dynamic>>.from(_dealer['hand'] ?? []);
    final hasHidden = dealerHand.any(
      (c) => c['rank'] == 'hidden' || c['suit'] == 'hidden',
    );
    final valueLabel = hasHidden ? '?' : '$_displayedDealerValue';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Dealer',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (dealerHand.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  valueLabel,
                  style: TextStyle(
                    color: widget.theme.present,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                'Deck: $_deckRemaining',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          if (dealerHand.isNotEmpty) ...[
            const SizedBox(height: 8),
            AnimatedHand(
              cards: dealerHand,
              revealedCount: _isInitialState
                  ? dealerHand.length
                  : _previousDealerCardCount,
              animateNewCards: !_isInitialState,
              delayBetweenCards: const Duration(milliseconds: 400),
              onCardFlipped: (index) {
                final visibleCards = dealerHand
                    .sublist(0, index + 1)
                    .where((c) => c['rank'] != 'hidden')
                    .toList();
                setState(
                  () => _displayedDealerValue =
                      _calculateHandValue(visibleCards),
                );
              },
              onAllFlipsComplete: () =>
                  setState(() => _isAnimating = false),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '—',
                style: TextStyle(color: Colors.white38, fontSize: 18),
              ),
            ),
        ],
      ),
    );
  }

  // SECTION: player seats
  Widget _buildPlayerSeats() {
    if (_players.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No players yet...',
          style: TextStyle(color: Colors.white38, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: List.generate(_players.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPlayerSeat(_players[i], i),
        );
      }),
    );
  }

  Widget _buildPlayerSeat(Map<String, dynamic> player, int index) {
    final isMe = player['userId'] == widget.userId;
    final isCurrentTurn = index == _currentTurn && _phase == 'playing';
    final isDisconnected = player['disconnected'] == true;

    Color borderColor;
    if (isCurrentTurn) {
      borderColor = widget.theme.present;
    } else if (isMe) {
      borderColor = widget.theme.correct;
    } else {
      borderColor = const Color(0xFF3A3A3C);
    }

    final name = isMe ? 'You' : (player['name'] ?? player['nickname'] ?? 'Player');
    final bet = player['bet'] ?? 0;
    final hand = List<Map<String, dynamic>>.from(player['hand'] ?? []);
    final displayedValue = _displayedPlayerValues[player['userId']] ?? 0;
    final status = player['status'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: (isCurrentTurn || isMe) ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + bet + value row
          Row(
            children: [
              if (isDisconnected)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.wifi_off, color: Colors.grey, size: 14),
                ),
              Text(
                name,
                style: TextStyle(
                  color: isCurrentTurn
                      ? widget.theme.present
                      : isMe
                          ? widget.theme.correct
                          : Colors.grey,
                  fontSize: 13,
                ),
              ),
              if (bet > 0) ...[
                const SizedBox(width: 8),
                Text(
                  'Bet: \$$bet',
                  style: TextStyle(color: widget.theme.present, fontSize: 12),
                ),
              ],
              const Spacer(),
              if (hand.isNotEmpty)
                Text(
                  '$displayedValue',
                  style: TextStyle(
                    color: isMe ? widget.theme.correct : widget.theme.present,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
          if (status.isNotEmpty && status != 'waiting' && status != 'playing') ...[
            const SizedBox(height: 4),
            Text(
              status == 'stood'
                  ? 'Stood'
                  : status == 'bust'
                      ? 'BUST'
                      : status == 'bet_placed'
                          ? 'Bet placed'
                          : status,
              style: TextStyle(
                color: status == 'bust' ? Colors.red : Colors.white54,
                fontSize: 11,
                fontWeight: status == 'bust' ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Cards - full size like solo
          if (hand.isNotEmpty)
            AnimatedHand(
              cards: hand,
              revealedCount: _isInitialState
                  ? hand.length
                  : (_previousCardCounts[player['userId']] ?? hand.length),
              animateNewCards: !_isInitialState,
              delayBetweenCards: const Duration(milliseconds: 550),
              cardWidth: 52,
              cardHeight: 72,
              spacing: 6,
              onCardFlipped: (cardIndex) {
                setState(() {
                  final visibleCards = hand
                      .sublist(0, cardIndex + 1)
                      .where((c) =>
                          c['rank'] != 'hidden' && c['rank'] != null)
                      .toList();
                  _displayedPlayerValues[player['userId']] =
                      _calculateHandValue(visibleCards);
                });
              },
              onAllFlipsComplete: () {
                if (player['userId'] == widget.userId) {
                  setState(() => _isAnimating = false);
                }
              },
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Waiting for cards...',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'stood':
        return 'Stood';
      case 'bust':
        return 'Bust! 💥';
      case 'blackjack':
        return 'Blackjack! 🎉';
      case 'waiting':
        return 'Waiting...';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'stood':
        return Colors.white54;
      case 'bust':
        return Colors.redAccent;
      case 'blackjack':
        return widget.theme.correct;
      default:
        return Colors.white38;
    }
  }

  // SECTION: action area
  Widget _buildActionArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: _buildActionContent(),
    );
  }

  Widget _buildActionContent() {
    switch (_phase) {
      case 'waiting':
        return _buildWaitingActions();
      case 'betting':
        return _myBetPlaced
            ? _buildWaitingForBets()
            : _buildBettingUI();
      case 'playing':
        return _isMyTurn() ? _buildPlayActions() : _buildWaitingForTurn();
      case 'dealer_turn':
        return _buildDealerPlaying();
      case 'round_over':
        return _roundResults != null
            ? _buildRoundResults()
            : const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- waiting phase ---
  Widget _buildWaitingActions() {
    final playerCount = _players.length;
    final isHost = _creatorId == widget.userId;
    final canStart = isHost && playerCount >= 2;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Text(
            '$playerCount/4 players',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (canStart)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _ws.startRound,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.theme.correct,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Start Round',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          )
        else
          Text(
            isHost
                ? 'Waiting for more players to join...'
                : 'Waiting for host to start...',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  // --- betting phase ---
  Widget _buildBettingUI() {
    final maxBet = _myBalance > 0 ? _myBalance : 50;
    return Column(
      children: [
        const Text(
          'Place Your Bet',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            ...[5, 10, 25, 50].map((amount) {
              final selected = _betAmount == amount;
              final disabled = amount > _myBalance;
              return GestureDetector(
                onTap: disabled ? null : () => setState(() => _betAmount = amount),
                child: Container(
                  width: 60,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? widget.theme.correct : const Color(0xFF2A2A2B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? widget.theme.correct : const Color(0xFF3A3A3C),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '\$$amount',
                    style: TextStyle(
                      color: disabled ? Colors.grey : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
            // All-in button
            GestureDetector(
              onTap: _myBalance > 0
                  ? () => setState(() => _betAmount = _myBalance)
                  : null,
              child: Container(
                width: 70,
                height: 40,
                decoration: BoxDecoration(
                  color: _betAmount == _myBalance && _myBalance > 0
                      ? widget.theme.present
                      : const Color(0xFF2A2A2B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _betAmount == _myBalance && _myBalance > 0
                        ? widget.theme.present
                        : const Color(0xFF3A3A3C),
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'All In',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (maxBet > 1)
          Slider(
            value: _betAmount.toDouble().clamp(1, maxBet.toDouble()),
            min: 1,
            max: maxBet.toDouble(),
            divisions: maxBet > 1 ? maxBet - 1 : 1,
            activeColor: widget.theme.correct,
            inactiveColor: const Color(0xFF3A3A3C),
            onChanged: (v) => setState(() => _betAmount = v.round()),
          ),
        Text(
          'Bet: \$$_betAmount',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _myBalance > 0
                ? () {
                    _ws.placeBet(_betAmount);
                    setState(() => _myBetPlaced = true);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.correct,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Place Bet — \$$_betAmount',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingForBets() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Waiting for others to bet...',
        style: TextStyle(color: Colors.white54, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  // --- playing phase ---
  Widget _buildPlayActions() {
    final canDouble = _canDouble && _isMyTurn();

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (_isAnimating || !_isMyTurn()) ? null : _ws.hit,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.theme.present,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Hit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (_isAnimating || !_isMyTurn()) ? null : _ws.stand,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3A3A3C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Stand', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (_isAnimating || !canDouble) ? null : _ws.doubleBet,
              style: ElevatedButton.styleFrom(
                backgroundColor: (!_isAnimating && canDouble) ? widget.theme.correct : const Color(0xFF2A2A2B),
                disabledBackgroundColor: const Color(0xFF2A2A2B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Double',
                style: TextStyle(
                  color: (!_isAnimating && canDouble) ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingForTurn() {
    String waitingName = 'player';
    if (_currentTurn >= 0 && _currentTurn < _players.length) {
      final p = _players[_currentTurn];
      waitingName = p['name'] ?? p['nickname'] ?? 'player';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Waiting for $waitingName...',
        style: const TextStyle(color: Colors.white54, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  // --- dealer_turn phase ---
  Widget _buildDealerPlaying() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Dealer is playing...',
        style: TextStyle(color: Colors.white70, fontSize: 15, fontStyle: FontStyle.italic),
        textAlign: TextAlign.center,
      ),
    );
  }

  // --- round_over phase ---
  Widget _buildRoundResults() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ..._roundResults!.map((result) => _buildResultRow(result)),
        ],
      ),
    );
  }

  Widget _buildResultRow(Map<String, dynamic> result) {
    final resultId = result['userId'];
    final isMe = resultId == widget.userId;
    final name = isMe ? 'You' : (result['name'] ?? result['nickname'] ?? 'Player');
    final outcome = result['outcome'] ?? result['result'] ?? 'unknown';
    final payout = result['payout'] ?? result['winnings'] ?? 0;

    final outcomeLabel = _outcomeLabel(outcome);
    final outcomeColor = _outcomeColor(outcome);

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
            outcomeLabel,
            style: TextStyle(
              color: outcomeColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatPayout(payout),
            style: TextStyle(
              color: payout >= 0 ? widget.theme.correct : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _outcomeLabel(String outcome) {
    switch (outcome) {
      case 'blackjack':
        return 'Blackjack! 🎉';
      case 'win':
        return 'Win ✅';
      case 'dealer_bust':
        return 'Win ✅';
      case 'push':
        return 'Push 🤝';
      case 'lose':
        return 'Lose ❌';
      case 'bust':
        return 'Bust 💥';
      case 'dealer_blackjack':
        return 'Lose ❌';
      default:
        return outcome;
    }
  }

  Color _outcomeColor(String outcome) {
    switch (outcome) {
      case 'blackjack':
      case 'win':
      case 'dealer_bust':
        return widget.theme.correct;
      case 'push':
        return Colors.white70;
      default:
        return Colors.redAccent;
    }
  }

  String _formatPayout(int payout) {
    if (payout > 0) return '+\$$payout';
    if (payout < 0) return '-\$${payout.abs()}';
    return '\$0';
  }

  // SECTION: balance bar
  Widget _buildBalanceBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Text(
        'Balance: \$$_myBalance',
        style: TextStyle(
          color: widget.theme.correct,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _getSuitSymbol(String suit) {
    switch (suit.toLowerCase()) {
      case 'hearts':
      case '♥':
        return '♥';
      case 'diamonds':
      case '♦':
        return '♦';
      case 'clubs':
      case '♣':
        return '♣';
      case 'spades':
      case '♠':
        return '♠';
      default:
        return suit;
    }
  }

  int _calculateHandValue(List<Map<String, dynamic>> cards) {
    int total = 0;
    int aces = 0;
    for (final c in cards) {
      final rank = c['rank'] ?? '';
      if (rank == 'hidden' || rank == '') continue;
      if (rank == 'A') {
        total += 11;
        aces++;
      } else if (['J', 'Q', 'K'].contains(rank)) {
        total += 10;
      } else {
        total += int.tryParse(rank as String) ?? 0;
      }
    }
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return total;
  }
}
