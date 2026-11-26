import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'app_dropdown.dart';

/// 支持直接输入及常用值选择；有效输入立即同步至串口配置。
class BaudRateInput extends StatefulWidget {
  const BaudRateInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  State<BaudRateInput> createState() => _BaudRateInputState();
}

class _BaudRateInputState extends State<BaudRateInput> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focusNode = FocusNode();
  static const _presets = [
    1200,
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];

  int? get _parsed {
    final value = int.tryParse(_controller.text);
    // Win32 DCB 的波特率字段为无符号 32 位整数。
    return value != null && value > 0 && value <= 0xFFFFFFFF ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_restoreInvalidInput);
  }

  void _restoreInvalidInput() {
    if (!_focusNode.hasFocus && _parsed == null) {
      setState(() => _controller.text = '${widget.value}');
    }
  }

  @override
  void didUpdateWidget(covariant BaudRateInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _parsed != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppPopupMenuButton<int>(
          enabled: widget.onChanged != null,
          initialValue: widget.value,
          menuWidth: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          menuMaxHeight: 280,
          itemBuilder: (_) => _presets
              .map((rate) => PopupMenuItem(value: rate, child: Text('$rate')))
              .toList(),
          onSelected: (rate) {
            setState(() => _controller.text = '$rate');
            widget.onChanged?.call(rate);
          },
          anchorBuilder: (context, toggle, menuFocusNode) => TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.onChanged != null,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              errorText: _parsed == null ? '请输入有效的正整数' : null,
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 32,
                height: 32,
              ),
              suffixIcon: IconButton(
                focusNode: menuFocusNode,
                tooltip: '常用波特率',
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                onPressed: widget.onChanged != null ? toggle : null,
              ),
            ),
            onChanged: (_) {
              setState(() {});
              final value = _parsed;
              if (value != null) widget.onChanged?.call(value);
            },
            onSubmitted: (_) => _focusNode.unfocus(),
          ),
        );
      },
    );
  }
}
