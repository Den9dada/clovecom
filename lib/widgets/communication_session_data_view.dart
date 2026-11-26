import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show
        BoxHitTestEntry,
        BoxHitTestResult,
        BoxParentData,
        ClearSelectionEvent,
        PaintingContext,
        PipelineOwner,
        PointerSignalEventListener,
        RenderObjectVisitor,
        RenderParagraph,
        RenderProxyBox,
        RenderPointerListener,
        RenderShiftedBox,
        Selectable,
        SelectionEvent,
        SelectionHandler,
        SelectionRegistrar,
        SelectionResult,
        ViewportOffset;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart'
    show AttributedString, SemanticsConfiguration, SemanticsProperties;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../src/application/communication_sessions.dart';
import '../src/application/session_history.dart';
import '../ui/desktop_theme.dart';
import '../ui/theme/app_theme_controller.dart';
import '../ui/theme/terminal_color_schemes.dart';
import '../ui/theme/terminal_text_highlighter.dart';
import '../ui/widgets/ds_toast.dart';
import 'communication_history_window.dart';
import 'communication_session_rows.dart';

part 'communication_session_gutter.dart';
part 'communication_session_horizontal_text.dart';

class CommunicationSessionDataView extends StatefulWidget {
  const CommunicationSessionDataView({
    super.key,
    required this.session,
    required this.saveDisplay,
    required this.layoutMenu,
    this.sendSettings,
    this.connectionAction,
  });
  final OpenCommunicationSession session;
  final VoidCallback saveDisplay;
  final List<Widget> layoutMenu;
  final Widget? connectionAction;
  final List<Widget> Function(VoidCallback refresh)? sendSettings;

  @override
  State<CommunicationSessionDataView> createState() => _DataViewState();
}

typedef _SessionRowStyle = ({
  _GutterStyle gutterText,
  double gutter,
  double columns,
  double padding,
  double? timestampWidth,
  double? numberWidth,
  double? directionWidth,
  bool timestampMillis,
  bool arrows,
  bool hex,
  bool wrap,
  double? noWrapWidth,
  double fontSize,
  TerminalColorScheme scheme,
  Color timestampColor,
  Color lineNumberColor,
  Color noticeColor,
  Color txColor,
  Color rxColor,
  Color rxTextColor,
});

class _DataViewState extends State<CommunicationSessionDataView> {
  static const _historyLoadSize = 160;
  static final _nonWideAscii = RegExp(r'[^0-9A-F ]');
  static const _seekPageBytes = 64 * 1024;
  static const _scrollbarWidth = 12.0;
  static const _lineHorizontalPadding = 6.0;
  static const _denseLiveBatch = 16;
  static const _centerKey = ValueKey('session-history-center');
  static final _mountedViews = <_DataViewState>{};
  static final _pendingLiveViews = <_DataViewState>{};
  static bool _liveFrameScheduled = false;

