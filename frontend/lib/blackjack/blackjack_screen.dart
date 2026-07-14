import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_theme.dart';
import 'widgets/animated_hand.dart';

class BlackjackScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const BlackjackScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  State<BlackjackScreen> createState() => _BlackjackScreenState();
}

class _BlackjackScreenState extends State<BlackjackScreen> {
  bool _loading = true;
  int _balance = 100;
  int _betAmount = 10;
  int _handsPlayed = 0;
  int _handsWon = 0;
  String _state = 'idle'; // idle, playing, result
  String _result = '';
  List<Map<String, dynamic>> _playerCards = [];
  List<Map<String, dynamic>> _dealerCards = [];
  int _playerTotal = 0;
  int _dealerTotal = 0;
  int _currentBet = 0;
  bool _cashedOut = false;
  String? _error;
  int _deckRemaining = 52;
  bool _shuffling = false;

  // Animation state
  int _displayedPlayerValue = 0;
  int _displayedDealerValue = 0;
  int _previousPlayerCardCount = 0;
  int _previousDealerCardCount = 0;
  bool _isInitialLoad = true;
  bool _isAnimating = false;
  bool _showResult = false; // true after delay when result should be displayed

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _loadSession() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('/api/blackjack/today'), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _isInitialLoad = true;
          _balance = data['balance'] ?? 100;
          _handsPlayed = data['handsPlayed'] ?? 0;
          _handsWon = data['handsWon'] ?? 0;
          _cashedOut = data['cashedOut'] ?? false;
          _currentBet = data['currentBet'] ?? 0;
          _deckRemaining = data['deckRemaining'] ?? 52;

          final playerHand = data['playerHand'] as List?;
          final dealerHand = data['dealerHand'] as List?;
          final inHand = data['inHand'] ?? false;
          final gameOver = data['gameOver'] ?? false;

