import 'package:material_ui/material_ui.dart';

/// 会话终端配色方案定义（参考 mbadolato/iTerm2-Color-Schemes）。
///
/// 涵盖终端背景、前景、16 色 ANSI 调色板、边栏（时间戳/行号/方向标记）、
/// 工具栏、选区高亮、滚动条及终端文本语义着色。
class TerminalColorScheme {
  const TerminalColorScheme({
    required this.id,
    required this.name,
    required this.isDark,
    required this.rx,
    required this.tx,
    required this.ansi,
    required this.palette,
    this.background,
    this.foreground,
    this.gutterTimestamp,
    this.gutterLineNumber,
    this.notice,
    this.warning,
    this.info,
    this.debug,
    this.number,
    this.banner,
    this.toolbarBackground,
    this.toolbarForeground,
    this.selection,
    this.scrollbarTrack,
    this.scrollbarThumb,
  });

  /// 通过 iTerm2-Color-Schemes 的 16 色 ANSI 调色板构造完整终端配色。
  factory TerminalColorScheme.fromAnsi({
    required String id,
    required String name,
    required bool isDark,
    required Color background,
    required Color foreground,
    required Color selection,
    required List<Color> ansi,
    Color? toolbarBackground,
    Color? scrollbarTrack,
  }) {
    assert(ansi.length == 16);
    final rx = isDark ? ansi[10] : ansi[2];
    final tx = isDark ? ansi[13] : ansi[5];
    final notice = isDark ? ansi[9] : ansi[1];
    final warning = isDark ? ansi[11] : ansi[3];
    final debug = isDark ? ansi[14] : ansi[6];
    final gutterTimestamp = ansi[8];
    final gutterLineNumber = isDark ? ansi[14] : ansi[6];
    final banner = isDark ? ansi[15] : ansi[0];
    return TerminalColorScheme(
      id: id,
      name: name,
      isDark: isDark,
      background: background,
      foreground: foreground,
      rx: rx,
      tx: tx,
      ansi: ansi,
      gutterTimestamp: gutterTimestamp,
      gutterLineNumber: gutterLineNumber,
      notice: notice,
      warning: warning,
      info: rx,
      debug: debug,
      number: tx,
      banner: banner,
      toolbarBackground: toolbarBackground,
      toolbarForeground: foreground.withValues(alpha: 0.78),
      selection: selection,
      scrollbarTrack: scrollbarTrack,
      scrollbarThumb: gutterTimestamp.withValues(alpha: isDark ? 0.6 : 0.55),
      palette: [
        rx,
        tx,
        debug,
        warning,
        isDark ? ansi[12] : ansi[4],
        notice,
        foreground,
      ],
    );
  }

  final String id;
  final String name;
  final bool isDark;

  /// 终端数据区背景色；为 null 时跟随应用当前表面色。
  final Color? background;

  /// 默认前景色；为 null 时跟随 RX 配色或应用默认文字色。
  final Color? foreground;

  /// 接收数据（RX）标记及 HEX 颜色。
  final Color rx;

  /// 发送数据（TX）标记及文本颜色。
  final Color tx;

  /// 标准 16 色 ANSI 调色板（0..7 普通色，8..15 高亮色）。
  final List<Color> ansi;

  /// 左侧边栏时间戳颜色。
  final Color? gutterTimestamp;

  /// 左侧边栏行号颜色。
  final Color? gutterLineNumber;

  /// 会话提示/错误行及 `[E/...]` 错误标签颜色。
  final Color? notice;

  /// `[W/...]` 警告标签颜色。
  final Color? warning;

  /// `[I/...]` 信息标签颜色。
  final Color? info;

  /// `[D/...]` 调试标签颜色。
  final Color? debug;

  /// 数字与十六进制字面量颜色。
  final Color? number;

  /// 标题横幅（如 `--- ... ---`、`=== ... ===`）颜色。
  final Color? banner;

  /// 会话工具栏背景色。
  final Color? toolbarBackground;