  static void _scheduleLiveFrame() {
    if (_liveFrameScheduled || _pendingLiveViews.isEmpty) return;
    _liveFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _liveFrameScheduled = false;
      if (_pendingLiveViews.isEmpty) return;
      final view = _pendingLiveViews.first;
      _pendingLiveViews.remove(view);
      view._refreshLiveWindow();
      // 当前帧提交后再请求下一屏，避免构建尚未结束时提前请求下一帧。
      if (_pendingLiveViews.isNotEmpty) {
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => _scheduleLiveFrame(),
        );
      }
    });
  }

  late final _scroll = _HistoryScrollController(
    () => !_following && !_correcting && _scrollbarPreview.value == null,
  );
  // 各行持有独立的横向位置，移出视口后无需写入共用的页面存储。
  final _horizontalScroll = ScrollController(keepScrollOffset: false);
  late final _rowSelection = _SessionSelectionDelegate(_visibleTextLayouts);
  bool _selectionLayoutPending = false;
  final _viewportKey = GlobalKey();
  final _scrollbarPreview = ValueNotifier<double?>(null);
  final _scrollbarAnchor = ValueNotifier<int?>(null);
  int? _pendingAnchorGeneration;
  final _scrollbarDimensions =
      ValueNotifier<
        ({
          double viewport,
          double? first,
          double? last,
          double? pixels,
          bool atBeginning,
          bool atTail,
        })?
      >(null);
  int? _seekTarget;
  (int, int)? _activeSeekTarget;
  bool _seeking = false, _seekScheduled = false;
  bool _preloadingOldest = false;
  double _dragOffset = 0, _wheelRemainder = 0;
  final _viewportChanges = ValueNotifier(0);
  final _chromeChanges = ValueNotifier(0);
  (String?, bool, int, int)? _chromeIssue;
  Timer? _chromeTimer;
  final _mountedRows = HashMap<(int, int), BuildContext>();
  final _projection = SessionDisplayRows();
  // 行索引淘汰记录后，弱键不会为该记录额外保留组件。
  Expando<Widget> _rowWidgets = Expando<Widget>();
  _SessionRowStyle? _rowStyle;
  Widget? _hexPrototype;
  Text? _lastSentText;
  final _shortLineWidths = <String, double?>{};
  late ({
    TextStyle notice,
    TextStyle sent,
    TextStyle received,
    TextStyle receivedPlain,
  }) _lineStyles;
  final _gutterText = _GutterTextCache();
  final _visibleTextLayouts = _VisibleTextLayouts();
  final _timestampLabel = SessionTimestampLabel();
  final _historyWindow = SessionHistoryWindow();
  bool _windowSkippedReceive = false;
  List<SessionRecord> get _window => _historyWindow.records;
  List<SessionRecord>? _fixedHeightWindow;
  bool _historySeekLayout = false;
  (int, int)? _center;
  int _generation = 0, _historyGeneration = 0;
  int? _oldestRead, _waitingCursor;
  bool _loading = false, _following = false, _correcting = false;
  bool _expired = false, _tailLayout = false, _tailSyncScheduled = false;
  bool? _towardsOlder;
  final _contextMenu = MenuController();
  Offset _menuPosition = Offset.zero;
  bool _showGutterMenu = false;
  String _selection = '', _menuSelection = '';
  OpenCommunicationSession get session => widget.session;
  SessionDisplay get display => session.display;
  bool get _followingSplitRows =>
      _following &&
      _selection.isEmpty &&
      !display.wrap &&
      _projection.hasSplitRecords;

  @override
  void initState() {
    super.initState();
    _mountedViews.add(this);
    PaintingBinding.instance.systemFonts.addListener(
      _visibleTextLayouts.invalidate,
    );
    _scroll
      ..addListener(_scheduleSelectionLayout)
      ..addListener(_trackScrollbarPosition);
    session.addListener(_refresh);
    _openView();
  }

  @override
  void didUpdateWidget(covariant CommunicationSessionDataView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == session) return;
    oldWidget.session.removeListener(_refresh);
    session.addListener(_refresh);
    _openView();
  }

  @override
  void dispose() {
    session.removeListener(_refresh);
    _mountedViews.remove(this);
    _pendingLiveViews.remove(this);
    _viewportChanges.dispose();
    _chromeTimer?.cancel();
    _chromeChanges.dispose();
    _scrollbarPreview.dispose();
    _scrollbarAnchor.dispose();
    _scrollbarDimensions.dispose();
    _gutterText.dispose();
    PaintingBinding.instance.systemFonts.removeListener(
      _visibleTextLayouts.invalidate,
    );
    _visibleTextLayouts.invalidate();
    _scroll.dispose();
    _horizontalScroll.dispose();
    _rowSelection.dispose();
    super.dispose();
  }

  void _scheduleSelectionLayout() {
    if (_selectionLayoutPending || !_rowSelection.value.hasSelection) return;
    _selectionLayoutPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionLayoutPending = false;
      if (mounted) _rowSelection.layoutDidChange();
    });
  }

  void _openView() {
    _chromeTimer?.cancel();
    _chromeTimer = null;
    _chromeIssue = null;
    _resetWindow();
    if (session.historyAnchor case final anchor?) {
      _following = false;
      _tailLayout = false;
      _scroll.nextLayoutOffset = null;
      _replaceHistoryWindow(const []);
      unawaited(_restore(anchor));
    } else if (_following) {
      _scrollToTail();
    }
  }

  void _resetWindow() {
    _pendingLiveViews.remove(this);
    _generation++;
    _scroll.nextLayoutOffset = null;
    _seekTarget = null;
    _scrollbarPreview.value = null;
    _scroll.cancelPendingWheel();
    _wheelRemainder = 0;
    _historyGeneration = session.history.generation;
    _replaceHistoryWindow(session.latest);
    _center = null;
    _following = display.follow;
    _tailSyncScheduled = false;
    _tailLayout = false;
    if (_following && _window.isNotEmpty) {
      _projection.replace(
        _window,
        hideReceive: display.hideReceive,
        liveTail: true,
      );
      _tailLayout = _estimatedOverflow();
    } else {
      _projection.replace(const [], hideReceive: false);
    }
    if (_tailLayout || _window.isEmpty) _scroll.nextLayoutOffset = 0;
    _lastSentText = null;
    _oldestRead = null;
    _waitingCursor = null;
    _towardsOlder = null;
    _loading = false;
    _correcting = false;
    _expired = false;
    _selection = '';
  }

  void _refreshChrome() {
    final issue = (
      session.history.error,
      session.history.truncated,
      session.missedInputPackets,
      session.serialReceiveOverruns,
    );
    final issueChanged = issue != _chromeIssue;
    _chromeIssue = issue;
    if (_following || issueChanged) {
      _chromeTimer?.cancel();
      _chromeTimer = null;
      _chromeChanges.value++;
      return;
    }
    _chromeTimer ??= Timer(const Duration(milliseconds: 100), () {
      _chromeTimer = null;
      _chromeChanges.value++;
    });
  }

  void _refresh() {
    _refreshChrome();
    if (_historyGeneration != session.history.generation) {
      setState(_resetWindow);
      if (_following) _scrollToTail();
      return;
    }
    final latest = session.latestSequence;
    final shown = _window.lastOrNull?.sequence;
    if (!_loading && shown == null && latest != null) {
      _replaceHistoryWindow(session.latest);
      _viewportChanges.value++;
      if (_following) _scrollToTail();
    } else if (_following && _selection.isEmpty && shown != latest) {
      final pending = (latest ?? 0) - (shown ?? 0);
      // 多个视图同时跟随拆行长包时，错开各自的布局工作。
      final dense =
          pending >= _denseLiveBatch ||
          (_followingSplitRows &&
              _mountedViews.any(
                (view) => view != this && view._followingSplitRows,
              ));
      if (!dense && !_pendingLiveViews.contains(this)) {
        _refreshLiveWindow();
      } else {
        _pendingLiveViews.add(this);
        _scheduleLiveFrame();
      }
    } else if (_waitingCursor != null &&
        (session.history.publishedSequence != _waitingCursor ||
            !session.history.hasPending)) {
      _waitingCursor = null;
      _checkEdges();
    }
  }

  void _refreshLiveWindow() {
    if (!_following ||
        _selection.isNotEmpty ||
        _historyGeneration != session.history.generation ||
        _window.lastOrNull?.sequence == session.latestSequence) {
      return;
    }
    _replaceHistoryWindow(session.latest);
    _center = null;
    if (!display.hideReceive ||
        _projection.replace(_window, hideReceive: true, liveTail: true)) {
      _viewportChanges.value++;
    }
    _scrollToTail();
  }

  void _returnToLatest() {
    session.historyAnchor = null;
    setState(_resetWindow);
    _scrollToTail(force: true);
  }

  bool _estimatedOverflow() {
    final count = _projection.length;
    if (count == 0) return false;
    final rowHeight = display.fontSize * 1.4 + 2;
    final viewport = _scroll.hasClients && _scroll.position.hasViewportDimension
        ? _scroll.position.viewportDimension
        : null;
    return viewport != null ? count * rowHeight > viewport + 1 : count >= 64;
  }

  bool _hasTopGapInTail() {
    final first = _rows.firstOrNull;
    if (first == null) return true;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final row = _mountedRows[first.id]?.findRenderObject();
    if (viewport is! RenderBox ||
        !viewport.hasSize ||
        row is! RenderBox ||
        !row.attached ||
        !row.hasSize) {
      return false;
    }
    return row.localToGlobal(Offset.zero, ancestor: viewport).dy > 0.5;
  }

  void _syncTailLayout(ScrollMetrics metrics) {
    if (_tailSyncScheduled || !_following || _selection.isNotEmpty) return;
    final needsPromote = !_tailLayout && metrics.maxScrollExtent > 0.5;
    final needsCheckDemote =
        _tailLayout &&
        metrics.minScrollExtent == 0 &&
        metrics.maxScrollExtent == 0;
    if (!needsPromote && !needsCheckDemote) return;
    _tailSyncScheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tailSyncScheduled = false;
      if (!mounted ||
          generation != _generation ||
          !_following ||
          _selection.isNotEmpty ||
          !_scroll.hasClients) {
        return;
      }
      final position = _scroll.position;
      if (!position.hasContentDimensions) return;
      if (!_tailLayout) {
        if (position.maxScrollExtent <= 0.5) return;
        if (position.extentAfter >= 1) _jump(position.maxScrollExtent);
        setState(() {
          _tailLayout = true;
          _center = null;
          _scroll.nextLayoutOffset = 0;
        });
      } else if (position.minScrollExtent == 0 &&
          position.maxScrollExtent == 0 &&
          _hasTopGapInTail()) {
        setState(() {
          _tailLayout = false;
          _center = null;
          _scroll.nextLayoutOffset = 0;
        });
      }
    });
  }

  void _scrollToTail({bool force = false}) {
    if (_tailLayout && !force) return;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          _scroll.hasClients &&
          (force || (_following && _selection.isEmpty))) {
        final position = _scroll.position;
        if (position.hasContentDimensions) {
          _jump(position.maxScrollExtent);
          _syncTailLayout(position);
        }
      }
    });
  }

  void _jump(double offset) {
    final position = _scroll.position;
    _correcting = true;
    try {
      position.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    } finally {
      _correcting = false;
    }
  }

  ({int sequence, int byteOffset, double offset})? _visibleAnchor() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    // 行按记录序号与字节偏移排列，第一个可见行就是锚点。
    ({int sequence, int byteOffset, double offset})? best;
    for (final entry in _mountedRows.entries) {
      final key = entry.key;
      if (best != null &&
          (key.$1 > best.sequence ||
              (key.$1 == best.sequence && key.$2 >= best.byteOffset))) {
        continue;
      }
      final row = entry.value.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) continue;
      final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top >= viewport.size.height || top + row.size.height <= 0) continue;
      best = (sequence: key.$1, byteOffset: key.$2, offset: top);
    }
    return best;
  }

  void _rememberAnchor() {
    if (_following) return;
    if (_visibleAnchor() case final anchor?) {
      session.historyAnchor = anchor;
      _scrollbarAnchor.value = anchor.sequence;
    }
  }

  void _scheduleAnchorUpdate() {
    final generation = _generation;
    if (_following || _pendingAnchorGeneration == generation) return;
    _pendingAnchorGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingAnchorGeneration != generation) return;
      _pendingAnchorGeneration = null;
      if (mounted && generation == _generation && !_correcting) {
        _rememberAnchor();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _replaceHistoryWindow(List<SessionRecord> records) {
    _historyWindow.replace(records);
    _historySeekLayout = false;
    _windowSkippedReceive = false;
  }

  void _recenter(({int sequence, int byteOffset, double offset}) anchor) {
    _scroll.cancelPendingWheel();
    _fixedHeightWindow = null;
    _tailLayout = false;
    _center = (anchor.sequence, anchor.byteOffset);
    _scroll.nextLayoutOffset = -anchor.offset;
    final generation = _generation;
    _correcting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _correcting = false;
      if (_scroll.hasClients) {
        final position = _scroll.position;
        if (_scroll.nextLayoutOffset != null || position.outOfRange) {
          _scroll.nextLayoutOffset = null;
          _jump(-anchor.offset);
          // 回退到像素跳转时仍需等待新的行布局。
          _scheduleAnchorUpdate();
        } else {
          // 本帧已应用中心与偏移，直接记录已布局后的可见锚点。
          _rememberAnchor();
        }
      }
      _checkEdges();
    });
  }

  Future<void> _restore(
    ({int sequence, int byteOffset, double offset}) anchor,
  ) async {
    final generation = _generation;
    _loading = true;
    try {
      final history = session.history;
      final live = session.latest;
      final retainedLive = live.any(
        (record) => record.sequence == anchor.sequence,
      );
      final page = await history.readPage(after: anchor.sequence - 1);
      if (!mounted || generation != _generation) return;
      final pageContainsAnchor = page.records.any(
        (record) => record.sequence == anchor.sequence,
      );
      final records = retainedLive && !pageContainsAnchor ? live : page.records;
      final anchorFound = records.any(
        (record) => record.sequence == anchor.sequence,
      );
      setState(() {
        _replaceHistoryWindow(records.isEmpty ? live : records);
        if (anchorFound) {
          _recenter(anchor);
        } else if (_window.isNotEmpty) {
          _expired = page.oldest != null && anchor.sequence < page.oldest!;
          _recenter((
            sequence: _window.first.sequence,
            byteOffset: 0,
            offset: 0,
          ));
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) _reportReadError(error);
    } finally {
      if (mounted && generation == _generation) _loading = false;
    }
  }

  bool _onScroll(ScrollNotification event) {
    if (event.depth != 0 ||
        _correcting ||
        _historyGeneration != session.history.generation) {
      return false;
    }
    final delta = switch (event) {
      ScrollUpdateNotification(:final scrollDelta) => scrollDelta,
      OverscrollNotification(:final overscroll) => overscroll,
      _ => null,
    };
    if (delta != null && delta != 0) _scrollDirection(delta);
    if (event is ScrollEndNotification) {
      if (_scrollbarPreview.value == null &&
          !_following &&
          display.follow &&
          _towardsOlder == false &&
          _selection.isEmpty &&
          event.metrics.extentAfter < 1 &&
          _window.lastOrNull?.sequence == session.latestSequence) {
        final generation = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation && _towardsOlder == false) {
            _returnToLatest();
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
    return false;
  }

  void _scrollDirection(double delta) {
    if (_correcting || _historyGeneration != session.history.generation) return;
    _towardsOlder = delta < 0;
    if (delta < 0 && _following) {
      _following = false;
      // 滚动通知在布局后发出，工具栏在下一帧更新。
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) setState(() {});
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    // 一帧内合并滚动事件，并在新行完成布局后再读取锚点。
    _scheduleAnchorUpdate();
    _checkEdges();
  }

  void _scrollAtEdge(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        _scrollbarPreview.value != null ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    if (_wheelRemainder.sign != delta.sign) _wheelRemainder = 0;
    final position = _scroll.position as _HistoryScrollPosition;
    final target = position.projectedWheelOffset + delta;
    final excess =
        target -
        target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (excess != 0) {
      // 原生滚动只消费本窗口内的距离，补页后继续执行剩余的滚轮位移。
      _wheelRemainder += excess;
      _scrollDirection(delta);
    }
  }

  void _continueWheelScroll() {
    if (_wheelRemainder == 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    final previous = position.pixels;
    _jump(previous + _wheelRemainder);
    _wheelRemainder -= position.pixels - previous;
    if (_wheelRemainder.abs() < 1) _wheelRemainder = 0;
  }

  ({int first, int last})? get _historyRange {
    final diskFirst = session.history.oldestPublishedSequence;
    final liveFirst = session.firstLatestSequence;
    final first = diskFirst == null
        ? liveFirst
        : math.min(diskFirst, liveFirst ?? diskFirst);
    if (first == null) return null;
    return (
      first: first,
      last: math.max(
        session.history.publishedSequence,
        session.latestSequence ?? first,
      ),
    );
  }

  void _seekFraction(double fraction, int first, int last) {
    if (fraction >= 1) {
      if (_scrollbarPreview.value != 1) {
        _returnToLatest();
        _scrollbarPreview.value = 1;
      }
      return;
    }
    final target = first + ((last - first) * fraction).round();
    _scrollbarPreview.value = fraction;
    if (_seekTarget == target || _activeSeekTarget == (target, _generation)) {
      return;
    }
    _seekTarget = target;
    _scroll.cancelPendingWheel();
    _generation++;
    _scroll.nextLayoutOffset = null;
    _wheelRemainder = 0;
    _waitingCursor = null;
    _oldestRead = null;
    _towardsOlder = null;
    _following = false;
    _correcting = false;
    _selection = '';
    _loading = false;
    _requestHistorySeek();
  }

  void _requestHistorySeek() {
    if (!mounted || _seeking || _seekTarget == null) return;
    if (!_draggingScrollbar) {
      unawaited(_seekHistory());
      return;
    }
    if (_seekScheduled) return;
    _seekScheduled = true;
    // 帧开始时只处理最后一个拖动目标，已在内存中的记录可在本帧布局。
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _seekScheduled = false;
      if (mounted && !_seeking && _seekTarget != null) {
        unawaited(_seekHistory());
      }
    });
  }

  bool _jumpToMountedHistoryRow(int sequence) {
    if (!_scroll.hasClients ||
        (_windowSkippedReceive && !display.hideReceive)) {
      return false;
    }
    final position = _scroll.position;
    if (!position.hasContentDimensions) return false;
    final id = (sequence, 0);
    var rowId = id;
    var rowDistance = 0;
    if (!_mountedRows.containsKey(id) &&
        display.hex &&
        !display.wrap &&
        identical(_fixedHeightWindow, _window)) {
      final rows = _rows;
      final index = rows.indexOf(id);
      // 等高列表可以直接跳过尚未挂载的行。
      final reference = _mountedRows.keys.firstOrNull;
      final referenceIndex = reference == null ? null : rows.indexOf(reference);
      if (index != null && reference != null && referenceIndex != null) {
        rowId = reference;
        rowDistance = index - referenceIndex;
      }
    }
    final row = _mountedRows[rowId]?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (row is! RenderBox ||
        !row.attached ||
        !row.hasSize ||
        viewport is! RenderBox) {
      return false;
    }
    final leadingEdge = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final target =
        position.pixels + leadingEdge + rowDistance * row.size.height;
    // 超出已知滚动范围时，让常规分页提供目标之后的记录。
    if (!target.isFinite ||
        target < position.minScrollExtent ||
        target > position.maxScrollExtent) {
      return false;
    }
    _jump(target);
    _chromeChanges.value++;
    _scheduleAnchorUpdate();
    return true;
  }

  bool _jumpToResidentHistoryRow(int sequence) {
    if ((_windowSkippedReceive && !display.hideReceive) ||
        sequence < (_historyRange?.first ?? sequence) ||
        !_scroll.hasClients ||
        !_scroll.position.hasViewportDimension) {
      return false;
    }
    final rows = _rows;
    // 拆行报文按常规读页预算组织首屏。
    if (rows.hasSplitRecords) return false;
    final index = rows.indexOf((sequence, 0));
    if (index == null || index == 0) return false;
    // 目标后不足一屏时仍按普通路径定位和补页。
    final visible = _estimatedVisibleRows(_scroll.position.viewportDimension);
    if (rows.length - index < visible &&
        _window.last.sequence != session.latestSequence) {
      return false;
    }
    _towardsOlder = false;
    _recenter((sequence: sequence, byteOffset: 0, offset: 0));
    _viewportChanges.value++;
    _chromeChanges.value++;
    return true;
  }

  Future<void> _seekHistory() async {
    _seeking = true;
    try {
      while (_seekTarget != null) {
        final target = _seekTarget!;
        _seekTarget = null;
        final generation = _generation;
        _activeSeekTarget = (target, generation);
        final owner = session;
        final history = owner.history;
        try {
          var cursor = target - 1;
          var records = const <SessionRecord>[];
          var landed =
              mounted &&
              _historyGeneration == history.generation &&
              (_jumpToMountedHistoryRow(target) ||
                  _jumpToResidentHistoryRow(target));
          while (!landed &&
              mounted &&
              generation == _generation &&
              _historyGeneration == history.generation) {
            final live = owner.latest;
            var searchDisk = false;
            if (display.hideReceive) {
              final written = history.firstSentOrNoticeAtOrAfter(cursor + 1);
              final recent = live
                  .where(
                    (record) =>
                        record.sequence > cursor &&
                        (record.sent || record.packet == null),
                  )
                  .firstOrNull;
              final candidate = written == null
                  ? recent?.sequence
                  : math.min(written, recent?.sequence ?? written);
              if (candidate == null) break;
              cursor = candidate - 1;
              searchDisk =
                  candidate == written && candidate != recent?.sequence;
            }
            var fromDisk = false;
            if (!searchDisk &&
                live.isNotEmpty &&
                cursor >= live.first.sequence - 1) {
              records = live;
            } else {
              final page = await history.readPage(
                after: cursor,
                limit: _historyLoadSize,
                byteLimit: _seekPageBytes,
              );
              fromDisk = page.records.isNotEmpty;
              records = fromDisk ? page.records : live;
            }
            if (!mounted ||
                generation != _generation ||
                _historyGeneration != history.generation) {
              break;
            }
            final index = records.indexWhere(
              (record) =>
                  record.sequence > cursor &&
                  (!display.hideReceive ||
                      record.sent ||
                      record.packet == null),
            );
            if (index < 0) {
              final end = records.lastOrNull?.sequence;
              if (end == null || end <= cursor) break;
              cursor = end;
              continue;
            }
            final record = records[index];
            _replaceHistoryWindow(records);
            _historySeekLayout = true;
            // 首屏落位后按可见距离补齐后续记录。
            if (fromDisk) _towardsOlder = false;
            _recenter((sequence: record.sequence, byteOffset: 0, offset: 0));
            _viewportChanges.value++;
            _chromeChanges.value++;
            landed = true;
            break;
          }
          if (mounted && generation == _generation) {
            if (landed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    generation == _generation &&
                    !_draggingScrollbar) {
                  _scrollbarPreview.value = null;
                  _checkEdges();
                }
              });
            } else if (!_draggingScrollbar) {
              _scrollbarPreview.value = null;
            }
          }
        } catch (error) {
          if (mounted && generation == _generation) {
            _scrollbarPreview.value = null;
            _reportReadError(error);
          }
        }
        if (_draggingScrollbar) break;
      }
    } finally {
      _activeSeekTarget = null;
      _seeking = false;
      _requestHistorySeek();
    }
  }

  bool _draggingScrollbar = false;

  void _endHistoryDrag() {
    _draggingScrollbar = false;
    _requestHistorySeek();
    if (_scrollbarPreview.value == 1 || (!_seeking && !_correcting)) {
      _scrollbarPreview.value = null;
      _checkEdges();
    }
  }

  Future<void> _preloadOldestHistory() async {
    if (!mounted || !_following || _preloadingOldest) return;
    final history = session.history;
    final oldest = history.oldestPublishedSequence;
    final windowStart = _window.firstOrNull?.sequence;
    if (oldest == null || windowStart == null || oldest >= windowStart) return;

    _preloadingOldest = true;
    try {
      // 只预读一页。实际定位仍按当时的保留范围查询，并复用已完成或在途的分页。
      await history.readPage(
        after: oldest - 1,
        limit: _historyLoadSize,
        byteLimit: _seekPageBytes,
        skipReceiveEdge: display.hideReceive,
      );
    } catch (_) {
      // 预读失败由实际定位重新读取，并沿用现有的错误提示。
    } finally {
      _preloadingOldest = false;
    }
  }

  bool _coversHistory(({int first, int last}) range) =>
      (_window.firstOrNull?.sequence ?? range.last) <= range.first &&
      (_window.lastOrNull?.sequence ?? range.first) >= range.last;

  void _trackScrollbarPosition() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.hasViewportDimension && position.hasContentDimensions) {
      _updateScrollbarDimensions(position);
    }
  }

  void _updateScrollbarDimensions(ScrollMetrics metrics) {
    final range = _historyRange;
    final local = range != null && _coversHistory(range);
    // 全历史模式只关心可见记录和首尾边界，完整窗口才使用像素偏移。
    _scrollbarDimensions.value = (
      viewport: metrics.viewportDimension,
      first: local ? metrics.minScrollExtent : null,
      last: local ? metrics.maxScrollExtent : null,
      pixels: local ? metrics.pixels : null,
      atBeginning:
          !local &&
          range != null &&
          metrics.extentBefore < 1 &&
          (_window.firstOrNull?.sequence ?? range.last) <= range.first,
      atTail:
          !local &&
          range != null &&
          metrics.extentAfter < 1 &&
          (_window.lastOrNull?.sequence ?? 0) >= range.last,
    );
  }

  double _estimatedVisibleRows(double viewport) =>
      math.max(1.0, viewport / (display.fontSize * 1.4 + 2));

  Widget _historyScrollbar(ColorScheme colors, TerminalColorScheme scheme) =>
      ListenableBuilder(
    listenable: Listenable.merge([
      _chromeChanges,
      _scrollbarPreview,
      _scrollbarAnchor,
      _scrollbarDimensions,
    ]),
    builder: (context, _) {
      final range = _historyRange;
      if (range == null) {
        return const SizedBox.shrink();
      }
      final position = _scroll.hasClients ? _scroll.position : null;
      final viewport = position?.hasViewportDimension == true
          ? position!.viewportDimension
          : 0.0;
      final total = range.last - range.first + 1;
      final local =
          position?.hasContentDimensions == true && _coversHistory(range);
      final extent = local
          ? position!.maxScrollExtent - position.minScrollExtent
          : 0.0;
      if (local && extent <= 0) return const SizedBox.shrink();
      final visible = _estimatedVisibleRows(viewport);
      final atTail =
          position?.hasContentDimensions == true &&
          position!.extentAfter < 1 &&
          (_window.lastOrNull?.sequence ?? 0) >= range.last;
      final atBeginning =
          position?.hasContentDimensions == true &&
          position!.extentBefore < 1 &&
          (_window.firstOrNull?.sequence ?? range.last) <= range.first;
      final sequence = atBeginning
          ? range.first
          : session.historyAnchor?.sequence ??
                _window.firstOrNull?.sequence ??
                range.first;
      final fraction =
          _scrollbarPreview.value ??
          (local
              ? ((position!.pixels - position.minScrollExtent) / extent).clamp(
                  0.0,
                  1.0,
                )
              : _following || atTail || total == 1
              ? 1.0
              : ((sequence - range.first) / (total - 1)).clamp(0.0, 1.0));
      void seekFraction(double value) {
        final current = _historyRange;
        if (current == null) return;
        final currentPosition = _scroll.hasClients ? _scroll.position : null;
        if (currentPosition != null &&
            currentPosition.hasContentDimensions &&
            _coversHistory(current)) {
          _wheelRemainder = 0;
          final min = currentPosition.minScrollExtent;
          final extent = currentPosition.maxScrollExtent - min;
          currentPosition.jumpTo(min + extent * value);
        } else {
          _seekFraction(value, current.first, current.last);
        }
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final ratio = local
              ? viewport / (viewport + extent)
              : visible / total;
          final thumb = (height * ratio)
              .clamp(math.min(28.0, height), height)
              .toDouble();
          final travel = height - thumb;
          final top = travel * fraction;
          void seek(double y) {
            if (travel > 0) {
              seekFraction(((y - _dragOffset) / travel).clamp(0.0, 1.0));
            }
          }

          return Semantics(
            label: '会话历史滚动条',
            value: '${(fraction * 100).round()}%',
            increasedValue: travel > 0
                ? '${math.min(100, (fraction * 100).round() + 10)}%'
                : null,
            decreasedValue: travel > 0
                ? '${math.max(0, (fraction * 100).round() - 10)}%'
                : null,
            onIncrease: travel > 0
                ? () => seekFraction(math.min(1.0, fraction + 0.1))
                : null,
            onDecrease: travel > 0
                ? () => seekFraction(math.max(0.0, fraction - 0.1))
                : null,
            child: MouseRegion(
              cursor: travel > 0 ? SystemMouseCursors.click : MouseCursor.defer,
              onEnter: travel > 0 && !local
                  ? (_) => unawaited(_preloadOldestHistory())
                  : null,
              child: GestureDetector(
                key: ValueKey('session-history-scrollbar-${session.id}'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: (event) {
                  _dragOffset = thumb / 2;
                  seek(event.localPosition.dy);
                  _endHistoryDrag();
                },
                onVerticalDragStart: (event) {
                  _draggingScrollbar = true;
                  final y = event.localPosition.dy;
                  _dragOffset = y >= top && y <= top + thumb
                      ? y - top
                      : thumb / 2;
                },
                onVerticalDragUpdate: (event) => seek(event.localPosition.dy),
                onVerticalDragEnd: (_) => _endHistoryDrag(),
                onVerticalDragCancel: _endHistoryDrag,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color:
                            scheme.scrollbarTrack ?? colors.surfaceContainerLow,
                      ),
                    ),
                    Positioned(
                      top: top,
                      height: thumb,
                      left: 3,
                      right: 3,
                      child: DecoratedBox(
                        key: ValueKey('session-history-thumb-${session.id}'),
                        decoration: BoxDecoration(
                          color:
                              scheme.scrollbarThumb ??
                              colors.onSurfaceVariant.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  void _checkEdges() {
    if (_following ||
        _scrollbarPreview.value != null ||
        _loading ||
        _correcting ||
        _towardsOlder == null ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    final position = _scroll.position;
    final older = _towardsOlder!;
    final distance = older ? position.extentBefore : position.extentAfter;
    if (distance < math.max(480, position.viewportDimension * 3)) {
      unawaited(_loadPage(older: older));
    }
  }

  Future<void> _loadPage({required bool older}) async {
    final cursor = older
        ? _window.firstOrNull?.sequence
        : _window.lastOrNull?.sequence;
    if (cursor == null ||
        (older && cursor == _oldestRead) ||
        (!older && cursor == session.latestSequence)) {
      _wheelRemainder = 0;
      return;
    }
    final generation = _generation;
    final owner = session;
    _loading = true;
    var advanced = false;
    try {
      final history = owner.history;
      final page = await history.readPage(
        before: older ? cursor : null,
        after: older ? null : cursor,
        limit: _historyLoadSize,
        skipReceiveEdge: display.hideReceive,
      );
      if (!mounted ||
          generation != _generation ||
          _historyGeneration != history.generation ||
          _following ||
          _towardsOlder != older) {
        return;
      }
      var records = page.records;
      if (records.isEmpty) {
        final live = older ? const <SessionRecord>[] : owner.latest;
        final connectsToLive =
            live.isNotEmpty && live.first.sequence <= cursor + 1;
        final published = history.publishedSequence;
        // 已发布游标之后的记录无法再补到当前窗口的前面。
        if (history.hasPending &&
            !connectsToLive &&
            (!older || cursor - 1 > published)) {
          _waitingCursor = published;
          return;
        }
        if (older) {
          _oldestRead = cursor;
          if (_rows.firstOrNull case final row? when _wheelRemainder < 0) {
            // 变高的行尚未布局时，最小滚动偏移只是估算值。
            // 已确认没有更早记录后，直接以首行为中心兑现剩余滚轮位移。
            _wheelRemainder = 0;
            _recenter((sequence: row.id.$1, byteOffset: row.id.$2, offset: 0));
            _viewportChanges.value++;
          }
          return;
        }
        // 已读到磁盘尾部，随后接上仍在内存中的实时记录。
        final recent = live.where((record) => record.sequence > cursor);
        records =
            (display.hideReceive
                    ? recent.skipWhile((row) => !row.sent && row.packet != null)
                    : recent)
                .take(_historyLoadSize)
                .toList();
        if (records.isEmpty) return;
      }
      final anchor = _visibleAnchor();
      if (!older && page.oldest != null && cursor + 1 < page.oldest!) {
        _expired = true;
      }
      if (_rows.firstOrNull case final row?
          when !_tailLayout && _center == null) {
        _center = (row.record.sequence, row.start);
      }
      final previousLast = _window.last.sequence;
      if (display.hideReceive &&
          (older
              ? records.last.sequence + 1 < cursor
              : records.first.sequence > cursor + 1)) {
        _windowSkippedReceive = true;
      }
      _historyWindow.extend(
        records,
        older: older,
        anchorSequence: anchor?.sequence,
      );
      final center = _center;
      final tailMoved = _tailLayout && _window.last.sequence != previousLast;
      if (tailMoved ||
          (center != null && !_historyWindow.containsSequence(center.$1))) {
        if (anchor != null &&
            _historyWindow.containsSequence(anchor.sequence)) {
          _recenter(anchor);
        } else {
          _tailLayout = false;
          _center = null;
        }
      }
      advanced = older
          ? _window.first.sequence != cursor
          : _window.last.sequence != cursor;
      // 补页只更新数据区、历史范围和状态栏。
      _viewportChanges.value++;
      _chromeChanges.value++;
    } catch (error) {
      if (mounted && generation == _generation) _reportReadError(error);
    } finally {
      if (mounted && generation == _generation) {
        _loading = false;
        // 反向滚动后保留已读取的缓存，把窗口更新交给当前方向。
        if (_towardsOlder != older) _checkEdges();
      }
    }
    if (advanced) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) {
          _continueWheelScroll();
          _scheduleAnchorUpdate();
          _checkEdges();
        }
      });
    }
  }

  void _reportReadError(Object error) {
    showDsToast('读取历史失败：$error', kind: DsToastKind.error);
  }

  void _changeRows(VoidCallback change) {
    final anchor = _following ? null : _visibleAnchor();
    setState(() {
      change();
      if (anchor != null) {
        final rows = _rows;
        final index = rows.lowerBound((anchor.sequence, anchor.byteOffset));
        final row = index == rows.length ? rows.lastOrNull : rows[index];
        if (row != null) {
          _recenter((
            sequence: row.record.sequence,
            byteOffset: row.start,
            offset: anchor.offset,
          ));
        }
      }
    });
    if (_following) _scrollToTail();
  }

  void _toggleReceiveVisibility() {
    final reveal = display.hideReceive;
    final refill = reveal && _windowSkippedReceive && !_following;
    final anchor = refill
        ? _visibleAnchor() ??
              session.historyAnchor ??
              (sequence: _window.first.sequence, byteOffset: 0, offset: 0.0)
        : null;
    _generation++;
    _scroll.nextLayoutOffset = null;
    _scroll.cancelPendingWheel();
    _oldestRead = null;
    _waitingCursor = null;
    _seekTarget = null;
    _scrollbarPreview.value = null;
    _loading = false;
    _correcting = false;
    _wheelRemainder = 0;
    if (anchor == null) {
      _changeRows(() => display.hideReceive = !reveal);
    } else {
      setState(() => display.hideReceive = false);
      unawaited(_restore(anchor));
    }
  }

  void _zoom(double change) {
    _changeRows(
      () => display.fontSize = (display.fontSize + change).clamp(8, 32),
    );
    widget.saveDisplay();
  }

  void _zoomWithWheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (_) => _zoom(event.scrollDelta.dy > 0 ? -1 : 1),
      );
    }
  }

  Future<void> _export() async {
    final owner = session;
    try {
      final destination = await file_selector.getSaveLocation(
        suggestedName: 'communication-history.jsonl',
        confirmButtonText: '导出',
      );
      if (destination == null || owner.closed) return;
      await owner.exportTo(File(destination.path));
      if (mounted) showDsToast('会话历史已导出');
    } catch (error) {
      if (mounted) showDsToast('导出失败：$error', kind: DsToastKind.error);
    }
  }

  Future<void> _clear() async {
    try {
      final owner = session;
      await owner.clear();
      if (mounted && session == owner) _returnToLatest();
    } catch (error) {
      if (mounted) showDsToast('清空历史失败：$error', kind: DsToastKind.error);
    }
  }

  void _action(String action) {
    switch (action) {
      case 'hex':
        _changeRows(() => display.hex = !display.hex);
      case 'wrap':
        _changeRows(() => display.wrap = !display.wrap);
      case 'hideReceive':
        _toggleReceiveVisibility();
      case 'follow':
        display.follow = !display.follow;
        if (display.follow) {
          _returnToLatest();
        } else {
          _following = false;
          _rememberAnchor();
        }
      case 'export':
        unawaited(_export());
        return;
      case 'clear':
        unawaited(_clear());
        return;
      case 'recover':
        unawaited(session.history.recover());
        return;
    }
    setState(() {});
    widget.saveDisplay();
  }

  void _openContextMenu(PointerDownEvent event, double gutterWidth) {
    if ((event.buttons & kSecondaryMouseButton) == 0) {
      _contextMenu.close();
      return;
    }
    final position = event.localPosition;
    // 菜单取得焦点后，数据区原有的选区可能被框架清除。
    final selection = _selection;
    _contextMenu.close();
    setState(() {
      _menuPosition = position;
      _showGutterMenu = position.dx < gutterWidth;
      _menuSelection = selection;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contextMenu.open();
    });
  }

  Widget _command(String label, VoidCallback? callback) =>
      MenuItemButton(onPressed: callback, child: Text(label));

  Widget _check(String label, bool value, VoidCallback toggle) =>
      CheckboxMenuButton(
        closeOnActivate: false,
        value: value,
        onChanged: (_) => toggle(),
        child: Text(label),
      );

  List<Widget> _zoomActions() => [
    _command('放大数据字号', () => _zoom(1)),
    _command('缩小数据字号', () => _zoom(-1)),
    _command('重置数据字号', () => _zoom(13 - display.fontSize)),
  ];

  List<Widget> _dataActions() => [
    _command(
      '复制',
      _menuSelection.isEmpty
          ? null
          : () {
              unawaited(Clipboard.setData(ClipboardData(text: _menuSelection)));
            },
    ),
    SubmenuButton(menuChildren: widget.layoutMenu, child: const Text('会话组布局')),
    SubmenuButton(
      menuChildren: [
        _check('HEX 显示', display.hex, () => _action('hex')),
        _check('自动换行', display.wrap, () => _action('wrap')),
        _check('隐藏接收', display.hideReceive, () => _action('hideReceive')),
        _check('跟随最新数据', display.follow, () => _action('follow')),
        ..._zoomActions(),
      ],
      child: const Text('会话数据选项'),
    ),
    _command('导出会话历史', () => _action('export')),
    _command('清空会话历史', () => _action('clear')),
    if (session.history.error != null)
      _command('恢复记录', () => _action('recover')),
    if (widget.sendSettings case final buildSettings?)
      SubmenuButton(
        menuChildren: buildSettings(() => setState(() {})),
        child: const Text('发送配置'),
      ),
  ];

  void _changeGutter(VoidCallback change) {
    setState(change);
    widget.saveDisplay();
  }

  List<Widget> _gutterActions() => [
    _check(
      '空白',
      display.gutterPadding,
      () => _changeGutter(() => display.gutterPadding = !display.gutterPadding),
    ),
    _check(
      '行号',
      display.lineNumbers,
      () => _changeGutter(() => display.lineNumbers = !display.lineNumbers),
    ),
    _check(
      '符号',
      display.directionMarks,
      () =>
          _changeGutter(() => display.directionMarks = !display.directionMarks),
    ),
    _check(
      '时间戳',
      display.timestamps,
      () => _changeGutter(() => display.timestamps = !display.timestamps),
    ),
    SubmenuButton(
      menuChildren: [
        _check(
          '使用收发箭头',
          display.directionArrows,
          () => _changeGutter(
            () => display.directionArrows = !display.directionArrows,
          ),
        ),
        _check(
          '时间戳显示毫秒',
          display.timestampMillis,
          () => _changeGutter(
            () => display.timestampMillis = !display.timestampMillis,
          ),
        ),
      ],
      child: const Text('符号样式'),
    ),
    SubmenuButton(
      menuChildren: [
        _check(
          '加宽左侧空白',
          display.wideGutterPadding,
          () => _changeGutter(() {
            display.gutterPadding = true;
            display.wideGutterPadding = !display.wideGutterPadding;
          }),
        ),
      ],
      child: const Text('空格'),
    ),
    SubmenuButton(menuChildren: _zoomActions(), child: const Text('缩放')),
  ];

  double get _timestampWidth =>
      display.fontSize * (display.timestampMillis ? 8.8 : 6.4);
  double get _numberWidth => display.fontSize * 3.1;
  double get _directionWidth => display.fontSize * 1.7;
  double get _paddingWidth =>
      display.gutterPadding ? (display.wideGutterPadding ? 16 : 7) : 0;

  double get _columnsWidth =>
      (display.timestamps ? _timestampWidth + _paddingWidth : 0) +
      (display.lineNumbers ? _numberWidth + _paddingWidth : 0) +
      (display.directionMarks ? _directionWidth + _paddingWidth : 0);

  double get _gutterWidth => math.max(8, _columnsWidth);

  List<_GutterCell> _gutterCells(
    SessionDisplayRow row,
    _SessionRowStyle style,
  ) {
    if (row.start != 0 || style.columns == 0) return const [];
    final packet = row.record.packet;
    return [
      if (style.timestampWidth case final width?)
        (
          width: width,
          label: packet == null
              ? null
              : _timestampLabel.format(
                  packet.receivedAt,
                  milliseconds: style.timestampMillis,
                ),
          color: style.timestampColor,
        ),
      if (style.numberWidth case final width?)
        (
          width: width,
          label: '${row.record.sequence}',
          color: style.lineNumberColor,
        ),
      if (style.directionWidth case final width?)
        (
          width: width,
          label: packet == null
              ? null
              : style.arrows
              ? (row.record.sent ? '↑' : '↓')
              : (row.record.sent ? 'TX' : 'RX'),
          color: row.record.sent ? style.txColor : style.rxColor,
        ),
    ];
  }

  double _gutterHeight(_SessionRowStyle style) => style.columns == 0
      ? 2
      : (style.fontSize * 1.4 + 2) *
            math.min(1.0, style.gutter / style.columns);

  Widget _gutter(List<_GutterCell> cells, _SessionRowStyle style) {
    final width = style.gutter;
    final total = style.columns;
    if (total == 0) return SizedBox(width: width, height: 2);
    final height = style.fontSize * 1.4;
    final scale = math.min(1.0, width / total);
    if (cells.isEmpty) {
      return SizedBox(width: width, height: (height + 2) * scale);
    }
    return CustomPaint(
      size: Size(width, (height + 2) * scale),
      painter: _GutterPainter(
        cells,
        style.gutterText,
        _gutterText,
        height: height,
        padding: style.padding,
        contentWidth: total,
        scale: scale,
      ),
    );
  }

  SessionDisplayRows get _rows {
    _projection.replace(
      _window,
      hideReceive: display.hideReceive,
      liveTail: _following,
    );
    return _projection;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scheme =
        theme.extension<TerminalThemeExtension>()?.scheme ??
        AppThemeScope.maybeOf(context)?.scheme ??
        defaultTerminalColorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = math.min(_gutterWidth, constraints.maxWidth * 0.55);
        final terminalBody = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _openContextMenu(event, gutter),
          onPointerSignal: _scrollAtEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: gutter,
                child: SizedBox(
                  key: ValueKey('session-gutter-${session.id}'),
                ),
              ),
              Positioned.fill(
                right: _scrollbarWidth,
                child: RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: _viewportChanges,
                    builder: (context, _) => _dataViewport(
                      context,
                      colors,
                      scheme,
                      gutter,
                      constraints.maxWidth -
                          _scrollbarWidth -
                          gutter -
                          2 * _lineHorizontalPadding,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: _scrollbarWidth,
                child: RepaintBoundary(
                  child: _historyScrollbar(colors, scheme),
                ),
              ),
              Positioned(
                left: _menuPosition.dx,
                top: _menuPosition.dy,
                width: 1,
                height: 1,
                child: MenuAnchor(
                  controller: _contextMenu,
                  style: const MenuStyle(alignment: Alignment.topLeft),
                  menuChildren: _showGutterMenu
                      ? _gutterActions()
                      : _dataActions(),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
        return Column(
          children: [
            if (constraints.maxHeight >= 40)
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: _chromeChanges,
                  builder: (_, _) => _toolbar(colors, scheme),
                ),
              ),
            Expanded(
              child: scheme.background != null
                  ? ColoredBox(
                      key: ValueKey('session-terminal-bg-${session.id}'),
                      color: scheme.background!,
                      child: terminalBody,
                    )
                  : terminalBody,
            ),
          ],
        );
      },
    );
  }

  Widget _dataViewport(
    BuildContext context,
    ColorScheme colors,
    TerminalColorScheme scheme,
    double gutter,
    double contentWidth,
  ) {
    final rows = _rows;
    final defaultText = DefaultTextStyle.of(context);
    final gutterStyle = (
      text: defaultText.style.merge(
        TextStyle(
          fontFamily: 'monospace',
          fontSize: display.fontSize,
          color: scheme.gutterTimestamp ?? colors.onSurfaceVariant,
        ),
      ),
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final style = (
      gutterText: gutterStyle,
      gutter: gutter,
      columns: _columnsWidth,
      padding: _paddingWidth,
      timestampWidth: display.timestamps ? _timestampWidth : null,
      numberWidth: display.lineNumbers ? _numberWidth : null,
      directionWidth: display.directionMarks ? _directionWidth : null,
      timestampMillis: display.timestampMillis,
      arrows: display.directionArrows,
      hex: display.hex,
      wrap: display.wrap,
      noWrapWidth:
          !display.wrap &&
              contentWidth.isFinite &&
              contentWidth > 0 &&
              defaultText.maxLines == null &&
              !MediaQuery.boldTextOf(context) &&
              MediaQuery.maybeLetterSpacingOverrideOf(context) == null &&
              MediaQuery.maybeWordSpacingOverrideOf(context) == null
          ? contentWidth
          : null,
      fontSize: display.fontSize,
      scheme: scheme,
      timestampColor: scheme.gutterTimestamp ?? colors.onSurfaceVariant,
      lineNumberColor: scheme.gutterLineNumber ?? colors.onSurfaceVariant,
      noticeColor: scheme.notice ?? colors.error,
      txColor: scheme.tx,
      rxColor: scheme.rx,
      rxTextColor: scheme.foreground ?? scheme.rx,
    );
    if (style != _rowStyle) {
      _rowStyle = style;
      _rowWidgets = Expando<Widget>();
      _hexPrototype = null;
      _lastSentText = null;
      _shortLineWidths.clear();
      TextStyle lineStyle(Color color) => TextStyle(
        fontFamily: 'monospace',
        fontSize: style.fontSize,
        color: color,
      );
      _lineStyles = (
        notice: lineStyle(style.noticeColor),
        sent: lineStyle(style.txColor),
        received: lineStyle(style.rxColor),
        receivedPlain: lineStyle(style.rxTextColor),
      );
    }
    final widgets = _rowWidgets;
    final isolateRowPaint = !_following;
    Widget buildRow(int index) {
      final row = rows[index];
      return widgets[row] ??= _dataRow(
        row,
        style,
        isolatePaint: isolateRowPaint,
      );
    }

    final center = _center;
    final olderCount = _tailLayout
        ? rows.length
        : center == null
        ? 0
        : rows.lowerBound(center);
    int? indexOf(Key key, {required bool older}) {
      final index = rows.indexOf((key as ValueKey<(int, int)>).value);
      if (index == null || (index < olderCount) != older) return null;
      return older ? olderCount - index - 1 : index - olderCount;
    }

    // 只在滚动条定位已切换窗口后启用，普通滚轮离开实时区时继续复用已挂载行。
    final fixedHexRows =
        _historySeekLayout &&
        defaultText.maxLines == null &&
        style.hex &&
        !style.wrap &&
        rows.hasSplitRecords &&
        style.gutterText.direction == TextDirection.ltr &&
        _window.every((record) {
          final packet = record.packet;
          return record.notice == null &&
              packet != null &&
              packet.peer == null &&
              packet.bytes.isNotEmpty;
        });
    _fixedHeightWindow = fixedHexRows ? _window : null;
    final prototype = fixedHexRows
        ? (_hexPrototype ??= SelectionContainer.disabled(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _gutter(const [], style),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _lineHorizontalPadding,
                      vertical: 1,
                    ),
                    child: Text(
                      '0123456789 ABCDEF',
                      softWrap: false,
                      style: _lineStyles.sent,
                    ),
                  ),
                ),
              ],
            ),
          ))
        : null;
    Widget rowSliver({required bool older, Key? key}) {
      final count = older ? olderCount : rows.length - olderCount;
      final delegate = SliverChildBuilderDelegate(
        (_, index) =>
            buildRow(older ? olderCount - index - 1 : olderCount + index),
        childCount: count,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
        findChildIndexCallback: (key) => indexOf(key, older: older),
      );
      return prototype == null
          ? SliverList(key: key, delegate: delegate)
          : SliverPrototypeExtentList(
              key: key,
              delegate: delegate,
              prototypeItem: prototype,
            );
    }

    final selectionArea = SelectionArea(
      contextMenuBuilder: (context, state) => const SizedBox.shrink(),
      onSelectionChanged: (selection) =>
          _selection = selection?.plainText ?? '',
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (event) {
          if (event.depth == 0) {
            _updateScrollbarDimensions(event.metrics);
            _checkEdges();
            _syncTailLayout(event.metrics);
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SizedBox.expand(
            key: _viewportKey,
            child: _SessionScrollView(
              selection: _rowSelection,
              key: PageStorageKey('data-${session.id}'),
              scrollBehavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              controller: _scroll,
              // 不换行的长报文同时创建文本和横向视口，缩短两侧的预建距离。
              scrollCacheExtent: _following
                  ? const ScrollCacheExtent.pixels(0)
                  : !style.wrap && rows.hasSplitRecords
                  ? const ScrollCacheExtent.pixels(96)
                  : null,
              center: _centerKey,
              anchor: _tailLayout ? 1 : 0,
              slivers: [
                rowSliver(older: true),
                rowSliver(older: false, key: _centerKey),
              ],
            ),
          ),
        ),
      ),
    );
    if (scheme.selection == null) return selectionArea;
    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: scheme.selection,
        ),
      ),
      child: selectionArea,
    );
  }

  Widget _toolbar(ColorScheme colors, TerminalColorScheme scheme) {
    final error = session.history.error;
    final problem =
        error ??
        (_expired
            ? '部分较早历史已轮换'
            : session.missedInputPackets > 0
            ? '历史有缺口 · 覆盖 ${session.missedInputPackets} 条接收记录'
            : session.serialReceiveOverruns > 0
            ? '历史有缺口 · 串口接收溢出 ${session.serialReceiveOverruns} 次'
            : session.history.truncated
            ? '历史存在截断或缺口'
            : null);
    final problemHint = error != null
        ? '$error。请检查磁盘空间和写入权限，再选择「恢复记录」。'
        : problem;
    final toolbarBg = scheme.toolbarBackground ?? colors.surfaceContainerLow;
    final toolbarFg = scheme.toolbarForeground ?? colors.onSurfaceVariant;
    final toolbarNotice = scheme.notice ?? colors.error;
    return SizedBox(
      key: ValueKey('session-toolbar-${session.id}'),
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: toolbarBg,
          border: scheme.background != null
              ? Border(
                  bottom: BorderSide(
                    color: toolbarFg.withValues(alpha: 0.14),
                  ),
                )
              : null,
        ),
        child: IconTheme(
          data: IconThemeData(color: toolbarFg, size: 16),
          child: Row(
            children: [
              ?widget.connectionAction,
              if (!_following && _window.isNotEmpty)
                TextButton(
                  onPressed: _returnToLatest,
                  style: TextButton.styleFrom(foregroundColor: toolbarFg),
                  child: const Text('回到最新'),
                ),
              if (problem != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Tooltip(
                      message: problemHint!,
                      child: Text(
                        problem,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: toolbarNotice),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, right: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      message:
                          '接收 ${session.receivedPackets} 次 · 发送 ${session.sentPackets} 次',
                      child: Text(
                        'RX ${session.receivedBytes} B · TX ${session.sentBytes} B',
                        key: ValueKey('session-statistics-${session.id}'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: toolbarFg),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataRow(
    SessionDisplayRow row,
    _SessionRowStyle style, {
    required bool isolatePaint,
  }) {
    final cells = _gutterCells(row, style);
    final data = _projection.textFor(row, hex: style.hex);
    final horizontal = !style.wrap && !_fitsWithoutScrolling(data, style);
    final line = _line(row, style, data, horizontal: horizontal);
    final summary = horizontal || (cells.isEmpty && data.isEmpty)
        ? null
        : (cells: cells, data: data, direction: style.gutterText.direction);
    final content = cells.isEmpty
        ? _SessionContinuationLine(
            gutter: (
              width: style.gutter,
              height: _gutterHeight(style),
              direction: style.gutterText.direction,
            ),
            summary: summary,
            onPointerSignal: _zoomWithWheel,
            child: line,
          )
        : _SessionRowListener(
            summary: summary,
            onPointerSignal: _zoomWithWheel,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _gutter(cells, style),
                Expanded(child: line),
              ],
            ),
          );
    // 进入历史回看时仍复用已挂载的行，保留行内的文本选择状态。
    // 新建的历史行可单独缓存绘制，实时行由整个数据区隔离重绘。
    return _MountedSessionRow(
      key: ValueKey(row.id),
      id: row.id,
      mountedRows: _mountedRows,
      selection: _rowSelection,
      child: isolatePaint ? RepaintBoundary(child: content) : content,
    );
  }

  bool _fitsWithoutScrolling(String data, _SessionRowStyle style) {
    final available = style.noWrapWidth;
    if (available == null || data.length > 128) return false;
    if (!_shortLineWidths.containsKey(data)) {
      // 只度量重复的短文本，避免为一次性数据重复排版。
      if (_shortLineWidths.length == 32) {
        _shortLineWidths.remove(_shortLineWidths.keys.first);
      }
      _shortLineWidths[data] = null;
      return false;
    }

    final metrics = style.gutterText;
    final width = _shortLineWidths[data] ??= () {
      final painter = TextPainter(
        text: TextSpan(text: data, style: metrics.text),
        textDirection: metrics.direction,
        textScaler: metrics.scaler,
        locale: metrics.locale,
      );
      try {
        painter.layout();
        return painter.maxIntrinsicWidth;
      } finally {
        painter.dispose();
      }
    }();
    return width <= available;
  }

  Widget _line(
    SessionDisplayRow row,
    _SessionRowStyle style,
    String data, {
    required bool horizontal,
  }) {
    final record = row.record;
    final useFastHorizontalPaint =
        horizontal &&
        style.gutterText.direction == TextDirection.ltr &&
        data.length > 256 &&
        ((style.hex &&
                record.notice == null &&
                record.packet?.bytes is Uint8List &&
                (row.start != 0 || record.packet?.peer == null)) ||
            !_nonWideAscii.hasMatch(data));
    final baseStyle = record.notice != null
        ? _lineStyles.notice
        : record.sent
        ? _lineStyles.sent
        : style.hex
        ? _lineStyles.received
        : _lineStyles.receivedPlain;
    final spans = !useFastHorizontalPaint && !style.hex && record.notice == null
        ? buildTerminalTextSpans(
            data,
            scheme: style.scheme,
            baseStyle: baseStyle,
          )
        : null;
    final reusable =
        spans == null &&
        record.sent &&
        record.notice == null &&
        data.length <= 3072;
    final previous = reusable ? _lastSentText : null;
    final text = previous != null && identical(previous.data, data)
        ? previous
        : spans != null
        ? Text.rich(
            TextSpan(children: spans),
            softWrap: style.wrap,
            style: baseStyle,
          )
        : Text(data, softWrap: style.wrap, style: baseStyle);
    // 同一配置可以挂载到多个选择节点，行内状态由各自的元素持有。
    if (reusable) _lastSentText = text;
    final Widget horizontalContent = useFastHorizontalPaint
        ? _HorizontalTextPaint(
            selection: _rowSelection,
            layouts: _visibleTextLayouts,
            child: text,
          )
        : text;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _lineHorizontalPadding,
        vertical: 1,
      ),
      child: horizontal
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horizontalScroll,
              child: horizontalContent,
            )
          : text,
    );
  }
}

// 中心切换与像素偏移一起应用，避免按旧偏移布局新窗口。
class _HistoryScrollController extends ScrollController {
  _HistoryScrollController(this.canBatchWheel) : super(keepScrollOffset: false);

  final bool Function() canBatchWheel;
  double? nextLayoutOffset;

  void cancelPendingWheel() {
    if (hasClients) (position as _HistoryScrollPosition).cancelPendingWheel();
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _HistoryScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _HistoryScrollPosition extends ScrollPositionWithSingleContext {
  _HistoryScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  }) : super(keepScrollOffset: false);

  final _HistoryScrollController controller;
  double _pendingWheel = 0;
  int? _wheelFrame;

  double get projectedWheelOffset => pixels + _pendingWheel;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) {
      _flushPendingWheel();
      super.pointerScroll(0);
      return;
    }
    // 边界距离依赖精确偏移，触边或反向时立即提交上一段位移。
    final target = projectedWheelOffset + delta;
    if ((_pendingWheel != 0 && _pendingWheel.sign != delta.sign) ||
        !(pixels > minScrollExtent &&
            pixels < maxScrollExtent &&
            target > minScrollExtent &&
            target < maxScrollExtent) ||
        !controller.canBatchWheel()) {
      _flushPendingWheel();
      super.pointerScroll(delta);
      return;
    }
    if (_wheelFrame != null) {
      _pendingWheel += delta;
      return;
    }
    // 第一条消息仍立即响应，只合并同帧后续位移。
    super.pointerScroll(delta);
    _wheelFrame = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _wheelFrame = null;
      _flushPendingWheel();
    });
  }

  void _flushPendingWheel() {
    final delta = _pendingWheel;
    cancelPendingWheel();
    if (delta != 0) super.pointerScroll(delta);
  }

  void cancelPendingWheel() {
    if (_wheelFrame case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _wheelFrame = null;
    }
    _pendingWheel = 0;
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    cancelPendingWheel();
    super.beginActivity(newActivity);
  }

  @override
  void dispose() {
    cancelPendingWheel();
    super.dispose();
  }

  @override
  bool applyViewportDimension(double viewportDimension) {
    final target = controller.nextLayoutOffset;
    if (target != null) {
      controller.nextLayoutOffset = null;
      correctBy(target - pixels);
    }
    return super.applyViewportDimension(viewportDimension);
  }
}

