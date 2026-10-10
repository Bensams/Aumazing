/// Internal keys for questionnaires, questions and answers, made from the
/// words a practitioner typed (AUM-356), so nobody has to invent
/// `lowercase_with_underscores` names themselves.
///
/// Keys only need to be stable and unique; they are never shown to parents.
library;

const _plain = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// [words] as lowercase letters, numbers and `_`, cut at a word break to at
/// most [maxLength] characters. Empty when [words] has no letters or digits.
String slugFor(String words, {int maxLength = 32}) {
  final lower = words.toLowerCase().split('').map((c) => _plain[c] ?? c).join();
  final slug = lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.length <= maxLength) return slug;
  final cut = slug.substring(0, maxLength);
  final lastBreak = cut.lastIndexOf('_');
  return lastBreak > 0 ? cut.substring(0, lastBreak) : cut;
}

/// A key for [words] not already in [taken], which it is then added to.
/// Uses [fallback] when [words] gives no key, and adds `_2`, `_3`… on a
/// clash.
String uniqueSlug(
  String words,
  Set<String> taken, {
  required String fallback,
  int maxLength = 32,
}) {
  final slug = slugFor(words, maxLength: maxLength);
  final base = slug.isEmpty ? fallback : slug;
  var key = base;
  for (var n = 2; taken.contains(key); n++) {
    key = '${base}_$n';
  }
  taken.add(key);
  return key;
}