          if (playerHand != null && playerHand.isNotEmpty) {
            _playerCards = List<Map<String, dynamic>>.from(playerHand);
            _dealerCards = List<Map<String, dynamic>>.from(dealerHand ?? []);
            _playerTotal = _calculateHandValue(_playerCards);

            if (inHand && !gameOver) {
              _state = 'playing';
              _dealerTotal = 0;
              _displayedPlayerValue = _playerTotal;
              _displayedDealerValue = 0;
            } else if (gameOver) {
              _state = 'result';
              _showResult = true;
              _dealerTotal = _calculateHandValue(_dealerCards);
              _result = 'Hand over';
              _displayedPlayerValue = _playerTotal;
              _displayedDealerValue = _dealerTotal;
            }
            _previousPlayerCardCount = _playerCards.length;
            _previousDealerCardCount = _dealerCards.length;
          } else {
            _state = 'idle';
            _playerCards = [];
            _dealerCards = [];
            _playerTotal = 0;
            _dealerTotal = 0;
            _displayedPlayerValue = 0;
            _displayedDealerValue = 0;
            _previousPlayerCardCount = 0;
            _previousDealerCardCount = 0;
          }
        });
      } else {
        setState(() => _error = 'Failed to load session');
      }
    } catch (e) {
      setState(() => _error = 'Connection error: $e');
    }
    setState(() => _loading = false);
  }

  void _applyState(Map<String, dynamic> data) {
    final oldDeckRemaining = _deckRemaining;
    final newDeckRemaining = data['deckRemaining'] ?? _deckRemaining;

    // Detect reshuffle: if deck count jumps up significantly
    if (newDeckRemaining > oldDeckRemaining + 5) {
      setState(() => _shuffling = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _shuffling = false);
      });
    }

    // Save previous card counts before updating, so AnimatedHand knows
    // which cards are "new" vs already visible.
    final prevPlayerCount = _playerCards.length;
    final prevDealerCount = _dealerCards.length;

    setState(() {
      _balance = data['balance'] ?? _balance;
      _deckRemaining = newDeckRemaining;
      _handsPlayed = data['handsPlayed'] ?? data['hands_played'] ?? _handsPlayed;
      _handsWon = data['handsWon'] ?? data['hands_won'] ?? _handsWon;
      _cashedOut = data['cashedOut'] ?? data['cashed_out'] ?? false;
      _currentBet = data['currentBet'] ?? data['current_bet'] ?? 0;

      final playerCards = data['playerHand'] ?? data['player_cards'];
      final dealerCards = data['dealerHand'] ?? data['dealer_cards'];

      if (playerCards != null && (playerCards as List).isNotEmpty) {
        _previousPlayerCardCount = prevPlayerCount;
        _previousDealerCardCount = prevDealerCount;

        _playerCards = List<Map<String, dynamic>>.from(playerCards);
        _dealerCards = List<Map<String, dynamic>>.from(dealerCards ?? []);
        _playerTotal = data['playerValue'] ?? data['player_total'] ?? _calculateHandValue(_playerCards);

        final gameOver = data['gameOver'] ?? data['game_over'] ?? false;
        final result = data['result'];

        if (!gameOver) {
          _state = 'playing';
          _result = '';
          _dealerTotal = 0;
        } else {
          _state = 'result';
          _dealerTotal = data['dealerValue'] ?? data['dealer_total'] ?? _calculateHandValue(_dealerCards);
          _result = _resultText(result ?? 'unknown');
          if (!_isInitialLoad) {
            _showResult = false; // hide result initially — show after dealer animation
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) setState(() => _showResult = true);
            });
          } else {
            _showResult = true; // on page load, show immediately
          }
        }

        if (_isInitialLoad) {
          // Initial load: show values immediately, no animation
          _displayedPlayerValue = _playerTotal;
          _displayedDealerValue = gameOver ? _dealerTotal : 0;
        } else {
          // New cards added: let animation callbacks update displayed values
          final playerCardsAdded = _playerCards.length > prevPlayerCount;
          final dealerCardsAdded = _dealerCards.length > prevDealerCount;
          if (playerCardsAdded || dealerCardsAdded) {
            _isAnimating = true;
            // Bug 1 fix: reset displayed values to 0 on new deal (prevCount == 0)
            // so the old hand's value doesn't linger until the first card flips
            if (playerCardsAdded && prevPlayerCount == 0) {
              _displayedPlayerValue = 0;
            }
            if (dealerCardsAdded && prevDealerCount == 0) {
              _displayedDealerValue = 0;
            }
          }
          // Bug 2 fix: on game over (stand), set values authoritatively from
          // server response — the hidden card reveal callback won't fire via
          // AnimatedHand since the card is treated as "old" (index < animateFromIndex)
          if (gameOver) {
            _displayedDealerValue = _dealerTotal;
            _displayedPlayerValue = _playerTotal;
          }
        }
      } else if (_currentBet == 0) {
        _state = 'idle';
        _playerCards = [];
        _dealerCards = [];
        _playerTotal = 0;
        _dealerTotal = 0;
        _previousPlayerCardCount = 0;
        _previousDealerCardCount = 0;
        _displayedPlayerValue = 0;
        _displayedDealerValue = 0;
      }
    });

    // Auto-cashout when balance is 0 and hand is over
    if (_balance <= 0 && _state == 'result') {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_cashedOut) _cashOut();
      });
    }
  }

  int _calculateHandValue(List<Map<String, dynamic>> hand) {
    int total = 0;
    int aces = 0;
    for (final card in hand) {
      final rank = card['rank'] ?? '';
      if (rank == 'hidden') continue;
      if (rank == 'A') { total += 11; aces++; }
      else if (['J', 'Q', 'K'].contains(rank)) total += 10;
      else total += int.tryParse(rank) ?? 0;
    }
    while (total > 21 && aces > 0) { total -= 10; aces--; }
    return total;
  }

  String _resultText(String status) {
    switch (status) {
      case 'blackjack':
        return '🎉 Blackjack! +\$${(_currentBet * 1.5).round()}';
      case 'win':
        return '✅ You Win! +\$$_currentBet';
      case 'dealer_bust':
        return '✅ Dealer Busts! +\$$_currentBet';
      case 'push':
        return '🤝 Push — Bet Returned';
      case 'lose':
        return '❌ You Lose — -\$$_currentBet';
      case 'bust':
        return '💥 Bust! -\$$_currentBet';
      case 'dealer_blackjack':
        return '😱 Dealer Blackjack! -\$$_currentBet';
      default:
        return 'Hand over';
    }
  }

  Future<void> _placeBet() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('/api/blackjack/bet'),
        headers: headers,
        body: jsonEncode({'amount': _betAmount}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // From this point on, cards animate in — no more instant display.
        _isInitialLoad = false;
        _applyState(data);
      } else {
        final err = jsonDecode(res.body);
        setState(() => _error = err['error'] ?? 'Bet failed');
      }
    } catch (e) {
      setState(() => _error = 'Connection error');
    }
    setState(() => _loading = false);
  }

  Future<void> _hit() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.post(Uri.parse('/api/blackjack/hit'), headers: headers);
      if (res.statusCode == 200) {
        _applyState(jsonDecode(res.body));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _stand() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.post(Uri.parse('/api/blackjack/stand'), headers: headers);
      if (res.statusCode == 200) {
        _applyState(jsonDecode(res.body));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _double() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.post(Uri.parse('/api/blackjack/double'), headers: headers);
      if (res.statusCode == 200) {
        _applyState(jsonDecode(res.body));
      } else {
        final err = jsonDecode(res.body);
        setState(() => _error = err['error'] ?? 'Double failed');
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _cashOut() async {
    setState(() => _loading = true);
    try {
      final headers = await _getHeaders();
      final res = await http.post(Uri.parse('/api/blackjack/cashout'), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _cashedOut = true;
          _balance = data['final_balance'] ?? _balance;
        });
      } else {
        final err = jsonDecode(res.body);
        setState(() => _error = err['error'] ?? 'Cannot cash out');
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _state == 'idle' && _playerCards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_cashedOut) {
      // Show the normal game screen with cashed-out footer instead of a separate view
    }

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
                    _buildBalanceBar(),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 16),
                              onPressed: () => setState(() => _error = null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_cashedOut && _state == 'idle') _buildBettingUI(),
                    if (_state == 'playing' || _state == 'result') ...[
                      _buildDeckIndicator(),
                      const SizedBox(height: 12),
                      _buildCardTable(),
                      const SizedBox(height: 16),
                      if (_state == 'playing') _buildActionButtons(),
                      if (_state == 'result' && !_cashedOut && _showResult) _buildResultUI(),
                    ],
                    const SizedBox(height: 24),
                    if (_cashedOut) _buildCashedOutBanner()
                    else if (_state == 'result' && _showResult) _buildCashOutButton()
                    else if (_state == 'idle') _buildCashOutButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

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
            'Stack.IT',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A3A3C)),
            ),
            child: Text(
              '$_handsWon/$_handsPlayed Won',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceBar() {
    final profit = _balance - 100;
    final profitColor = profit >= 0 ? widget.theme.correct : Colors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.theme.correct.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Balance', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                '\$$_balance',
                style: TextStyle(color: widget.theme.correct, fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Profit', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                '${profit >= 0 ? '+' : ''}\$$profit',
                style: TextStyle(color: profitColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBettingUI() {
    return Column(
      children: [
        const Text('Place Your Bet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [5, 10, 25, 50].map((amount) {
            final selected = _betAmount == amount;
            return GestureDetector(
              onTap: amount <= _balance ? () => setState(() => _betAmount = amount) : null,
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
                    color: amount > _balance ? Colors.grey : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList()
            ..add(
              GestureDetector(
                onTap: () => setState(() => _betAmount = _balance),
                child: Container(
                  width: 70,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _betAmount == _balance ? widget.theme.present : const Color(0xFF2A2A2B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _betAmount == _balance ? widget.theme.present : const Color(0xFF3A3A3C),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('All In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ),
        const SizedBox(height: 12),
        Slider(
          value: _betAmount.toDouble().clamp(1, _balance.toDouble()),
          min: 1,
          max: _balance.toDouble(),
          divisions: _balance > 1 ? _balance - 1 : 1,
          activeColor: widget.theme.correct,
          inactiveColor: const Color(0xFF3A3A3C),
          onChanged: (v) => setState(() => _betAmount = v.round()),
        ),
        Text('Bet: \$$_betAmount', style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _loading ? null : _placeBet,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.correct,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Deal — \$$_betAmount',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeckIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Visual deck stack (3 overlapping face-down cards)
          SizedBox(
            width: 44,
            height: 40,
            child: Stack(
              children: [
                if (_deckRemaining > 2)
                  Positioned(
                    left: 0,
                    top: 4,
                    child: _buildMiniCardBack(),
                  ),
                if (_deckRemaining > 1)
                  Positioned(
                    left: 4,
                    top: 2,
                    child: _buildMiniCardBack(),
                  ),
                if (_deckRemaining > 0)
                  Positioned(
                    left: 8,
                    top: 0,
                    child: _buildMiniCardBack(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_shuffling)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.theme.present,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Shuffling...',
                  style: TextStyle(color: widget.theme.present, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            )
          else
            Text(
              '$_deckRemaining cards remaining',
              style: TextStyle(
                color: _deckRemaining <= 10 ? widget.theme.present : Colors.grey,
                fontSize: 13,
                fontWeight: _deckRemaining <= 10 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniCardBack() {
    return Container(
      width: 28,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF2C5F8A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Center(
        child: Container(
          width: 18,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.white12),
          ),
        ),
      ),
    );
  }

  /// Player wins: Blackjack, You Win!, Dealer Busts!
  bool _isPlayerWin() {
    return _result.contains('Blackjack') ||
        _result.contains('You Win') ||
        _result.contains('Dealer Busts');
  }

  /// Dealer wins: You Lose, Bust! (player bust), Dealer Blackjack
  bool _isDealerWin() {
    return _result.contains('You Lose') ||
        _result.contains('Bust!') ||
        _result.contains('Dealer Blackjack');
  }

  Widget _buildCardTable() {
    return Column(
      children: [
        // Dealer's hand
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_state == 'result' && _isDealerWin())
                  ? widget.theme.correct
                  : const Color(0xFF3A3A3C),
              width: (_state == 'result' && _isDealerWin()) ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Dealer', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const Spacer(),
                  if (_state == 'result' || _displayedDealerValue > 0)
                    Text('$_displayedDealerValue', style: TextStyle(color: widget.theme.present, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedHand(
                cards: _dealerCards,
                revealedCount: _isInitialLoad ? _dealerCards.length : _previousDealerCardCount,
                animateNewCards: !_isInitialLoad,
                delayBetweenCards: const Duration(milliseconds: 550),
                onCardFlipped: (index) {
                  // Only update progressively during active play.
                  // On game over, the value was already set authoritatively from server.
                  if (_state != 'result') {
                    setState(() {
                      // Only count non-hidden cards toward the displayed value
                      final visibleCards = _dealerCards
                          .sublist(0, index + 1)
                          .where((c) => c['rank'] != 'hidden')
                          .toList();
                      _displayedDealerValue = _calculateHandValue(visibleCards);
                    });
                  }
                },
                onAllFlipsComplete: () => setState(() => _isAnimating = false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Player's hand
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_state == 'result' && _isPlayerWin())
                  ? widget.theme.correct
                  : widget.theme.correct.withOpacity(0.3),
              width: (_state == 'result' && _isPlayerWin()) ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('You', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const Spacer(),
                  Text('$_displayedPlayerValue', style: TextStyle(color: widget.theme.correct, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedHand(
                cards: _playerCards,
                revealedCount: _isInitialLoad ? _playerCards.length : _previousPlayerCardCount,
                animateNewCards: !_isInitialLoad,
                delayBetweenCards: const Duration(milliseconds: 550),
                onCardFlipped: (index) {
                  setState(() {
                    _displayedPlayerValue = _calculateHandValue(
                      _playerCards.sublist(0, index + 1),
                    );
                  });
                },
                onAllFlipsComplete: () => setState(() => _isAnimating = false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Bet: \$$_currentBet', style: TextStyle(color: widget.theme.present, fontSize: 14)),
      ],
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

  Widget _buildActionButtons() {
    final canDouble = _playerCards.length == 2 && _balance >= _currentBet;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (_loading || _isAnimating) ? null : _hit,
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
              onPressed: (_loading || _isAnimating) ? null : _stand,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3A3A3C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Stand', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        if (canDouble) ...[
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: (_loading || _isAnimating) ? null : _double,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.correct,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Double', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultUI() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Text(
            _result,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _balance > 0 ? () => setState(() {
              _state = 'idle';
              _error = null;
              _showResult = false;
              _displayedPlayerValue = 0;
              _displayedDealerValue = 0;
              _playerCards = [];
              _dealerCards = [];
              _previousPlayerCardCount = 0;
              _previousDealerCardCount = 0;
            }) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.correct,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              _balance > 0 ? 'Next Hand' : 'Busted — No Balance',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCashOutButton() {
    if (_balance <= 0) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: _loading ? null : _cashOut,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: widget.theme.present),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          'Cash Out — \$$_balance',
          style: TextStyle(color: widget.theme.present, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCashedOutBanner() {
    final profit = _balance - 100;
    final profitColor = profit >= 0 ? widget.theme.correct : Colors.red;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: profitColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: profitColor.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: profitColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Cashed Out',
                    style: TextStyle(color: profitColor, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Profit: ${profit >= 0 ? '+' : ''}\$$profit  •  $_handsPlayed hands, $_handsWon won',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: widget.onBack,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.correct,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Back to Lobby', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