/// 只登记已挂载的行，滚动锚点无需遍历窗口中曾经出现的行。
class _SessionScrollView extends CustomScrollView {
  const _SessionScrollView({
    required this.selection,
    super.key,
    super.scrollBehavior,
    super.controller,
    super.scrollCacheExtent,
    super.center,
    required super.anchor,
    required super.slivers,
  });

  final _SessionSelectionDelegate selection;

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset offset,
    AxisDirection axisDirection,
    List<Widget> slivers,
  ) => SelectionContainer(
    delegate: selection,
    child: super.buildViewport(context, offset, axisDirection, slivers),
  );
}

// 记录及其分行的顺序固定。保持 Flutter 的选区分发和边缘自动滚动。
class _SessionSelectionDelegate extends StaticSelectionContainerDelegate {
  _SessionSelectionDelegate(this.layouts);

  final _VisibleTextLayouts layouts;
  final _rows = Map<Selectable, (int, int)>.identity();

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    if (event is ClearSelectionEvent) {
      layouts.clearSelectionMode();
    } else {
      layouts.ensureAllLaidOut();
    }
    return super.dispatchSelectionEvent(event);
  }

  void addRow(Selectable selectable, (int, int) row) {
    _rows[selectable] = row;
    add(selectable);
  }

  @override
  void remove(Selectable selectable) {
    super.remove(selectable);
    _rows.remove(selectable);
  }

  @override
  Comparator<Selectable> get compareOrder => _compareRows;

  int _compareRows(Selectable first, Selectable second) {
    final a = _rows[first], b = _rows[second];
    if (a == null || b == null || a == b) {
      return super.compareOrder(first, second);
    }
    final sequence = a.$1.compareTo(b.$1);
    return sequence == 0 ? a.$2.compareTo(b.$2) : sequence;
  }
}

