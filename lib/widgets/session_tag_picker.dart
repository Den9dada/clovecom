import 'package:material_ui/material_ui.dart';

/// 会话标签可选图标条目。
class SessionTagIconOption {
  const SessionTagIconOption(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

/// 面向通信调试场景的会话标签图标集合。
const sessionTagIconOptions = <SessionTagIconOption>[
  SessionTagIconOption('square', '方块', Icons.square),
  SessionTagIconOption('circle', '圆点', Icons.circle),
  SessionTagIconOption('terminal', '终端', Icons.terminal),
  SessionTagIconOption('usb', '串口', Icons.usb),
  SessionTagIconOption('memory', '芯片', Icons.memory),
  SessionTagIconOption('developer_board', '开发板', Icons.developer_board),
  SessionTagIconOption('router', '网络', Icons.router),
  SessionTagIconOption('lan', '局域网', Icons.lan),
  SessionTagIconOption('sensors', '传感器', Icons.sensors),
  SessionTagIconOption('bolt', '电源', Icons.bolt),
  SessionTagIconOption('bug_report', '调试', Icons.bug_report),
  SessionTagIconOption('bookmark', '书签', Icons.bookmark),
];

IconData sessionTagIconData(String key) {
  for (final option in sessionTagIconOptions) {
    if (option.key == key) return option.icon;
  }
  return Icons.square;
}

/// 取色板预设颜色。
const sessionTagPresetColors = <int>[
  0xff008b9a,
  0xff3975d5,
  0xff9256c8,
  0xffcf6824,
  0xff288854,
  0xffc44777,
  0xff7251bf,
  0xffa47c15,
  0xff486b9f,
  0xffaa4f3c,
  0xff26a69a,
  0xffef5350,
];

String formatTagColorHex(int argb) =>
    '#${(argb & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 会话标签配置控件：左侧图标选择按钮 + 右侧十六进制颜色输入与取色板入口。
class SessionTagField extends StatefulWidget {
  const SessionTagField({
    super.key,
    required this.initialColor,
    required this.initialIcon,
    required this.defaultIconKey,
    required this.onColorChanged,
    required this.onIconChanged,
  });

  final int initialColor;
  final String initialIcon;
  final String defaultIconKey;
  final ValueChanged<String> onColorChanged;
  final ValueChanged<String> onIconChanged;

  @override
  State<SessionTagField> createState() => _SessionTagFieldState();
}

class _SessionTagFieldState extends State<SessionTagField> {
  late final TextEditingController _colorController;
  late String _iconKey;

  @override
  void initState() {
    super.initState();
    _iconKey = widget.initialIcon;
    _colorController = TextEditingController(
      text: formatTagColorHex(widget.initialColor),
    );
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  int? _parseColor(String text) {
    final hex = text.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return 0xff000000 | int.parse(hex, radix: 16);
  }

  Color get _previewColor =>
      Color(_parseColor(_colorController.text) ?? widget.initialColor);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final previewColor = _previewColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '会话标签',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Tooltip(
              message: '选择标签图标',
              child: SizedBox(
                width: 34,
                height: 34,
                child: InkWell(
                  key: const ValueKey('session-tag-icon-button'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    final picked = await showSessionTagIconPicker(
                      context,
                      selectedKey: _iconKey,
                      color: previewColor,
                    );
                    if (picked != null && mounted) {
                      setState(() => _iconKey = picked);
                      widget.onIconChanged(picked);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.outline),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      sessionTagIconData(_iconKey),
                      size: _iconKey == widget.defaultIconKey ? 11 : 16,
                      color: previewColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const ValueKey('session-tag-color-input'),
                controller: _colorController,
                textAlignVertical: TextAlignVertical.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'Consolas',
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '#RRGGBB',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  constraints: const BoxConstraints(minHeight: 34),
                  contentPadding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 34,
                  ),
                  prefixIcon: Tooltip(
                    message: '打开取色板',
                    child: InkWell(
                      key: const ValueKey('session-tag-color-picker-button'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final picked = await showSessionTagColorPicker(
                          context,
                          initialColor: previewColor,
                        );
                        if (picked != null && mounted) {
                          final nextHex = formatTagColorHex(picked);
                          _colorController.text = nextHex;
                          setState(() {});
                          widget.onColorChanged(nextHex);
                        }
                      },
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: previewColor,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: colors.onSurface.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                onChanged: (value) {
                  setState(() {});
                  widget.onColorChanged(value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 弹出图标选择面板，返回选中的图标键名。
Future<String?> showSessionTagIconPicker(
  BuildContext context, {
  required String selectedKey,
  required Color color,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return showDialog<String>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        key: const ValueKey('session-tag-icon-picker-dialog'),
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('选择标签图标', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 26,
                      height: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in sessionTagIconOptions)
                    _IconOptionTile(
                      option: option,
                      selected: option.key == selectedKey,
                      color: color,
                      colors: colors,
                      onTap: () => Navigator.pop(context, option.key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _IconOptionTile extends StatelessWidget {
  const _IconOptionTile({
    required this.option,
    required this.selected,
    required this.color,
    required this.colors,
    required this.onTap,
  });

  final SessionTagIconOption option;
  final bool selected;
  final Color color;
  final ColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSquare = option.key == 'square';
    return Tooltip(
      message: option.label,
      child: InkWell(
        key: ValueKey('session-tag-icon-option-${option.key}'),
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(option.icon, size: isSquare ? 12 : 18, color: color),
        ),
      ),
    );
  }
}

/// 弹出取色板（HSV 面板 + 预设色块），返回选中的 ARGB 整数。
Future<int?> showSessionTagColorPicker(
  BuildContext context, {
  required Color initialColor,
}) => showDialog<int>(
  context: context,
  builder: (context) => _SessionTagColorPickerDialog(initialColor: initialColor),
);

class _SessionTagColorPickerDialog extends StatefulWidget {
  const _SessionTagColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_SessionTagColorPickerDialog> createState() =>
      _SessionTagColorPickerDialogState();
}

class _SessionTagColorPickerDialogState
    extends State<_SessionTagColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);

  Color get _current => _hsv.toColor();

  void _updateSaturationValue(Offset localPosition, Size size) {
    final s = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final v = 1.0 - (localPosition.dy / size.height).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
  }

  void _updateHue(double dx, double width) {
    final hue = (dx / width).clamp(0.0, 1.0) * 360.0;
    setState(() => _hsv = _hsv.withHue(hue));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentColor = _current;
    final currentArgb = currentColor.toARGB32();
    final hex = formatTagColorHex(currentArgb);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        key: const ValueKey('session-tag-color-picker-dialog'),
        width: 300,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('选择标签颜色', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 26,
                      height: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final boxSize = Size(constraints.maxWidth, 140);
                  return GestureDetector(
                    onPanDown: (d) =>
                        _updateSaturationValue(d.localPosition, boxSize),
                    onPanUpdate: (d) =>
                        _updateSaturationValue(d.localPosition, boxSize),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: boxSize.width,
                        height: boxSize.height,
                        child: CustomPaint(
                          painter: _SvPalettePainter(
                            hue: _hsv.hue,
                            saturation: _hsv.saturation,
                            value: _hsv.value,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return GestureDetector(
                    onPanDown: (d) => _updateHue(d.localPosition.dx, width),
                    onPanUpdate: (d) => _updateHue(d.localPosition.dx, width),
                    child: SizedBox(
                      height: 16,
                      width: width,
                      child: CustomPaint(
                        painter: _HueBarPainter(hue: _hsv.hue),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in sessionTagPresetColors)
                    InkWell(
                      key: ValueKey(
                        'session-tag-preset-${formatTagColorHex(preset)}',
                      ),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => setState(
                        () => _hsv = HSVColor.fromColor(Color(preset)),
                      ),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Color(preset),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: currentArgb == preset
                                ? colors.onSurface
                                : colors.onSurface.withValues(alpha: 0.2),
                            width: currentArgb == preset ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: currentColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: colors.onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hex,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'Consolas',
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, currentArgb),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SvPalettePainter extends CustomPainter {
  const _SvPalettePainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final thumb = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      thumb,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      thumb,
      4.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SvPalettePainter oldDelegate) =>
      oldDelegate.hue != hue ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}

class _HueBarPainter extends CustomPainter {
  const _HueBarPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xffff0000),
            Color(0xffffff00),
            Color(0xff00ff00),
            Color(0xff00ffff),
            Color(0xff0000ff),
            Color(0xffff00ff),
            Color(0xffff0000),
          ],
        ).createShader(rect),
    );
    final x = (hue / 360.0).clamp(0.0, 1.0) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x.clamp(4, size.width - 4), size.height / 2),
          width: 6,
          height: size.height,
        ),
        const Radius.circular(3),
      ),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HueBarPainter oldDelegate) =>
      oldDelegate.hue != hue;
}
