import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_theme.dart';
import 'solitaire_service.dart';
import 'widgets/playing_card.dart';

// ─── Selection descriptor ────────────────────────────────────────────────────

class _Selection {
  final String zone; // 'tableau' | 'waste' | 'foundation'
  final int? col;
  final int? cardIndex;
  final String? suit;
  final String? card;

  const _Selection({
    required this.zone,
    this.col,
    this.cardIndex,
    this.suit,
    this.card,
  });

  bool matches(String z, {int? c, int? ci, String? s}) {
    if (zone != z) return false;
    if (c != null && col != c) return false;
    if (ci != null && cardIndex != ci) return false;
    if (s != null && suit != s) return false;
    return true;
  }
}

// ─── Main widget ─────────────────────────────────────────────────────────────

class SolitaireGameScreen extends StatefulWidget {
  final AppTheme theme;
  final VoidCallback onBack;
  final String nickname;
  final int userId;

  const SolitaireGameScreen({
    super.key,
    required this.theme,
    required this.onBack,
    required this.nickname,
    required this.userId,
  });

  @override
  State<SolitaireGameScreen> createState() => _SolitaireGameScreenState();
}

class _SolitaireGameScreenState extends State<SolitaireGameScreen> {
  // Game state from API
  int _stockCount = 0;
  List<String> _wasteTop = [];
  int _wasteCount = 0;
  Map<String, int> _foundations = {
    'hearts': 0,
    'diamonds': 0,
    'clubs': 0,
    'spades': 0,
  };
  List<Map<String, dynamic>> _tableau = [];
  int _moves = 0;
  int _elapsedSeconds = 0;
  String _status = 'in_progress';
  bool _started = false;

  // Result state (after win / give-up)
  int? _resultPoints;
  int? _resultMoves;
  int? _resultTime;

  // UI state
  _Selection? _selectedCard;
  bool _loading = true;
  String? _error;
  bool _won = false;

