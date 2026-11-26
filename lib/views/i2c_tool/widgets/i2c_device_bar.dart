import 'package:clovecom/widgets/app_dropdown.dart';
// 公共设备连接栏 — 设备选择/刷新/速率/连接

import 'package:material_ui/material_ui.dart';
import '../../../viewmodels/ch341/i2c_tool_viewmodel.dart';

class I2cDeviceBar extends StatelessWidget {
  final I2cToolViewModel viewModel;

  const I2cDeviceBar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vm = viewModel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          // 状态指示
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: vm.isConnected ? Colors.green : cs.outlineVariant,
            ),
          ),
          // 设备选择
          Expanded(
            flex: 3,
            child: AppDropdownFormField<int>(
              isExpanded: true,
              value: vm.selectedDeviceIndex,
              decoration: InputDecoration(
                labelText: 'CH341设备',
                labelStyle: TextStyle(
                  fontFamily: 'MiSans',
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
              style: TextStyle(
                fontFamily: 'MiSans',
                fontSize: 13,
                color: cs.onSurface,
              ),
              dropdownColor: cs.surface,
              items: vm.availableDevices.isEmpty
                  ? [
                      DropdownMenuItem<int>(
                        value: null,
                        child: Text(
                          '未检测到 CH341 设备',
                          style: TextStyle(
                            fontFamily: 'MiSans',
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ]
                  : vm.availableDevices.map((d) {
                      return DropdownMenuItem<int>(
                        value: d.deviceIndex,
                        child: Text(
                          d.description,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'MiSans',
                            fontSize: 12,
                            color: cs.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
              onChanged: vm.isConnected
                  ? null
                  : (idx) {
                      if (idx != null) vm.connect(idx);
                    },
            ),
          ),
          const SizedBox(width: 6),
          // 刷新
          SizedBox(
            height: 32,
            width: 36,
            child: IconButton(
              onPressed: vm.isConnecting ? null : () => vm.refreshDevices(),
              icon: Icon(
                Icons.refresh,
                size: 18,
                color: vm.isConnecting ? cs.outline : cs.onSurface,
              ),
              padding: EdgeInsets.zero,
              tooltip: '刷新设备列表',
            ),
          ),
          const SizedBox(width: 6),
          // 速率
          SizedBox(
            width: 144,
            child: AppDropdownFormField<int>(
              isExpanded: true,
              value: vm.i2cSpeed,
              decoration: InputDecoration(
                labelText: 'I2C速率',
                labelStyle: TextStyle(
                  fontFamily: 'MiSans',
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 0,
                ),
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
              style: TextStyle(
                fontFamily: 'MiSans',
                fontSize: 12,
                color: cs.onSurface,
              ),
              dropdownColor: cs.surface,
              items: I2cToolViewModel.i2cSpeedOptions.map((opt) {
                return DropdownMenuItem<int>(
                  value: opt['value'] as int,
                  child: Text(
                    opt['label'] as String,
                    style: TextStyle(
                      fontFamily: 'MiSans',
                      fontSize: 12,
                      color: cs.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: vm.isConnected
                  ? null
                  : (speed) {
                      if (speed != null) vm.setI2cSpeed(speed);
                    },
            ),
          ),
          const SizedBox(width: 8),
          // 连接/断开
          if (vm.isConnected)
            FilledButton.icon(
              onPressed: () => vm.disconnect(),
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text(
                '断开',
                style: TextStyle(fontFamily: 'MiSans', fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                minimumSize: const Size(60, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            )
          else
            FilledButton.icon(
              onPressed: vm.isConnecting || vm.availableDevices.isEmpty
                  ? null
                  : () {
                      final idx =
                          vm.selectedDeviceIndex ??
                          vm.availableDevices.first.deviceIndex;
                      vm.connect(idx);
                    },
              icon: vm.isConnecting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.link, size: 16),
              label: Text(
                vm.isConnecting ? '连接中...' : '连接',
                style: const TextStyle(fontFamily: 'MiSans', fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(60, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
        ],
      ),
    );
  }
}