  /// 会话工具栏文字与图标色。
  final Color? toolbarForeground;

  /// 文本选区高亮色。
  final Color? selection;

  /// 历史滚动条轨道色。
  final Color? scrollbarTrack;

  /// 历史滚动条滑块色。
  final Color? scrollbarThumb;

  /// 用于单向“切换接收/发送配色”循环的候选颜色列表。
  final List<Color> palette;
}

const defaultTerminalColorSchemeId = 'one-half-light';

final TerminalColorScheme defaultTerminalColorScheme =
    _oneHalfLightColorScheme;

final TerminalColorScheme _oneHalfLightColorScheme = TerminalColorScheme.fromAnsi(
  id: 'one-half-light',
  name: 'One Half Light',
  isDark: false,
  background: const Color(0xfffafafa),
  foreground: const Color(0xff383a42),
  selection: const Color(0xaae5e5e6),
  toolbarBackground: const Color(0xfff0f0f0),
  scrollbarTrack: const Color(0xfff0f0f0),
  ansi: const [
    Color(0xff383a42),
    Color(0xffe45649),
    Color(0xff50a14f),
    Color(0xffc18401),
    Color(0xff0184bc),
    Color(0xffa626a4),
    Color(0xff0997b3),
    Color(0xfffafafa),
    Color(0xffa0a1a7),
    Color(0xffe45649),
    Color(0xff50a14f),
    Color(0xffc18401),
    Color(0xff0184bc),
    Color(0xffa626a4),
    Color(0xff0997b3),
    Color(0xff383a42),
  ],
);

