import 'package:clovecom/widgets/app_dropdown.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/toolbox/crc_params.dart';
import '../../../services/status_bar_service.dart';
import '../../../viewmodels/toolbox/crc_viewmodel.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/hex_ascii_viewer.dart';

class CrcTool extends StatefulWidget {
  const CrcTool({super.key});

  @override
  State<CrcTool> createState() => _CrcToolState();
}

class _CrcToolState extends State<CrcTool> with AutomaticKeepAliveClientMixin {
  late final CrcViewModel _viewModel = CrcViewModel();
  var _dragging = false;

  @override
  bool get wantKeepAlive => true;

  bool get _isCurrentTab {
    final controller = DefaultTabController.of(context);
    return controller.index == 3;
  }

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_updateStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStatus());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_updateStatus);
    _viewModel.dispose();
    super.dispose();
  }

  void _updateStatus() {
    final selected = _viewModel.selectedFiles;
    final text = selected.isEmpty
        ? (_viewModel.files.isEmpty ? '就绪 — 拖入或打开文件' : '未选中文件')
        : selected.map((f) => f.path).join(' | ');
    StatusBarService().updateToolboxStatus(
      3,
      StatusBarInfo(
        text: text,
        icon: selected.isNotEmpty ? Icons.insert_drive_file : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: DropTarget(
        onDragEntered: (_) {
          if (_isCurrentTab) setState(() => _dragging = true);
        },
        onDragExited: (_) {
          if (_isCurrentTab) setState(() => _dragging = false);
        },
        onDragDone: (details) async {
          if (!_isCurrentTab) return;
          final paths = details.files.map((f) => f.path).toList();
          if (paths.isNotEmpty) {
            await _viewModel.importFiles(paths);
          }
          if (mounted) setState(() => _dragging = false);
        },
        child: Stack(
          children: [
            const _CrcToolContent(),
            if (_dragging) _buildDragOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDragOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: cs.primaryContainer.withValues(alpha: 0.15),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 48),
              SizedBox(height: 12),
              Text(
                '松开以导入文件',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text('支持任意文件格式', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrcToolContent extends StatelessWidget {
  const _CrcToolContent();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CrcViewModel>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _buildControls(context, viewModel);

        Widget rightPane;
        if (viewModel.showAboutPopup) {
          rightPane = _buildAboutPanel(context, viewModel);
        } else if (viewModel.inputMode == DataInputMode.file &&
            viewModel.selectedFiles.isNotEmpty) {
          rightPane = Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '文件预览: ${viewModel.selectedFiles.length} / ${viewModel.files.length} 个文件 · ${CrcViewModel.formatFileSize(viewModel.selectedFileSize)}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Expanded(
                flex: 6,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: HexAsciiViewer(bytes: viewModel.currentBytes!),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(flex: 4, child: _buildResultCard(context, viewModel)),
            ],
          );
        } else {
          rightPane = _buildResultCard(context, viewModel);
        }

        if (compact) {
          return Column(
            children: [
              controls,
              const SizedBox(height: 10),
              Expanded(child: rightPane),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 320, child: controls),
            const SizedBox(width: 10),
            Expanded(child: rightPane),
          ],
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, CrcViewModel viewModel) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInputCard(context, viewModel),
          const SizedBox(height: 10),
          _buildParamsCard(context, viewModel),
        ],
      ),
    );
  }

  Widget _buildInputCard(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据输入', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<DataInputMode>(
              segments: const [
                ButtonSegment(
                  value: DataInputMode.hex,
                  label: Text('Hex'),
                  icon: Icon(Icons.hexagon_outlined, size: 16),
                ),
                ButtonSegment(
                  value: DataInputMode.ascii,
                  label: Text('ASCII'),
                  icon: Icon(Icons.text_fields, size: 16),
                ),
                ButtonSegment(
                  value: DataInputMode.file,
                  label: Text('文件'),
                  icon: Icon(Icons.insert_drive_file_outlined, size: 16),
                ),
              ],
              selected: {viewModel.inputMode},
              onSelectionChanged: (v) => viewModel.setInputMode(v.first),
            ),
            const SizedBox(height: 10),
            _buildInputContent(context, viewModel),
          ],
        ),
      ),
    );
  }

  Widget _buildInputContent(BuildContext context, CrcViewModel viewModel) {
    switch (viewModel.inputMode) {
      case DataInputMode.hex:
        return TextField(
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '例如: 31 32 33 34',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(10),
          ),
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
            fontSize: 13,
          ),
          onChanged: viewModel.setHexText,
        );
      case DataInputMode.ascii:
        return TextField(
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '例如: hello world',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(10),
          ),
          onChanged: viewModel.setAsciiText,
        );
      case DataInputMode.file:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropZone(
              title: '导入文件',
              subtitle: '拖入或点击选择文件，计算 CRC（支持多选）',
              allowedExtensions: const [],
              allowMultiple: true,
              onFilesSelected: (paths) async {
                await context.read<CrcViewModel>().importFiles(paths);
              },
            ),
            if (viewModel.hasFiles) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < viewModel.files.length; i++)
                      _buildFileRow(context, viewModel, i),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }

  Widget _buildParamsCard(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CRC 参数', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppDropdownFormField<String>(
                    key: ValueKey(viewModel.selectedPreset),
                    initialValue: viewModel.selectedPreset ?? '自定义',
                    decoration: const InputDecoration(
                      labelText: '预设模型',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    isExpanded: true,
                    items: CrcPresets.presetNames.map((name) {
                      return DropdownMenuItem(
                        value: name,
                        child: Text(name, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      viewModel.selectPreset(value == '自定义' ? null : value);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _buildAboutButton(viewModel, colorScheme),
              ],
            ),
            if (!viewModel.isCustomMode) ...[
              const SizedBox(height: 10),
              _buildPresetParams(viewModel, theme),
            ],
            if (viewModel.isCustomMode) ...[
              const SizedBox(height: 10),
              _buildCustomParams(viewModel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPresetParams(CrcViewModel viewModel, ThemeData theme) {
    final p = viewModel.effectiveParams;
    final hexLen = (p.width + 3) ~/ 4;
    String hexVal(int v) =>
        v.toRadixString(16).toUpperCase().padLeft(hexLen, '0');
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
      fontSize: 13,
      color: theme.colorScheme.onSurface,
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paramRow('宽度 WIDTH', '${p.width}', labelStyle, valueStyle),
          const SizedBox(height: 4),
          _paramRow(
            '多项式 POLY（Hex）',
            '0x${hexVal(p.poly)}',
            labelStyle,
            valueStyle,
          ),
          const SizedBox(height: 4),
          _paramRow(
            '初始值 INIT（Hex）',
            '0x${hexVal(p.init)}',
            labelStyle,
            valueStyle,
          ),
          const SizedBox(height: 4),
          _paramRow(
            '结果异或值 XOROUT（Hex）',
            '0x${hexVal(p.xorout)}',
            labelStyle,
            valueStyle,
          ),
          const SizedBox(height: 4),
          _paramRow(
            '输入数据反转 REFIN',
            p.refin ? 'true' : 'false',
            labelStyle,
            valueStyle,
          ),
          const SizedBox(height: 4),
          _paramRow(
            '输出数据反转 REFOUT',
            p.refout ? 'true' : 'false',
            labelStyle,
            valueStyle,
          ),
        ],
      ),
    );
  }

  Widget _paramRow(
    String label,
    String value,
    TextStyle? labelStyle,
    TextStyle valueStyle,
  ) {
    return Row(
      children: [
        Expanded(flex: 3, child: Text(label, style: labelStyle)),
        Expanded(flex: 2, child: Text(value, style: valueStyle)),
      ],
    );
  }

  Widget _buildAboutButton(CrcViewModel viewModel, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => viewModel.toggleAboutPinned(),
      child: MouseRegion(
        onEnter: (_) => viewModel.enterAboutHover(),
        onExit: (_) => viewModel.exitAboutHover(),
        child: Tooltip(
          message: '查看 CRC 参数模型列表',
          child: Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildAboutPanel(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bodyStyle = TextStyle(
      fontSize: 12.5,
      height: 1.5,
      color: colorScheme.onSurface,
    );
    final headingStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.5,
      color: colorScheme.onSurface,
    );

    return MouseRegion(
      onEnter: (_) => viewModel.enterAboutHover(),
      onExit: (_) => viewModel.exitAboutHover(),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'CRC 参数模型列表',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => viewModel.dismissAbout(),
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CRC校验（循环冗余校验）小知识', style: headingStyle),
                      const SizedBox(height: 4),
                      Text(
                        'CRC即循环冗余校验码（Cyclic Redundancy Check）：是数据通信领域中最常用的一种查错校验码，其特征是信息字段和校验字段的长度可以任意选定。循环冗余检查（CRC）是一种数据传输检错功能，对数据进行多项式计算，并将得到的结果附在帧的后面，接收设备也执行类似的算法，以保证数据传输的正确性和完整性。',
                        style: bodyStyle,
                      ),
                      const SizedBox(height: 10),
                      Text('CRC算法参数模型解释：', style: headingStyle),
                      const SizedBox(height: 4),
                      Text('NAME：参数模型名称。', style: bodyStyle),
                      Text('WIDTH：宽度，即CRC比特数。', style: bodyStyle),
                      Text(
                        'POLY：生成项的简写，以16进制表示。例如：CRC-32即是0x04C11DB7，忽略了最高位的"1"，即完整的生成项是0x104C11DB7。',
                        style: bodyStyle,
                      ),
                      Text(
                        'INIT：这是算法开始时寄存器（crc）的初始化预置值，十六进制表示。',
                        style: bodyStyle,
                      ),
                      Text(
                        'REFIN：待测数据的每个字节是否按位反转，True或False。',
                        style: bodyStyle,
                      ),
                      Text(
                        'REFOUT：在计算后之后，异或输出之前，整个数据是否按位反转，True或False。',
                        style: bodyStyle,
                      ),
                      Text('XOROUT：计算结果与此参数异或后得到最终的CRC值。', style: bodyStyle),
                      const SizedBox(height: 14),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                          dataTextStyle: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                          columnSpacing: 12,
                          headingRowHeight: 32,
                          dataRowMinHeight: 26,
                          dataRowMaxHeight: 26,
                          columns: const [
                            DataColumn(label: Text('名称')),
                            DataColumn(label: Text('宽度'), numeric: true),
                            DataColumn(label: Text('多项式(Poly)')),
                            DataColumn(label: Text('初始值(Init)')),
                            DataColumn(label: Text('异或值(XorOut)')),
                            DataColumn(label: Text('输入反转')),
                            DataColumn(label: Text('输出反转')),
                          ],
                          rows: CrcPresets.all.map((preset) {
                            final p = preset.params;
                            final isSelected =
                                viewModel.selectedPreset == preset.name;
                            final hexLen = (p.width + 3) ~/ 4;
                            String hexVal(int v) => v
                                .toRadixString(16)
                                .toUpperCase()
                                .padLeft(hexLen, '0');
                            return DataRow(
                              selected: isSelected,
                              cells: [
                                DataCell(Text(preset.name)),
                                DataCell(Text('${p.width}')),
                                DataCell(Text('0x${hexVal(p.poly)}')),
                                DataCell(Text('0x${hexVal(p.init)}')),
                                DataCell(Text('0x${hexVal(p.xorout)}')),
                                DataCell(Text(p.refin ? '✓' : '✗')),
                                DataCell(Text(p.refout ? '✓' : '✗')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomParams(CrcViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: AppDropdownFormField<int>(
                key: ValueKey(viewModel.customParams.width),
                initialValue: viewModel.customParams.width,
                decoration: const InputDecoration(
                  labelText: 'WIDTH',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                isExpanded: true,
                items: List.generate(32, (i) => i + 1).map((w) {
                  return DropdownMenuItem(
                    value: w,
                    child: Text('$w', style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) viewModel.setCustomWidth(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'POLY',
                  hintText: '例如: 8005',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
                  fontSize: 13,
                ),
                onChanged: viewModel.setCustomPoly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'INIT',
                  hintText: '例如: FFFF',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
                  fontSize: 13,
                ),
                onChanged: viewModel.setCustomInit,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'XOROUT',
                  hintText: '例如: 0000',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
                  fontSize: 13,
                ),
                onChanged: viewModel.setCustomXorout,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                title: const Text('REFIN', style: TextStyle(fontSize: 13)),
                value: viewModel.customParams.refin,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: viewModel.setCustomRefin,
              ),
            ),
            Expanded(
              child: SwitchListTile(
                title: const Text('REFOUT', style: TextStyle(fontSize: 13)),
                value: viewModel.customParams.refout,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: viewModel.setCustomRefout,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, CrcViewModel viewModel) {
    final theme = Theme.of(context);
    final monoStyle = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
      fontSize: 14,
      color: theme.colorScheme.onSurface,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('计算结果', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            if (viewModel.result == null)
              Expanded(
                child: Center(
                  child: Text(
                    viewModel.currentBytes == null ? '请输入数据' : '无法计算（请检查输入）',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        'HEX:  ${viewModel.formatHex(viewModel.result!)}',
                        style: monoStyle,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        'Bin:  ${viewModel.formatBin(viewModel.result!)}',
                        style: monoStyle,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        'Dec:  ${viewModel.formatDec(viewModel.result!)}',
                        style: monoStyle,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '字节长度: ${viewModel.currentBytes?.length ?? 0} bytes',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(BuildContext context, CrcViewModel vm, int index) {
    final file = vm.files[index];
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: index < vm.files.length - 1
            ? Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: file.selected,
              onChanged: (_) => vm.toggleFileSelection(index),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.insert_drive_file_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${file.name} · ${CrcViewModel.formatFileSize(file.size)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: file.selected ? null : theme.disabledColor,
              ),
            ),
          ),
          SizedBox(
            height: 24,
            width: 24,
            child: IconButton(
              onPressed: () => vm.removeFile(index),
              icon: const Icon(Icons.close, size: 14),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tooltip: '移除',
            ),
          ),
        ],
      ),
    );
  }
}
