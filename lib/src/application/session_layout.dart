/// 树的叶节点是会话组，分支保存拆分方向与比例。
sealed class SessionLayout {
  Iterable<SessionGroup> get groups;
  Map<String, Object?> toJson();

  static SessionLayout? fromJson(Object? value, [int depth = 0]) {
    if (value is! Map<String, dynamic> || depth > 64) return null;
    final first = fromJson(value['first'], depth + 1);
    final second = fromJson(value['second'], depth + 1);
    if (first != null && second != null) {
      final ratio = value['ratio'];
      return SessionSplit(
        first,
        second,
        horizontal: value['horizontal'] == true,
        ratio: ratio is num ? ratio.toDouble().clamp(0.1, 0.9) : 0.5,
      );
    }
    final tabs = value['tabs'];
    if (tabs is! List) return first ?? second;
    final active = value['active'];
    return SessionGroup(
      tabs.whereType<String>(),
      active is String ? active : null,
    );
  }

  SessionLayout replace(SessionLayout target, SessionLayout replacement) {
    if (identical(this, target)) return replacement;
    if (this case final SessionSplit split) {
      split.first = split.first.replace(target, replacement);
      split.second = split.second.replace(target, replacement);
    }
    return this;
  }

  SessionLayout? pruneEmpty() {
    return switch (this) {
      SessionGroup(:final tabs) => tabs.isEmpty ? null : this,
      final SessionSplit split => split._prune(),
    };
  }

  SessionGroup? neighbor(SessionGroup group) {
    if (this is! SessionSplit) return null;
    final split = this as SessionSplit;
    if (split.first.groups.contains(group)) {
      return split.first.neighbor(group) ?? split.second.groups.first;
    }
    if (split.second.groups.contains(group)) {
      return split.second.neighbor(group) ?? split.first.groups.last;
    }
    return null;
  }
}

class SessionGroup extends SessionLayout {
  SessionGroup([Iterable<String> tabs = const [], String? selection])
    : tabs = tabs.toList() {
    active = this.tabs.contains(selection) ? selection : this.tabs.firstOrNull;
  }

  final List<String> tabs;
  String? active;

  void add(String id) {
    tabs.add(id);
    active = id;
  }

  void remove(String id) {
    final index = tabs.indexOf(id);
    if (index == -1) return;
    tabs.removeAt(index);
    if (active == id) {
      active = tabs.isEmpty ? null : tabs[index.clamp(0, tabs.length - 1)];
    }
  }

  @override
  Iterable<SessionGroup> get groups => [this];

  @override
  Map<String, Object?> toJson() => {'tabs': tabs, 'active': active};
}

class SessionSplit extends SessionLayout {
  SessionSplit(
    this.first,
    this.second, {
    required this.horizontal,
    this.ratio = 0.5,
  });
  SessionLayout first, second;
  final bool horizontal;
  double ratio;

  SessionLayout? _prune() {
    final left = first.pruneEmpty();
    final right = second.pruneEmpty();
    if (left == null || right == null) return left ?? right;
    first = left;
    second = right;
    return this;
  }

  @override
  Iterable<SessionGroup> get groups sync* {
    yield* first.groups;
    yield* second.groups;
  }

  @override
  Map<String, Object?> toJson() => {
    'first': first.toJson(),
    'second': second.toJson(),
    'horizontal': horizontal,
    'ratio': ratio,
  };
}

enum SessionDrop { tabs, left, right, top, bottom }