/// 精选自 mbadolato/iTerm2-Color-Schemes 的常用浅色与深色配色方案。
final List<TerminalColorScheme> terminalColorSchemes = [
  // --- 浅色方案 ---
  _oneHalfLightColorScheme,
  // --- 深色方案 ---
  TerminalColorScheme.fromAnsi(
    id: 'dracula',
    name: 'Dracula',
    isDark: true,
    background: const Color(0xff282a36),
    foreground: const Color(0xfff8f8f2),
    selection: const Color(0xaa44475a),
    toolbarBackground: const Color(0xff21222c),
    scrollbarTrack: const Color(0xff21222c),
    ansi: const [
      Color(0xff21222c),
      Color(0xffff5555),
      Color(0xff50fa7b),
      Color(0xfff1fa8c),
      Color(0xffbd93f9),
      Color(0xffff79c6),
      Color(0xff8be9fd),
      Color(0xfff8f8f2),
      Color(0xff6272a4),
      Color(0xffff6e6e),
      Color(0xff69ff94),
      Color(0xffffffa5),
      Color(0xffd6acff),
      Color(0xffff92df),
      Color(0xffa4ffff),
      Color(0xffffffff),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'one-half-dark',
    name: 'One Half Dark',
    isDark: true,
    background: const Color(0xff282c34),
    foreground: const Color(0xffdcdfe4),
    selection: const Color(0xaa474e5d),
    toolbarBackground: const Color(0xff21252b),
    scrollbarTrack: const Color(0xff21252b),
    ansi: const [
      Color(0xff282c34),
      Color(0xffe06c75),
      Color(0xff98c379),
      Color(0xffe5c07b),
      Color(0xff61afef),
      Color(0xffc678dd),
      Color(0xff56b6c2),
      Color(0xffdcdfe4),
      Color(0xff5c6370),
      Color(0xffe06c75),
      Color(0xff98c379),
      Color(0xffe5c07b),
      Color(0xff61afef),
      Color(0xffc678dd),
      Color(0xff56b6c2),
      Color(0xffffffff),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'solarized-dark',
    name: 'Solarized Dark',
    isDark: true,
    background: const Color(0xff002b36),
    foreground: const Color(0xff839496),
    selection: const Color(0xaa073642),
    toolbarBackground: const Color(0xff00212b),
    scrollbarTrack: const Color(0xff00212b),
    ansi: const [
      Color(0xff073642),
      Color(0xffdc322f),
      Color(0xff859900),
      Color(0xffb58900),
      Color(0xff268bd2),
      Color(0xffd33682),
      Color(0xff2aa198),
      Color(0xffeee8d5),
      Color(0xff586e75),
      Color(0xffcb4b16),
      Color(0xff859900),
      Color(0xffb58900),
      Color(0xff268bd2),
      Color(0xff6c71c4),
      Color(0xff2aa198),
      Color(0xfffdf6e3),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'nord',
    name: 'Nord',
    isDark: true,
    background: const Color(0xff2e3440),
    foreground: const Color(0xffd8dee9),
    selection: const Color(0xaa434c5e),
    toolbarBackground: const Color(0xff272c36),
    scrollbarTrack: const Color(0xff272c36),
    ansi: const [
      Color(0xff3b4252),
      Color(0xffbf616a),
      Color(0xffa3be8c),
      Color(0xffebcb8b),
      Color(0xff81a1c1),
      Color(0xffb48ead),
      Color(0xff88c0d0),
      Color(0xffe5e9f0),
      Color(0xff616e88),
      Color(0xffbf616a),
      Color(0xffa3be8c),
      Color(0xffebcb8b),
      Color(0xff81a1c1),
      Color(0xffb48ead),
      Color(0xff8fbcbb),
      Color(0xffeceff4),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'gruvbox-dark',
    name: 'Gruvbox Dark',
    isDark: true,
    background: const Color(0xff282828),
    foreground: const Color(0xffebdbb2),
    selection: const Color(0xaa504945),
    toolbarBackground: const Color(0xff1d2021),
    scrollbarTrack: const Color(0xff1d2021),
    ansi: const [
      Color(0xff282828),
      Color(0xffcc241d),
      Color(0xff98971a),
      Color(0xffd79921),
      Color(0xff458588),
      Color(0xffb16286),
      Color(0xff689d6a),
      Color(0xffa89984),
      Color(0xff928374),
      Color(0xfffb4934),
      Color(0xffb8bb26),
      Color(0xfffabd2f),
      Color(0xff83a598),
      Color(0xffd3869b),
      Color(0xff8ec07c),
      Color(0xffebdbb2),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'tokyo-night',
    name: 'Tokyo Night',
    isDark: true,
    background: const Color(0xff1a1b26),
    foreground: const Color(0xffc0caf5),
    selection: const Color(0xaa33467c),
    toolbarBackground: const Color(0xff16161e),
    scrollbarTrack: const Color(0xff16161e),
    ansi: const [
      Color(0xff15161e),
      Color(0xfff7768e),
      Color(0xff9ece6a),
      Color(0xffe0af68),
      Color(0xff7aa2f7),
      Color(0xffbb9af7),
      Color(0xff7dcfff),
      Color(0xffa9b1d6),
      Color(0xff565f89),
      Color(0xfff7768e),
      Color(0xff9ece6a),
      Color(0xffe0af68),
      Color(0xff7aa2f7),
      Color(0xffbb9af7),
      Color(0xff7dcfff),
      Color(0xffc0caf5),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    isDark: true,
    background: const Color(0xff1e1e2e),
    foreground: const Color(0xffcdd6f4),
    selection: const Color(0xaa45475a),
    toolbarBackground: const Color(0xff181825),
    scrollbarTrack: const Color(0xff181825),
    ansi: const [
      Color(0xff45475a),
      Color(0xfff38ba8),
      Color(0xffa6e3a1),
      Color(0xfff9e2af),
      Color(0xff89b4fa),
      Color(0xfff5c2e7),
      Color(0xff94e2d5),
      Color(0xffbac2de),
      Color(0xff6c7086),
      Color(0xfff38ba8),
      Color(0xffa6e3a1),
      Color(0xfff9e2af),
      Color(0xff89b4fa),
      Color(0xffcba6f7),
      Color(0xff94e2d5),
      Color(0xffcdd6f4),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'monokai-soda',
    name: 'Monokai Soda',
    isDark: true,
    background: const Color(0xff1a1a1a),
    foreground: const Color(0xffc4c5b5),
    selection: const Color(0xaa343434),
    toolbarBackground: const Color(0xff141414),
    scrollbarTrack: const Color(0xff141414),
    ansi: const [
      Color(0xff1a1a1a),
      Color(0xfff4005f),
      Color(0xff98e024),
      Color(0xfffa8419),
      Color(0xff9d65ff),
      Color(0xfff4005f),
      Color(0xff58d1eb),
      Color(0xffc4c5b5),
      Color(0xff625e4c),
      Color(0xfff4005f),
      Color(0xff98e024),
      Color(0xffe0d561),
      Color(0xff9d65ff),
      Color(0xfff4005f),
      Color(0xff58d1eb),
      Color(0xfff6f6ef),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'github-dark',
    name: 'GitHub Dark',
    isDark: true,
    background: const Color(0xff0d1117),
    foreground: const Color(0xffc9d1d9),
    selection: const Color(0x661f6feb),
    toolbarBackground: const Color(0xff090c10),
    scrollbarTrack: const Color(0xff090c10),
    ansi: const [
      Color(0xff484f58),
      Color(0xffff7b72),
      Color(0xff3fb950),
      Color(0xffd29922),
      Color(0xff58a6ff),
      Color(0xffbc8cff),
      Color(0xff39c5cf),
      Color(0xffb1bac4),
      Color(0xff8b949e),
      Color(0xffffa198),
      Color(0xff56d364),
      Color(0xffe3b341),
      Color(0xff79c0ff),
      Color(0xffd2a8ff),
      Color(0xff56d4dd),
      Color(0xfff0f6fc),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'ayu-dark',
    name: 'Ayu Dark',
    isDark: true,
    background: const Color(0xff0b0e14),
    foreground: const Color(0xffbfbdb6),
    selection: const Color(0xaa1b2733),
    toolbarBackground: const Color(0xff080a0f),
    scrollbarTrack: const Color(0xff080a0f),
    ansi: const [
      Color(0xff131721),
      Color(0xffea6c73),
      Color(0xff7fd962),
      Color(0xfff9af4f),
      Color(0xff53bdfa),
      Color(0xffcda1fa),
      Color(0xff90e1c6),
      Color(0xffc7c7c7),
      Color(0xff565b66),
      Color(0xfff07178),
      Color(0xffaad94c),
      Color(0xffffb454),
      Color(0xff59c2ff),
      Color(0xffd2a6ff),
      Color(0xff95e6cb),
      Color(0xffffffff),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'cobalt2',
    name: 'Cobalt2',
    isDark: true,
    background: const Color(0xff193549),
    foreground: const Color(0xffffffff),
    selection: const Color(0xaa0050a4),
    toolbarBackground: const Color(0xff122738),
    scrollbarTrack: const Color(0xff122738),
    ansi: const [
      Color(0xff000000),
      Color(0xffff0000),
      Color(0xff38de21),
      Color(0xffffe50a),
      Color(0xff1460d2),
      Color(0xffff005d),
      Color(0xff00bbbb),
      Color(0xffbbbbbb),
      Color(0xff6b8ea8),
      Color(0xffff628c),
      Color(0xff3ad900),
      Color(0xffffc600),
      Color(0xff0088ff),
      Color(0xffff55ff),
      Color(0xff80fcff),
      Color(0xffffffff),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'tomorrow-night',
    name: 'Tomorrow Night',
    isDark: true,
    background: const Color(0xff1d1f21),
    foreground: const Color(0xffc5c8c6),
    selection: const Color(0xaa373b41),
    toolbarBackground: const Color(0xff161719),
    scrollbarTrack: const Color(0xff161719),
    ansi: const [
      Color(0xff1d1f21),
      Color(0xffcc6666),
      Color(0xffb5bd68),
      Color(0xfff0c674),
      Color(0xff81a2be),
      Color(0xffb294bb),
      Color(0xff8abeb7),
      Color(0xffc5c8c6),
      Color(0xff969896),
      Color(0xffcc6666),
      Color(0xffb5bd68),
      Color(0xfff0c674),
      Color(0xff81a2be),
      Color(0xffb294bb),
      Color(0xff8abeb7),
      Color(0xffffffff),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'everforest-dark',
    name: 'Everforest Dark',
    isDark: true,
    background: const Color(0xff272e33),
    foreground: const Color(0xffd3c6aa),
    selection: const Color(0xaa414b50),
    toolbarBackground: const Color(0xff1e2326),
    scrollbarTrack: const Color(0xff1e2326),
    ansi: const [
      Color(0xff414b50),
      Color(0xffe67e80),
      Color(0xffa7c080),
      Color(0xffdbbc7f),
      Color(0xff7fbbb3),
      Color(0xffd699b6),
      Color(0xff83c092),
      Color(0xffd3c6aa),
      Color(0xff859289),
      Color(0xffe67e80),
      Color(0xffa7c080),
      Color(0xffdbbc7f),
      Color(0xff7fbbb3),
      Color(0xffd699b6),
      Color(0xff83c092),
      Color(0xffe8e0cb),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'rose-pine',
    name: 'Rosé Pine',
    isDark: true,
    background: const Color(0xff191724),
    foreground: const Color(0xffe0def4),
    selection: const Color(0xaa2a283e),
    toolbarBackground: const Color(0xff13111c),
    scrollbarTrack: const Color(0xff13111c),
    ansi: const [
      Color(0xff26233a),
      Color(0xffeb6f92),
      Color(0xff31748f),
      Color(0xfff6c177),
      Color(0xff9ccfd8),
      Color(0xffc4a7e7),
      Color(0xffebbcba),
      Color(0xffe0def4),
      Color(0xff6e6a86),
      Color(0xffeb6f92),
      Color(0xff9ccfd8),
      Color(0xfff6c177),
      Color(0xff31748f),
      Color(0xffc4a7e7),
      Color(0xffebbcba),
      Color(0xffe0def4),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'snazzy',
    name: 'Snazzy',
    isDark: true,
    background: const Color(0xff282a36),
    foreground: const Color(0xffeff0eb),
    selection: const Color(0xaa3e404a),
    toolbarBackground: const Color(0xff21222c),
    scrollbarTrack: const Color(0xff21222c),
    ansi: const [
      Color(0xff282a36),
      Color(0xffff5c57),
      Color(0xff5af78e),
      Color(0xfff3f99d),
      Color(0xff57c7ff),
      Color(0xffff6ac1),
      Color(0xff9aedfe),
      Color(0xfff1f1f0),
      Color(0xff686868),
      Color(0xffff5c57),
      Color(0xff5af78e),
      Color(0xfff3f99d),
      Color(0xff57c7ff),
      Color(0xffff6ac1),
      Color(0xff9aedfe),
      Color(0xffeff0eb),
    ],
  ),
  // --- 浅色方案（其余） ---
  TerminalColorScheme.fromAnsi(
    id: 'solarized-light',
    name: 'Solarized Light',
    isDark: false,
    background: const Color(0xfffdf6e3),
    foreground: const Color(0xff657b83),
    selection: const Color(0xaaeee8d5),
    toolbarBackground: const Color(0xfff5eedb),
    scrollbarTrack: const Color(0xfff5eedb),
    ansi: const [
      Color(0xff073642),
      Color(0xffdc322f),
      Color(0xff859900),
      Color(0xffb58900),
      Color(0xff268bd2),
      Color(0xffd33682),
      Color(0xff2aa198),
      Color(0xffeee8d5),
      Color(0xff93a1a1),
      Color(0xffcb4b16),
      Color(0xff859900),
      Color(0xffb58900),
      Color(0xff268bd2),
      Color(0xff6c71c4),
      Color(0xff2aa198),
      Color(0xff586e75),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'gruvbox-light',
    name: 'Gruvbox Light',
    isDark: false,
    background: const Color(0xfffbf1c7),
    foreground: const Color(0xff3c3836),
    selection: const Color(0xaaebdbb2),
    toolbarBackground: const Color(0xfff2e5bc),
    scrollbarTrack: const Color(0xfff2e5bc),
    ansi: const [
      Color(0xff3c3836),
      Color(0xff9d0006),
      Color(0xff79740e),
      Color(0xffb57614),
      Color(0xff076678),
      Color(0xff8f3f71),
      Color(0xff427b58),
      Color(0xfffbf1c7),
      Color(0xff7c6f64),
      Color(0xff9d0006),
      Color(0xff79740e),
      Color(0xffb57614),
      Color(0xff076678),
      Color(0xff8f3f71),
      Color(0xff427b58),
      Color(0xff282828),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'catppuccin-latte',
    name: 'Catppuccin Latte',
    isDark: false,
    background: const Color(0xffeff1f5),
    foreground: const Color(0xff4c4f69),
    selection: const Color(0xaaacb0be),
    toolbarBackground: const Color(0xffe6e9ef),
    scrollbarTrack: const Color(0xffe6e9ef),
    ansi: const [
      Color(0xff4c4f69),
      Color(0xffd20f39),
      Color(0xff40a02b),
      Color(0xffdf8e1d),
      Color(0xff1e66f5),
      Color(0xff8839ef),
      Color(0xff179299),
      Color(0xffeff1f5),
      Color(0xff7c7f93),
      Color(0xffd20f39),
      Color(0xff40a02b),
      Color(0xffdf8e1d),
      Color(0xff1e66f5),
      Color(0xff8839ef),
      Color(0xff179299),
      Color(0xff4c4f69),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'github-light',
    name: 'GitHub Light',
    isDark: false,
    background: const Color(0xffffffff),
    foreground: const Color(0xff24292f),
    selection: const Color(0x99bbdfff),
    toolbarBackground: const Color(0xfff6f8fa),
    scrollbarTrack: const Color(0xfff6f8fa),
    ansi: const [
      Color(0xff24292f),
      Color(0xffcf222e),
      Color(0xff116329),
      Color(0xff9a6700),
      Color(0xff0550ae),
      Color(0xff8250df),
      Color(0xff1b7c83),
      Color(0xffffffff),
      Color(0xff6e7781),
      Color(0xffa40e26),
      Color(0xff1a7f37),
      Color(0xff633c01),
      Color(0xff218bff),
      Color(0xffa475f9),
      Color(0xff3192aa),
      Color(0xff24292f),
    ],
  ),
  TerminalColorScheme.fromAnsi(
    id: 'rose-pine-dawn',
    name: 'Rosé Pine Dawn',
    isDark: false,
    background: const Color(0xfffaf4ed),
    foreground: const Color(0xff575279),
    selection: const Color(0xaadfdad9),
    toolbarBackground: const Color(0xfff2e9e1),
    scrollbarTrack: const Color(0xfff2e9e1),
    ansi: const [
      Color(0xff575279),
      Color(0xffb4637a),
      Color(0xff286983),
      Color(0xffea9d34),
      Color(0xff56949f),
      Color(0xff907aa9),
      Color(0xff56949f),
      Color(0xfffaf4ed),
      Color(0xff797593),
      Color(0xffb4637a),
      Color(0xff286983),
      Color(0xffea9d34),
      Color(0xff56949f),
      Color(0xff907aa9),
      Color(0xff286983),
      Color(0xff575279),
    ],
  ),
];

final Map<String, TerminalColorScheme> _schemesById = {
  for (final scheme in terminalColorSchemes) scheme.id: scheme,
};

/// 根据配色 ID 解析终端配色方案；未知 ID 回退到默认方案。
TerminalColorScheme resolveTerminalColorScheme(String id) =>
    _schemesById[id] ?? defaultTerminalColorScheme;
