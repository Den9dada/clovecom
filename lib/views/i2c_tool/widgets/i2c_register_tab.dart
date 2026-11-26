// Register 子页 — 加载 Excel 寄存器映射，读写芯片寄存器

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import '../../../viewmodels/ch341/i2c_tool_viewmodel.dart';
import '../../../models/i2c_register_map.dart';
import 'i2c_chip_config_card.dart';
import 'i2c_register_list.dart';
import 'i2c_register_card.dart';
import 'i2c_bit_field_row.dart';
import 'i2c_operation_bar.dart';
import 'i2c_log_panel.dart';

class I2cRegisterTab extends StatefulWidget {
  const I2cRegisterTab({super.key});

  @override
  State<I2cRegisterTab> createState() => _I2cRegisterTabState();
}

class _I2cRegisterTabState extends State<I2cRegisterTab> {
  double _logHeight = 200;
  static const double _logMinHeight = 80;
  static const double _logMaxHeight = 600;
  static const double _dividerThickness = 6;

  Future<void> _loadExcel() async {
    final result = await FilePickerCompat.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null)
        await context.read<I2cToolViewModel>().loadExcelFile(path);
    }
  }

  Future<void> _exportExcel() async {
    final map = context.read<I2cToolViewModel>().registerMap;
    if (map == null) return;
    final defaultName =
        '${map.chipConfig.moduleName}_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}.xlsx';
    final result = await FilePickerCompat.saveFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      fileName: defaultName,
    );
    if (result != null)
      await context.read<I2cToolViewModel>().exportExcel(result);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<I2cToolViewModel>();
    final cs = Theme.of(context).colorScheme;

    if (!vm.hasMapLoaded) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart, size: 48, color: cs.primary),
            const SizedBox(height: 16),
            Text('加载芯片寄存器映射', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '拖入 .xlsx 文件或点击下方按钮加载',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadExcel,
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('加载Excel'),
            ),
            if (vm.statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  vm.statusMessage!,
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ),
          ],
        ),
      );
    }

    final registers = vm.registerMap!.registers;
    final chipConfig = vm.registerMap!.chipConfig;
    final selIdx = vm.selectedRegisterIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 280,
                child: Column(
                  children: [
                    I2cChipConfigCard(
                      config: chipConfig,
                      registerCount: registers.length,
                      speedLabel:
                          I2cToolViewModel.i2cSpeedOptions[vm.i2cSpeed]['label']
                              as String,
                    ),
                    // Excel 加载按钮（仅加载）
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loadExcel,
                          icon: const Icon(Icons.file_open, size: 16),
                          label: const Text(
                            '加载Excel配置表',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: I2cRegisterList(
                        registers: registers,
                        selectedIndex: selIdx,
                        onSelect: (i) => vm.selectRegister(i),
                        onDoubleTap: (i) => vm.selectAndRead(i),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    I2cOperationBar(
                      isBusy: vm.isBusy,
                      hasMap: true,
                      onReadAll: () => vm.readAllRegisters(),
                      onWriteAll: () => vm.writeAllRegisters(),
                      onExport: null, // 导出在左侧
                    ),
                    if (selIdx != null && selIdx < registers.length)
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildDetail(vm, registers[selIdx]),
                        ),
                      )
                    else
                      Expanded(
                        child: Center(
                          child: Text(
                            '← 点击寄存器列表查看详情',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    _divider(context),
                    SizedBox(
                      height: _logHeight,
                      child: I2cLogPanel(
                        logs: vm.operationLog,
                        onClear: () => vm.clearLog(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        // 窄屏
        return Column(
          children: [
            I2cChipConfigCard(
              config: chipConfig,
              registerCount: registers.length,
              speedLabel:
                  I2cToolViewModel.i2cSpeedOptions[vm.i2cSpeed]['label']
                      as String,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadExcel,
                  icon: const Icon(Icons.file_open, size: 16),
                  label: const Text(
                    '加载Excel配置表',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
            I2cOperationBar(
              isBusy: vm.isBusy,
              hasMap: true,
              onReadAll: () => vm.readAllRegisters(),
              onWriteAll: () => vm.writeAllRegisters(),
              onExport: null,
            ),
            Expanded(
              child: selIdx != null
                  ? SingleChildScrollView(
                      child: _buildDetail(vm, registers[selIdx]),
                    )
                  : I2cRegisterList(
                      registers: registers,
                      selectedIndex: selIdx,
                      onSelect: (i) => vm.selectRegister(i),
                      onDoubleTap: (i) => vm.selectAndRead(i),
                    ),
            ),
            _divider(context),
            SizedBox(
              height: _logHeight,
              child: I2cLogPanel(
                logs: vm.operationLog,
                onClear: () => vm.clearLog(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetail(I2cToolViewModel vm, I2cRegister reg) {
    final regIdx = vm.registerMap!.registers.indexOf(reg);
    return Column(
      children: [
        I2cRegisterCard(
          register: reg,
          regIndex: regIdx,
          onHexChanged: (v) => vm.setRegisterHexValue(regIdx, v),
          onRead: () => vm.readRegister(regIdx),
          onWrite: () => vm.writeRegister(regIdx),
          onResetDefault: () => vm.resetRegisterToDefault(regIdx),
        ),
        for (int i = 0; i < reg.bitFields.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: I2cBitFieldRow(
              bitField: reg.bitFields[i],
              currentFullValue: reg.editingValue ?? reg.currentValue ?? 0,
              readValue: reg.currentValue,
              onChanged: reg.bitFields[i].isReadOnly
                  ? null
                  : (v) => vm.updateBitFieldValue(regIdx, i, v),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _divider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        setState(() {
          _logHeight = (_logHeight - d.delta.dy).clamp(
            _logMinHeight,
            _logMaxHeight,
          );
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: _dividerThickness,
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
    );
  }
}