class _SessionRowRegistrar implements SelectionRegistrar {
  _SessionRowRegistrar(this.selection, this.row);
  final _SessionSelectionDelegate selection;
  final (int, int) row;

  @override
  void add(Selectable selectable) => selection.addRow(selectable, row);

  @override
  void remove(Selectable selectable) => selection.remove(selectable);
}

class _MountedSessionRow extends StatefulWidget {
  const _MountedSessionRow({
    required super.key,
    required this.id,
    required this.mountedRows,
    required this.selection,
    required this.child,
  });

  final (int, int) id;
  final Map<(int, int), BuildContext> mountedRows;
  final _SessionSelectionDelegate selection;
  final Widget child;

  @override
  State<_MountedSessionRow> createState() => _MountedSessionRowState();
}

class _MountedSessionRowState extends State<_MountedSessionRow> {
  late final _registrar = _SessionRowRegistrar(widget.selection, widget.id);

  @override
  void initState() {
    super.initState();
    widget.mountedRows[widget.id] = context;
  }

  @override
  void deactivate() {
    if (identical(widget.mountedRows[widget.id], context)) {
      widget.mountedRows.remove(widget.id);
    }
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.mountedRows[widget.id] = context;
  }

  @override
  Widget build(BuildContext context) =>
      SelectionRegistrarScope(registrar: _registrar, child: widget.child);
}