  // Timer
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_started && _status == 'in_progress') {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─── State loading ──────────────────────────────────────────────────────────

  Future<void> _loadState() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await SolitaireService.getToday();
    if (data == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load game. Check connection.';
      });
      return;
    }
    _applyState(data);
    setState(() => _loading = false);
  }

  void _applyState(Map<String, dynamic> data) {
    // Already completed / gave-up
    if (data['completed'] == true ||
        data['status'] == 'won' ||
        data['status'] == 'gave_up') {
      _status = data['status'] ?? 'won';
      _won = data['status'] == 'won';
      _resultPoints = data['points'] as int?;
      _resultMoves = data['moves'] as int?;
      _resultTime = data['time_seconds'] as int?;
      _moves = data['moves'] ?? _moves;
      _elapsedSeconds = data['time_seconds'] ?? _elapsedSeconds;
      return;
    }

    _status = data['status'] ?? 'in_progress';
    _started = data['started'] ?? false;
    _stockCount = data['stock_count'] ?? 0;
    _wasteCount = data['waste_count'] ?? 0;
    _moves = data['moves'] ?? 0;
    _elapsedSeconds = data['elapsed_seconds'] ?? 0;

    // waste_top: null | List
    final rawWaste = data['waste_top'];
    if (rawWaste == null) {
      _wasteTop = [];
    } else if (rawWaste is List) {
      _wasteTop = List<String>.from(rawWaste);
    } else {
      _wasteTop = [];
    }

    // foundations: {hearts: count, ...}
    final rawF = data['foundations'];
    if (rawF is Map) {
      _foundations = {
        'hearts': (rawF['hearts'] ?? 0) as int,
        'diamonds': (rawF['diamonds'] ?? 0) as int,
        'clubs': (rawF['clubs'] ?? 0) as int,
        'spades': (rawF['spades'] ?? 0) as int,
      };
    }

    // tableau
    final rawT = data['tableau'];
    if (rawT is List) {
      _tableau = rawT.map<Map<String, dynamic>>((col) {
        return {
          'hidden': (col['hidden'] ?? 0) as int,
          'visible': List<String>.from(col['visible'] ?? []),
        };
      }).toList();
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showError(String msg) {
    setState(() => _error = msg);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _error = null);
    });
  }

  // ─── Interaction logic ───────────────────────────────────────────────────────

  void _handleTap(String zone, {int? col, int? cardIndex, String? suit}) {
    if (_status != 'in_progress') return;

    // Tap stock → draw or recycle
    if (zone == 'stock') {
      _drawFromStock();
      return;
    }

    // If something is already selected → try to move to destination
    if (_selectedCard != null) {
      // Tap same card → deselect
      if (_selectedCard!.matches(zone, c: col, ci: cardIndex, s: suit)) {
        setState(() => _selectedCard = null);
        return;
      }

      // Destination: tableau column or foundation
      if (zone == 'tableau' || zone == 'foundation') {
        _attemptMove(
          from: _selectedCard!,
          toZone: zone,
          toCol: col,
          toSuit: suit,
        );
        return;
      }

      // Tapping another selectable card → change selection
      if (zone == 'waste' || zone == 'tableau') {
        // fall through to selection logic below
      }
    }

    // Select a card
    String? cardCode;
    if (zone == 'waste' && _wasteTop.isNotEmpty) {
      cardCode = _wasteTop.last;
    } else if (zone == 'tableau' && col != null && cardIndex != null) {
      final visible = List<String>.from(_tableau[col]['visible']);
      if (cardIndex < visible.length) cardCode = visible[cardIndex];
    } else if (zone == 'foundation' && suit != null) {
      // Selecting from foundation (to move back)
      cardCode = _foundationTopCard(suit);
    }

    if (cardCode == null) return;

    setState(() {
      _selectedCard = _Selection(
        zone: zone,
        col: col,
        cardIndex: cardIndex,
        suit: suit,
        card: cardCode,
      );
    });
  }

  String? _foundationTopCard(String suit) {
    final count = _foundations[suit] ?? 0;
    if (count == 0) return null;
    const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
    final suitLetter = suit[0]; // hearts→h, diamonds→d, clubs→c, spades→s
    return ranks[count - 1] + suitLetter;
  }

  Future<void> _attemptMove({
    required _Selection from,
    required String toZone,
    int? toCol,
    String? toSuit,
  }) async {
    // Build API from/to maps
    final Map<String, dynamic> fromMap = {'zone': from.zone};
    if (from.col != null) fromMap['col'] = from.col;
    if (from.cardIndex != null) fromMap['cardIndex'] = from.cardIndex;
    if (from.suit != null) fromMap['suit'] = from.suit;

    final Map<String, dynamic> toMap = {'zone': toZone};
    if (toCol != null) toMap['col'] = toCol;
    if (toSuit != null) toMap['suit'] = toSuit;

    setState(() => _selectedCard = null);

    final result = await SolitaireService.move(fromMap, toMap);
    if (result == null) {
      _showError('Network error');
      return;
    }
    if (result['ok'] == true) {
      final state = result['state'] as Map<String, dynamic>?;
      if (state != null) {
        setState(() => _applyState(state));
      }
      if (result['won'] == true) {
        setState(() {
          _won = true;
          _status = 'won';
          _resultPoints = result['points'] as int?;
          _resultMoves = result['moves'] as int?;
          _resultTime = result['time_seconds'] as int?;
        });
      }
    } else {
      _showError(result['error'] ?? 'Invalid move');
    }
  }

  Future<void> _drawFromStock() async {
    setState(() => _selectedCard = null);

    Map<String, dynamic>? result;
    if (_stockCount == 0) {
      result = await SolitaireService.recycle();
    } else {
      result = await SolitaireService.draw();
    }

    if (result == null) {
      _showError('Network error');
      return;
    }
    if (result['ok'] == true) {
      setState(() {
        _stockCount = result!['stock_count'] ?? _stockCount;
        _wasteCount = result['waste_count'] ?? _wasteCount;
        _moves = result['moves'] ?? _moves;
        final rawWaste = result['waste_top'];
        if (rawWaste == null) {
          _wasteTop = [];
        } else if (rawWaste is List) {
          _wasteTop = List<String>.from(rawWaste);
        }
        if (!_started) _started = true;
      });
    } else {
      _showError(result['error'] ?? 'Cannot draw');
    }
  }

  Future<void> _giveUp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.theme.absent,
        title: Text('Give Up?',
            style: TextStyle(color: widget.theme.textColor)),
        content: Text(
          "Are you sure? You'll only get 1 point.",
          style: TextStyle(color: widget.theme.textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: widget.theme.textColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Give Up',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await SolitaireService.giveUp();
    if (result == null) {
      _showError('Network error');
      return;
    }
    setState(() {
      _status = 'gave_up';
      _resultPoints = result['points'] as int?;
      _resultMoves = result['moves'] as int?;
      _resultTime = result['time_seconds'] as int?;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show result screen
    if (_status == 'won' || _status == 'gave_up') {
      return _buildResultScreen();
    }

    return Column(
      children: [
        _buildHeader(),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        if (_error != null) _buildErrorBanner(),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: _buildBody(),
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
            'Klond.IT',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            'Moves: $_moves',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          Text(
            _formatTime(_elapsedSeconds),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: Colors.redAccent.withOpacity(0.85),
      child: Text(
        _error!,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.theme.correct),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        _buildTopRow(),
        const SizedBox(height: 8),
        Expanded(child: _buildTableau()),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildResultScreen() {
    final isWon = _status == 'won';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildHeader(),
        const Divider(color: Color(0xFF3A3A3C), height: 1),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isWon ? '🎉 You Won!' : 'Game Over',
                    style: TextStyle(
                      color: isWon ? widget.theme.correct : widget.theme.textColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_resultPoints != null)
                    Text(
                      'Points earned: $_resultPoints',
                      style: TextStyle(
                          color: widget.theme.present,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 8),
                  if (_resultMoves != null)
                    Text('Moves: $_resultMoves',
                        style: TextStyle(
                            color: widget.theme.textColor, fontSize: 16)),
                  if (_resultTime != null)
                    Text('Time: ${_formatTime(_resultTime!)}',
                        style: TextStyle(
                            color: widget.theme.textColor, fontSize: 16)),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.theme.correct,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: widget.onBack,
                    child: const Text('Back to Lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Top row: stock + waste + foundations ────────────────────────────────────

  Widget _buildTopRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStock(),
          const SizedBox(width: 4),
          _buildWaste(),
          const Spacer(),
          ..._buildFoundations(),
        ],
      ),
    );
  }

  Widget _buildStock() {
    final isEmpty = _stockCount == 0;
    return GestureDetector(
      onTap: () => _handleTap('stock'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isEmpty)
            Container(
              width: 50,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white30),
              ),
              child: Icon(Icons.refresh,
                  color: Colors.white54, size: 28),
            )
          else
            PlayingCard(
              faceDown: true,
              theme: widget.theme,
              onTap: () => _handleTap('stock'),
            ),
          if (!isEmpty)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$_stockCount',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWaste() {
    if (_wasteTop.isEmpty) {
      return const SizedBox(width: 50, height: 70);
    }

    // Show up to 3 cards fanned: oldest at left, newest (playable) at front-right
    final display = _wasteTop.length > 3
        ? _wasteTop.sublist(_wasteTop.length - 3)
        : _wasteTop;
    final topIndex = display.length - 1;

    return SizedBox(
      width: 50 + (display.length - 1) * 14.0,
      height: 70,
      child: Stack(
        children: [
          for (int i = 0; i < display.length; i++)
            Positioned(
              left: i * 14.0,
              child: PlayingCard(
                card: display[i],
                faceDown: false,
                compact: i < topIndex, // compact for fanned cards, full for top (playable) card
                selected: i == topIndex &&
                    (_selectedCard?.zone == 'waste'),
                theme: widget.theme,
                onTap: i == topIndex
                    ? () => _handleTap('waste')
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildFoundations() {
    const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    const symbols = {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'};
    const ranks = ['A','2','3','4','5','6','7','8','9','10','J','Q','K'];

    return suits.map((suit) {
      final count = _foundations[suit] ?? 0;
      final topCard = count > 0
          ? ranks[count - 1] + suit[0]
          : null;
      final isSelected =
          _selectedCard?.zone == 'foundation' &&
          _selectedCard?.suit == suit;

      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: GestureDetector(
          onTap: () {
            if (_selectedCard != null &&
                _selectedCard!.zone != 'foundation') {
              _handleTap('foundation', suit: suit);
            } else if (count > 0) {
              _handleTap('foundation', suit: suit);
            }
          },
          child: topCard != null
              ? PlayingCard(
                  card: topCard,
                  selected: isSelected,
                  theme: widget.theme,
                )
              : Container(
                  width: 50,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.theme.correct.withOpacity(0.5)),
                  ),
                  child: Center(
                    child: Text(
                      symbols[suit]!,
                      style: TextStyle(
                        color: widget.theme.correct.withOpacity(0.6),
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
        ),
      );
    }).toList();
  }

  // ─── Tableau ─────────────────────────────────────────────────────────────────

  Widget _buildTableau() {
    if (_tableau.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int col = 0; col < _tableau.length; col++)
            Expanded(child: _buildColumn(col)),
        ],
      ),
    );
  }

  Widget _buildColumn(int col) {
    final colData = _tableau[col];
    final hidden = colData['hidden'] as int;
    final visible = List<String>.from(colData['visible'] as List);

    // Tap empty column (tappable destination for a King)
    if (hidden == 0 && visible.isEmpty) {
      return GestureDetector(
        onTap: () => _handleTap('tableau', col: col, cardIndex: 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: PlayingCard(
            isEmpty: true,
            theme: widget.theme,
            onTap: () => _handleTap('tableau', col: col, cardIndex: 0),
          ),
        ),
      );
    }

    const hiddenOverlap = 12.0;
    const visibleOverlap = 25.0;
    final totalHeight = hidden * hiddenOverlap +
        (visible.isEmpty ? 0 : (visible.length - 1) * visibleOverlap + 70);

    return GestureDetector(
      // Tapping blank area below column = destination tap
      onTap: () => _handleTap('tableau', col: col,
          cardIndex: visible.isEmpty ? 0 : visible.length - 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          width: double.infinity,
          height: totalHeight > 0 ? totalHeight : 70,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Hidden face-down cards
              for (int i = 0; i < hidden; i++)
                Positioned(
                  top: i * hiddenOverlap,
                  left: 0,
                  right: 0,
                  child: PlayingCard(
                    faceDown: true,
                    theme: widget.theme,
                  ),
                ),

              // Visible face-up cards
              for (int i = 0; i < visible.length; i++)
                Positioned(
                  top: hidden * hiddenOverlap + i * visibleOverlap,
                  left: 0,
                  right: 0,
                  child: _buildVisibleCard(col, visible, i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisibleCard(int col, List<String> visible, int i) {
    final isSelected = _selectedCard != null &&
        _selectedCard!.zone == 'tableau' &&
        _selectedCard!.col == col &&
        _selectedCard!.cardIndex != null &&
        i >= _selectedCard!.cardIndex!;

    return PlayingCard(
      card: visible[i],
      compact: i < visible.length - 1, // compact for all except the last (fully visible) card
      selected: isSelected,
      theme: widget.theme,
      onTap: () => _handleTap('tableau', col: col, cardIndex: i),
    );
  }

  // ─── Bottom bar ──────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            onPressed: _giveUp,
            child: const Text('Give Up'),
          ),
        ],
      ),
    );
  }
}
