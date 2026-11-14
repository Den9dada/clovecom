import 'dart:async';
import '../../services/protocol_library.dart';
import 'package:flutter/material.dart';
import '../../ui/desktop_theme.dart';
import '../../widgets/serial_port_input.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/baud_rate_input.dart';
import '../../viewmodels/serial_port_viewmodel.dart';
import '../../services/status_bar_service.dart';

/// 独立持有连接和升级任务，切换导航时保留页面状态。
class FirmwareUpgradeView extends StatefulWidget {
  const FirmwareUpgradeView({
    super.key,
    this.createViewModel,
    this.protocolLibrary,
  });
  final SerialPortViewModel Function()? createViewModel;
  final ProtocolLibrary? protocolLibrary;

  @override
  State<FirmwareUpgradeView> createState() => _FirmwareUpgradeViewState();
}

class _FirmwareUpgradeViewState extends State<FirmwareUpgradeView> {
  late final SerialPortViewModel _vm;
  StreamSubscription<String>? _errors;
  String? _protocolCandidate;

  @override
  void initState() {
    super.initState();
    _vm =
        widget.createViewModel?.call() ??
        SerialPortViewModel(protocolLibrary: widget.protocolLibrary);
    _protocolCandidate = _vm.firmwareProtocols?.loaded?.id;
    _vm.addListener(_updated);
    _errors = _vm.errorStream.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updated();
    });
  }

  void _updated() {
    if (!mounted) return;
    StatusBarService().update(
      5,
      StatusBarInfo(
        text: _vm.firmwareConfig.isUpgrading
            ? '固件升级中'
            : _vm.state.isConnected
            ? '已连接 ${_vm.config.portName}'
            : '未连接',
        icon: _vm.state.isConnected
            ? Icons.check_circle
            : Icons.circle_outlined,
      ),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _errors?.cancel();
    _vm.removeListener(_updated);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('固件升级', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          // 短暂校验仅拦截交互，避免参数框禁用样式来回切换而闪动。
          AbsorbPointer(
            absorbing: _vm.firmwareProtocols?.loading == true,
            child: ExcludeFocus(
              excluding: _vm.firmwareProtocols?.loading == true,
              child: _connectionCard(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final settings = Card(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: Text(
                            '升级配置',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _buildFirmwareUpgradeArea(_vm, colors),
                      ],
                    ),
                  ),
                );
                if (constraints.maxWidth >= 1000) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 420, child: settings),
                      const SizedBox(width: 12),
                      Expanded(child: _logs()),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: settings),
                    const SizedBox(height: 12),
                    Expanded(flex: 2, child: _logs()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectProtocol(String? id) async {
    if (id == null) return;
    setState(() => _protocolCandidate = id);
    await _vm.loadFirmwareProtocol(id);
    if (!mounted) return;
    // 载入失败保留原快照，同时让选项恢复到实际已载入的协议。
    setState(() => _protocolCandidate = _vm.firmwareProtocols?.loaded?.id);
  }

  Widget _protocolSelector() {
    final binding = _vm.firmwareProtocols!;
    final available = binding.available;
    final candidate = available.any((p) => p.id == _protocolCandidate)
        ? _protocolCandidate
        : null;
    final locked = _vm.isTransferBusy || binding.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          '升级交互协议',
          AppDropdownFormField<String>(
            key: ValueKey('firmware-protocol-$candidate'),
            value: candidate,
            decoration: _controlDecoration.copyWith(
              hintText: '选择已保存的 Lua 协议',
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 28,
                height: 28,
              ),
              suffixIcon: binding.loaded == null
                  ? null
                  : IconButton(
                      key: const ValueKey('unload-firmware-protocol'),
                      tooltip: '卸载协议',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onPressed: locked
                          ? null
                          : () {
                              _vm.unloadFirmwareProtocol();
                              setState(() => _protocolCandidate = null);
                            },
                      icon: const Icon(Icons.close),
                    ),
            ),
            style: _controlTextStyle,
            menuMaxHeight: 260,
            iconEnabledColor: Theme.of(context).colorScheme.onSurfaceVariant,
            items: available
                .map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: locked
                ? null
                : (value) => unawaited(_selectProtocol(value)),
          ),
        ),
        if (!binding.loading && binding.hasNewVersion)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '协议有新版本，请重新选择该协议；当前仍使用已载入版本',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _connectionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SerialPortInput(
                  directory: _vm.portDirectory,
                  value: _vm.config.portName,
                  enabled: !_connectionParametersLocked,
                  onChanged: (value) => _vm.updateConfig(portName: value),
                ),
              ),
              IconButton(
                onPressed: _vm.refreshPorts,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新串口列表',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  if (_vm.state.isConnected) {
                    await _vm.disconnect();
                  } else {
                    await _vm.connect();
                  }
                },
                icon: Icon(
                  _vm.state.isConnected ? Icons.link_off : Icons.link,
                  size: 16,
                ),
                label: Text(_vm.state.isConnected ? '断开连接' : '打开串口'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 136,
                child: _field(
                  '波特率',
                  BaudRateInput(
                    value: _vm.config.baudRate,
                    onChanged: _connectionParametersLocked
                        ? null
                        : (value) => _vm.updateConfig(baudRate: value),
                  ),
                ),
              ),
              _option<int>('数据位', _vm.config.dataBits, [
                5,
                6,
                7,
                8,
              ], (value) => _vm.updateConfig(dataBits: value)),
              _option<int>('停止位', _vm.config.stopBits, [
                1,
                2,
              ], (value) => _vm.updateConfig(stopBits: value)),
              _option<String>('校验', _vm.config.parity, [
                'None',
                'Odd',
                'Even',
                'Mark',
                'Space',
              ], (value) => _vm.updateConfig(parity: value)),
              _option<String>('流控', _vm.config.flowControl, [
                'None',
                'XON/XOFF',
                'RTS/CTS',
                'DTR/DSR',
              ], (value) => _vm.updateConfig(flowControl: value)),
            ],
          ),
          if (_vm.state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _vm.state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );

  static const _controlDecoration = InputDecoration(
    constraints: BoxConstraints.tightFor(height: 32),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );

  bool get _connectionParametersLocked =>
      _vm.state.isConnected || _vm.isTransferBusy;

  TextStyle? get _controlTextStyle =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      );

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(height: 32, child: child),
    ],
  );

  Widget _option<T>(
    String label,
    T value,
    List<T> options,
    ValueChanged<T> changed,
  ) => SizedBox(
    width: 136,
    child: _field(
      label,
      AppDropdownFormField<T>(
        key: ValueKey('firmware-option-$label'),
        value: value,
        decoration: _controlDecoration,
        style: _controlTextStyle,
        menuMaxHeight: 260,
        iconEnabledColor: Theme.of(context).colorScheme.onSurfaceVariant,
        items: [...options, if (!options.contains(value)) value]
            .map(
              (option) =>
                  DropdownMenuItem<T>(value: option, child: Text('$option')),
            )
            .toList(),
        onChanged: _connectionParametersLocked
            ? null
            : (next) {
                if (next != null) changed(next);
              },
      ),
    ),
  );

  Widget _logs() => Card(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '升级日志',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: _vm.clearMessages,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空日志'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _vm.messages.isEmpty
              ? const Center(child: Text('暂无升级日志'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: _vm.messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        _vm.messages[_vm.messages.length - index - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(
                        '[${message.timestamp.toIso8601String().substring(11, 19)}] ${message.data}',
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  /// 构建固件升级区
  Widget _buildFirmwareUpgradeArea(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    final config = viewModel.firmwareConfig;
    final isUpgrading = config.isUpgrading;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 固件文件选择
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  key: const ValueKey('firmware-file-field'),
                  expands: true,
                  decoration: _controlDecoration.copyWith(
                    visualDensity: VisualDensity.standard,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.system_update_outlined,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          config.firmwareName.isEmpty
                              ? '未选择固件 (.bin)'
                              : config.firmwareName,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  key: const ValueKey('select-firmware-file'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    maximumSize: const Size(double.infinity, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                  ),
                  onPressed: viewModel.isTransferBusy
                      ? null
                      : viewModel.selectFirmwareFile,
                  child: const Text('选择固件'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_vm.firmwareProtocols != null) ...[
            _protocolSelector(),
            const SizedBox(height: 8),
          ],
          if (_vm.firmwareProtocols?.loaded == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('请先选择并载入升级协议'),
            ),
          const SizedBox(height: 8),
          // 进度条（仅在选择了固件或正在升级时显示）
          if (config.firmwareSize > 0 || isUpgrading) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isUpgrading && config.progress <= 0
                          ? null
                          : config.progress,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(config.progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      viewModel.state.isConnected &&
                          !viewModel.isTransferBusy &&
                          _vm.firmwareProtocols?.loading != true &&
                          _vm.firmwareProtocols?.loaded != null
                      ? viewModel.startFirmwareUpgrade
                      : null,
                  icon: const Icon(Icons.upgrade, size: 16),
                  label: const Text('开始升级'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isUpgrading ? viewModel.stopFirmwareUpgrade : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                  style: desktopActionStyle(DesktopActionKind.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
