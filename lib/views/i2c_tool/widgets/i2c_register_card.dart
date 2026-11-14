// 寄存器详情卡片
//
// 显示单个寄存器的位域详情 + HEX 编辑联动。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/i2c_register_map.dart';

class I2cRegisterCard extends StatefulWidget {
  final I2cRegister register;
  final int regIndex;
  final void Function(int value)? onHexChanged;
  final VoidCallback? onRead;
  final VoidCallback? onWrite;
  final VoidCallback? onResetDefault;

  const I2cRegisterCard({
    super.key,
    required this.register,
    required this.regIndex,
    this.onHexChanged,
    this.onRead,
    this.onWrite,
    this.onResetDefault,
  });

  @override
  State<I2cRegisterCard> createState() => _I2cRegisterCardState();
}

class _I2cRegisterCardState extends State<I2cRegisterCard> {
  TextEditingController? _hexController;
  int? _lastDisplayedValue;
  bool _isValidHex = true;

  @override
  void initState() {
    super.initState();
    _updateController();
  }

  @override
  void didUpdateWidget(I2cRegisterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reg = widget.register;
    final current = reg.editingValue ?? reg.currentValue;
    if (current != _lastDisplayedValue) {
      _updateController();
    }
  }

  void _updateController() {
    final reg = widget.register;
    final current = reg.editingValue ?? reg.currentValue;
    _lastDisplayedValue = current;
    _hexController?.dispose();
    _hexController = TextEditingController(
      text: current != null
          ? current.toRadixString(16).toUpperCase().padLeft(2, '0')
          : '',
    );
    _isValidHex = true;
  }

  void _onHexSubmitted(String text) {
    String hex = text.trim().toUpperCase();
    if (hex.isEmpty) return;
    if (hex.startsWith('0X')) hex = hex.substring(2);
    if (hex.startsWith('0x')) hex = hex.substring(2);

    final v = int.tryParse(hex, radix: 16);
    if (v != null && v >= 0 && v <= 255) {
      _lastDisplayedValue = v;
      _isValidHex = true;
      _hexController!.text = v.toRadixString(16).toUpperCase().padLeft(2, '0');
      widget.onHexChanged?.call(v);
    } else {
      _isValidHex = false;
      setState(() {});
    }
  }

  void _onHexChanged(String text) {
    String hex = text.trim().toUpperCase();
    if (hex.isEmpty) {
      _isValidHex = true;
      return;
    }
    // 实时校验：只允许 0-9 A-F
    _isValidHex = RegExp(r'^[0-9A-F]{0,2}$').hasMatch(hex);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reg = widget.register;
    final readVal = reg.currentValue; // 芯片读取值
    final editingVal = reg.editingValue;
    final displayVal = editingVal ?? readVal; // 当前显示/编辑值

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 寄存器头部：名称 + 偏移
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: reg.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '  [${reg.offsetHex}]',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const [
                        'Menlo',
                        'Courier New',
                        'MiSans',
                      ],
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // 编辑状态提示
            if (editingVal != null && editingVal != readVal)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '已修改 (未写入)',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                ),
              ),
            const Divider(height: 12),
            // 操作按钮行
            Row(
              children: [
                Text(
                  '0x${(readVal ?? 0).toRadixString(16).toUpperCase().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const [
                      'Menlo',
                      'Courier New',
                      'MiSans',
                    ],
                    fontWeight: FontWeight.w700,
                    color: readVal != null
                        ? Colors.green.shade700
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                if (readVal != null)
                  Text(
                    '($readVal)',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.onResetDefault,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('默认值'),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: widget.onRead,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('读取'),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 64,
                  height: 34,
                  child: TextField(
                    controller: _hexController!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const [
                        'Menlo',
                        'Courier New',
                        'MiSans',
                      ],
                      fontWeight: FontWeight.w600,
                      color: _isValidHex ? cs.onSurface : cs.error,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _isValidHex ? cs.outline : cs.error,
                        ),
                      ),
                      isDense: true,
                      hintText: 'HEX',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Consolas',
                        fontFamilyFallback: const [
                          'Menlo',
                          'Courier New',
                          'MiSans',
                        ],
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(2),
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    ],
                    onChanged: _onHexChanged,
                    onSubmitted: _onHexSubmitted,
                    onEditingComplete: () =>
                        _onHexSubmitted(_hexController!.text),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: widget.onWrite,
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('写入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hexController?.dispose();
    super.dispose();
  }
}
