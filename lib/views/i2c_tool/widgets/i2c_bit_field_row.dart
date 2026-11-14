// 位域行组件
//
// 单行位域显示和编辑：位范围、字段名、权限、物理值解读、编辑输入框

import 'package:flutter/material.dart';
import '../../../models/i2c_register_map.dart';

class I2cBitFieldRow extends StatefulWidget {
  final I2cRegisterBitField bitField;
  final int currentFullValue; // 完整的寄存器值（用于解码位域）
  final int? readValue; // 芯片读取值（null=未读）
  final void Function(int value)? onChanged; // 位域值修改回调

  const I2cBitFieldRow({
    super.key,
    required this.bitField,
    required this.currentFullValue,
    this.readValue,
    this.onChanged,
  });

  @override
  State<I2cBitFieldRow> createState() => _I2cBitFieldRowState();
}

class _I2cBitFieldRowState extends State<I2cBitFieldRow> {
  late TextEditingController _controller;
  int _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _lastValue = widget.bitField.extract(widget.currentFullValue);
    _controller = TextEditingController(text: _formatValue(_lastValue));
  }

  @override
  void didUpdateWidget(I2cBitFieldRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newVal = widget.bitField.extract(widget.currentFullValue);
    if (newVal != _lastValue) {
      _lastValue = newVal;
      _controller.text = _formatValue(newVal);
    }
  }

  String _formatValue(int v) => widget.bitField.toPhysical(v) != null
      ? widget.bitField.toPhysical(v)!.toStringAsFixed(1)
      : v.toString();

  void _onEditingComplete() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final parsed = double.tryParse(text);
    if (parsed == null) return;

    int rawValue;
    if (widget.bitField.gain != null || widget.bitField.offsetValue != null) {
      // 物理值 → 位域值
      final raw = widget.bitField.fromPhysical(parsed);
      if (raw == null) return;
      rawValue = raw;
    } else {
      rawValue = parsed.toInt();
    }

    rawValue = rawValue.clamp(0, (1 << widget.bitField.width) - 1);
    _lastValue = rawValue;
    _controller.text = _formatValue(rawValue);
    widget.onChanged?.call(rawValue);
  }

  String? get _unit {
    final desc = widget.bitField.description.toLowerCase();
    if (desc.contains('ma')) return 'mA';
    if (desc.contains('v')) return 'V';
    if (desc.contains('mv')) return 'mV';
    if (desc.contains('℃')) return '℃';
    if (desc.contains('khz')) return 'kHz';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bf = widget.bitField;
    final cs = Theme.of(context).colorScheme;
    final isReadOnly = bf.isReadOnly;
    final bitStr = bf.msb == bf.lsb ? '${bf.msb}' : '${bf.msb}:${bf.lsb}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 位范围
          Container(
            width: 42,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              bitStr,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 字段名 + 权限
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      bf.fieldName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _accessChip(bf.access, cs),
                  ],
                ),
                if (bf.description.isNotEmpty)
                  Text(
                    _firstLine(bf.description),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 编辑输入框
          if (isReadOnly)
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatValue(bf.extract(widget.currentFullValue)),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            SizedBox(
              width: 110,
              height: 30,
              child: TextField(
                controller: _controller,
                enabled: !isReadOnly,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixText: _unit,
                  suffixStyle: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                onSubmitted: (_) => _onEditingComplete(),
                onEditingComplete: _onEditingComplete,
              ),
            ),
        ],
      ),
    );
  }

  Widget _accessChip(String access, ColorScheme cs) {
    final isRO = access == 'R';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isRO
            ? Colors.orange.withValues(alpha: 0.15)
            : cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        access,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isRO ? Colors.orange.shade800 : cs.primary,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _firstLine(String s) {
    final idx = s.indexOf('\n');
    return idx > 0 ? s.substring(0, idx) : s;
  }
}
