import 'package:material_ui/material_ui.dart';
import '../models/serial_port_model.dart';
import '../services/serial/serial_port_catalog.dart';

/// 菜单直接监听目录快照，展开期间仍能响应设备插拔。
class SerialPortInput extends StatefulWidget {
  const SerialPortInput({
    super.key,
    required this.directory,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final SerialPortDirectory directory;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<SerialPortInput> createState() => _SerialPortInputState();
}

class _SerialPortInputState extends State<SerialPortInput> {
  final _link = LayerLink();
  late final TextEditingController _controller;
  OverlayEntry? _menu;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant SerialPortInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) _controller.text = widget.value;
    if (!widget.enabled) _closeMenu();
  }

  void _closeMenu() {
    _menu?.remove();
    _menu?.dispose();
    _menu = null;
  }

  void _toggleMenu() {
    if (_menu != null) {
      _closeMenu();
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    _menu = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, box.size.height + 4),
            child: SizedBox(
              width: box.size.width,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: AnimatedBuilder(
                  animation: widget.directory,
                  builder: (context, _) {
                    final scan = widget.directory.snapshot;
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          if (widget.directory.warning != null)
                            ListTile(
                              title: Text(
                                widget.directory.warning!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          if (scan.devices.isEmpty)
                            const ListTile(title: Text('未发现串口，可手动输入端口名')),
                          for (final port in scan.devices) _portTile(port),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_menu!);
  }

  Widget _portTile(PortDetailInfo port) => ListTile(
    dense: true,
    title: Text(port.displayText),
    selected: port.portName == widget.value,
    onTap: () {
      _closeMenu();
      _controller.text = port.portName;
      widget.onChanged(port.portName);
    },
  );

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: TextField(
      controller: _controller,
      enabled: widget.enabled,
      onChanged: (value) => widget.onChanged(value.trim().toUpperCase()),
      decoration: InputDecoration(
        hintText: '选择或输入端口',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        suffixIcon: IconButton(
          onPressed: widget.enabled ? _toggleMenu : null,
          tooltip: '选择串口',
          icon: const Icon(Icons.arrow_drop_down),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _closeMenu();
    _controller.dispose();
    super.dispose();
  }
}
