/// Red numbers on a European roulette wheel
const Set<int> redNumbers = {
  1, 3, 5, 7, 9, 12, 14, 16, 18,
  19, 21, 23, 25, 27, 30, 32, 34, 36,
};

/// European wheel pocket order (physical layout)
const List<int> wheelOrder = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36,
  11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9,
  22, 18, 29, 7, 28, 12, 35, 3, 26,
];

/// Get the color of a roulette number
String getNumberColor(int number) {
  if (number == 0) return 'green';
  return redNumbers.contains(number) ? 'red' : 'black';
}

/// Payout multipliers for display purposes
const Map<String, int> payoutMultipliers = {
  'straight': 35,
  'red': 1,
  'black': 1,
  'odd': 1,
  'even': 1,
  'high': 1,
  'low': 1,
};
