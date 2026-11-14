String nextDraftName(String prefix, Iterable<String> existing) {
  final names = existing.toSet();
  var index = 1;
  while (names.contains('$prefix $index')) {
    index++;
  }
  return '$prefix $index';
}
