// Transform 子页 — 原始 I2C 收发 + I2C 设备探测

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../viewmodels/ch341/i2c_tool_viewmodel.dart';
import '../../../models/ch341_operation_result.dart';

class I2cTransformTab extends StatefulWidget {
  const I2cTransformTab({super.key});

  @override
  State<I2cTransformTab> createState() => _I2cTransformTabState();
}

class _I2cTransformTabState extends State<I2cTransformTab> {
  final _devAddrCtrl = TextEditingController(text: '07');
  final _regAddrCtrl = TextEditingController(text: '00');
  final _writeDataCtrl = TextEditingController();
  final _readLenCtrl = TextEditingController(text: '1');
  double _logHeight = 200;
  static const double _logMinHeight = 80;
  static const double _logMaxHeight = 600;

  // I2C 扫描状态
  bool _isScanning = false;
  final Set<int> _foundAddresses = {};
  int _scanProgress = 0;

  @override
  void dispose() {
    _devAddrCtrl.dispose();
    _regAddrCtrl.dispose();
    _writeDataCtrl.dispose();
    _readLenCtrl.dispose();
    super.dispose();
  }

  int get _devAddr => int.tryParse(_devAddrCtrl.text.trim(), radix: 16) ?? 0x07;
  int get _regAddr => int.tryParse(_regAddrCtrl.text.trim(), radix: 16) ?? 0x00;
  int get _readLen =>
      int.tryParse(_readLenCtrl.text.trim())?.clamp(0, 256) ?? 1;

  List<int> get _writeData {
    final hex = _writeDataCtrl.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (hex.isEmpty) return [];
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
        if (b != null) bytes.add(b);
      }
    }
    return bytes;
  }

  Future<void> _doRead() async {
    if (!context.read<I2cToolViewModel>().isConnected) {
      context.read<I2cToolViewModel>().addLogMessage('请先连接 CH341 设备', false);
      return;
    }
    await context.read<I2cToolViewModel>().transformRead(
      _devAddr,
      _regAddr,
      _readLen,
    );
  }

  Future<void> _doWrite() async {
    if (!context.read<I2cToolViewModel>().isConnected) {
      context.read<I2cToolViewModel>().addLogMessage('请先连接 CH341 设备', false);
      return;
    }
    final data = _writeData;
    if (data.isEmpty) {
      context.read<I2cToolViewModel>().addLogMessage('请输入要写入的十六进制数据', false);
      return;
    }
    await context.read<I2cToolViewModel>().transformWrite(
      _devAddr,
      _regAddr,
      data,
    );
  }

  Future<void> _doScan() async {
    if (!context.read<I2cToolViewModel>().isConnected) {
      context.read<I2cToolViewModel>().addLogMessage('请先连接 CH341 设备', false);
      return;
    }
    setState(() {
      _isScanning = true;
      _foundAddresses.clear();
      _scanProgress = 0;
    });

    await context.read<I2cToolViewModel>().i2cScan(
      onProgress: (progress, addr) {
        setState(() {
          _scanProgress = progress;
          if (addr != null) _foundAddresses.add(addr);
        });
      },
    );

    setState(() {
      _isScanning = false;
      _scanProgress = 128;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<I2cToolViewModel>();
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        final leftPanel = SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 配置区
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'I2C 通信配置',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _hexField('设备地址', _devAddrCtrl, 2)),
                          const SizedBox(width: 8),
                          Expanded(child: _hexField('寄存器地址', _regAddrCtrl, 2)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            child: _numField('读取长度', _readLenCtrl),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('写入数据 (HEX)', style: _labelStyle(cs)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 60,
                        child: TextField(
                          controller: _writeDataCtrl,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'Consolas',
                            fontFamilyFallback: [
                              'Menlo',
                              'Courier New',
                              'MiSans',
                            ],
                          ),
                          decoration: const InputDecoration(
                            hintText: '例: 1A FF 00',
                            hintStyle: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Consolas',
                              fontFamilyFallback: [
                                'Menlo',
                                'Courier New',
                                'MiSans',
                              ],
                            ),
                            contentPadding: EdgeInsets.all(8),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9a-fA-F\s]'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 操作按钮
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: vm.isBusy || !vm.isConnected ? null : _doRead,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('读取'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: vm.isBusy || !vm.isConnected ? null : _doWrite,
                      icon: const Icon(Icons.upload, size: 16),
                      label: const Text('写入'),
                    ),
                  ),
                ],
              ),
              // I2C 设备探测
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'I2C 设备探测',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          if (_isScanning)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            TextButton.icon(
                              onPressed: vm.isConnected ? _doScan : null,
                              icon: const Icon(Icons.radar, size: 16),
                              label: const Text('开始扫描'),
                            ),
                        ],
                      ),
                      if (_isScanning || _foundAddresses.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: _scanProgress / 128),
                        const SizedBox(height: 4),
                        Text(
                          _isScanning
                              ? '扫描中... $_scanProgress/128'
                              : '发现 ${_foundAddresses.length} 个设备',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (_foundAddresses.isNotEmpty)
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: _foundAddresses
                                .map(
                                  (a) => Chip(
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      '0x${a.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'Consolas',
                                        fontFamilyFallback: [
                                          'Menlo',
                                          'Courier New',
                                          'MiSans',
                                        ],
                                      ),
                                    ),
                                    backgroundColor: Colors.green.withValues(
                                      alpha: 0.12,
                                    ),
                                    labelStyle: TextStyle(
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        // 日志
        final logs = List.unmodifiable(vm.operationLog);
        final okCount = logs.where((l) => l.success).length;
        final failCount = logs.where((l) => !l.success).length;
        final logPanel = Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '通信日志',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '✓$okCount  ✗$failCount',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (logs.isNotEmpty)
                      GestureDetector(
                        onTap: () =>
                            context.read<I2cToolViewModel>().clearLog(),
                        child: Icon(
                          Icons.clear_all,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          '等待操作...',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 8, endIndent: 8),
                        itemBuilder: (_, i) {
                          final log = logs[i];
                          final time =
                              '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontFamily: 'Consolas',
                                    fontFamilyFallback: const [
                                      'Menlo',
                                      'Courier New',
                                      'MiSans',
                                    ],
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  log.success
                                      ? Icons.check_circle
                                      : Icons.error,
                                  size: 12,
                                  color: log.success ? Colors.green : cs.error,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.description,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      if (log.errorMessage != null)
                                        Text(
                                          log.errorMessage!,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: cs.error,
                                          ),
                                        ),
                                      if (log.data != null &&
                                          log.data!.isNotEmpty)
                                        Text(
                                          log.hexData,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontFamily: 'Consolas',
                                            fontFamilyFallback: const [
                                              'Menlo',
                                              'Courier New',
                                              'MiSans',
                                            ],
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );

        if (isWide) {
          return Row(
            children: [
              SizedBox(width: 340, child: leftPanel),
              const VerticalDivider(width: 1),
              Expanded(child: logPanel),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(height: 300, child: leftPanel),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(() {
                _logHeight = (_logHeight - d.delta.dy).clamp(
                  _logMinHeight,
                  _logMaxHeight,
                );
              }),
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: Container(
                  height: 6,
                  color: cs.surfaceContainerHighest,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: logPanel),
          ],
        );
      },
    );
  }

  Widget _hexField(String label, TextEditingController ctrl, int maxLen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 2),
        SizedBox(
          height: 28,
          child: TextField(
            controller: ctrl,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'Consolas',
              fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
            ),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxLen),
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 2),
        SizedBox(
          height: 28,
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _labelStyle(ColorScheme cs) =>
      TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
}
