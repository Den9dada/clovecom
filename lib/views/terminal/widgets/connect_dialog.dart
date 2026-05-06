import 'package:flutter/material.dart';

import '../../../models/terminal/serial_connection_params.dart';
import '../../../models/terminal/ssh_connection_params.dart';
import '../../../services/terminal/serial_terminal_service.dart';
import '../../../viewmodels/terminal/terminal_viewmodel.dart';

class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key, required this.viewModel});

  final TerminalViewModel viewModel;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  var _mode = 0;

  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController();

  String? _serialPort;
  int _baudRate = 115200;
  int _dataBits = 8;
  int _stopBits = 1;
  String _parity = 'None';
  bool _customBaud = false;
  int _customBaudRate = 115200;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Text('新建连接'),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('SSH'),
                  icon: Icon(Icons.cloud, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('串口'),
                  icon: Icon(Icons.usb, size: 16),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 14),
            if (_mode == 0) ..._sshFields(theme) else ..._serialFields(theme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _connect, child: const Text('连接')),
      ],
    );
  }

  List<Widget> _sshFields(ThemeData theme) {
    return [
      TextField(
        controller: _hostCtrl,
        decoration: const InputDecoration(
          labelText: '主机/IP',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _portCtrl,
        decoration: const InputDecoration(
          labelText: '端口',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(
          labelText: '会话名称（可选）',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _userCtrl,
        decoration: const InputDecoration(
          labelText: '用户名',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _passCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '密码',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    ];
  }

  List<Widget> _serialFields(ThemeData theme) {
    final ports = SerialTerminalService.getAvailablePorts();
    if (_serialPort == null && ports.isNotEmpty) _serialPort = ports.first;

    return [
      DropdownButtonFormField<String>(
        value: ports.contains(_serialPort) ? _serialPort : null,
        decoration: const InputDecoration(
          labelText: '端口',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: ports
            .map((p) => DropdownMenuItem(value: p, child: Text(p)))
            .toList(),
        onChanged: (v) => setState(() => _serialPort = v),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        value: _customBaud ? -1 : _baudRate,
        decoration: const InputDecoration(
          labelText: '波特率',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          ...SerialConnectionParams.baudRatePresets.map(
            (r) => DropdownMenuItem(value: r, child: Text('$r')),
          ),
          const DropdownMenuItem(value: -1, child: Text('自定义')),
        ],
        onChanged: (v) {
          setState(() {
            if (v == -1) {
              _customBaud = true;
            } else {
              _customBaud = false;
              _baudRate = v!;
            }
          });
        },
      ),
      if (_customBaud) ...[
        const SizedBox(height: 10),
        TextField(
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '自定义波特率',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) =>
              _customBaudRate = int.tryParse(v) ?? _customBaudRate,
        ),
      ],
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _dataBits,
              decoration: const InputDecoration(
                labelText: '数据位',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: SerialConnectionParams.dataBitsOptions
                  .map(
                    (v) =>
                        DropdownMenuItem(value: v, child: Text('$v')),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _dataBits = v);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _stopBits,
              decoration: const InputDecoration(
                labelText: '停止位',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: SerialConnectionParams.stopBitsOptions
                  .map(
                    (v) =>
                        DropdownMenuItem(value: v, child: Text('$v')),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _stopBits = v);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _parity,
        decoration: const InputDecoration(
          labelText: '校验位',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: SerialConnectionParams.parityOptions
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _parity = v);
        },
      ),
    ];
  }

  void _connect() {
    final vm = widget.viewModel;
    Navigator.pop(context);

    if (_mode == 0) {
      vm.createSshSession(SshConnectionParams(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 22,
        sessionName: _nameCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      ));
    } else {
      if (_serialPort == null) return;
      vm.createSerialSession(SerialConnectionParams(
        port: _serialPort!,
        baudRate: _customBaud ? _customBaudRate : _baudRate,
        dataBits: _dataBits,
        stopBits: _stopBits,
        parity: _parity,
      ));
    }
  }
}
