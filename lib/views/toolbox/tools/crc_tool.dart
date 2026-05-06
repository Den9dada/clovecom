import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/toolbox/crc_params.dart';
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
  final _aboutKey = GlobalKey();
  OverlayEntry? _aboutEntry;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onAboutStateChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onAboutStateChanged);
    _removeAboutOverlay();
    _viewModel.dispose();
    super.dispose();
  }

  void _onAboutStateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_viewModel.showAboutPopup) {
        _showAboutOverlay();
      } else {
        _removeAboutOverlay();
      }
    });
  }

  void _showAboutOverlay() {
    _removeAboutOverlay();
    final renderBox =
        _aboutKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final colorScheme = Theme.of(context).colorScheme;

    _aboutEntry = OverlayEntry(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _viewModel.dismissAbout(),
        child: Stack(
          children: [
            Positioned(
              left: (offset.dx + size.width / 2 - 320).clamp(0, 700),
              top: offset.dy + size.height + 6,
              child: MouseRegion(
                onEnter: (_) => _viewModel.setAboutHovered(true),
                onExit: (_) {
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (!_viewModel.isAboutPinned) {
                      _viewModel.setAboutHovered(false);
                    }
                  });
                },
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(12),
                    shadowColor: Colors.black26,
                    child: Container(
                      width: 640,
                      constraints: const BoxConstraints(maxHeight: 420),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: SingleChildScrollView(
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
                                _viewModel.selectedPreset == preset.name;
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
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_aboutEntry!);
  }

  void _removeAboutOverlay() {
    _aboutEntry?.remove();
    _aboutEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: _CrcToolContent(aboutKey: _aboutKey),
    );
  }
}

class _CrcToolContent extends StatelessWidget {
  const _CrcToolContent({required this.aboutKey});

  final GlobalKey aboutKey;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CrcViewModel>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final controls = _buildControls(context, viewModel);

        Widget rightPane;
        if (viewModel.inputMode == DataInputMode.file &&
            viewModel.fileBytes != null) {
          rightPane = Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '文件预览: ${viewModel.fileName}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Expanded(
                flex: 6,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: HexAsciiViewer(bytes: viewModel.fileBytes!),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 4,
                child: _buildResultCard(context, viewModel),
              ),
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
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
          children: [
            FileDropZone(
              title: '导入文件',
              subtitle: '拖入或点击选择任意文件，计算 CRC',
              allowedExtensions: const [],
              allowMultiple: false,
              onFilesSelected: (paths) async {
                await context.read<CrcViewModel>().importFile(paths);
              },
            ),
            if (viewModel.fileName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${viewModel.fileName} · ${CrcViewModel.formatFileSize(viewModel.fileSize)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                  child: DropdownButtonFormField<String>(
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
                      viewModel.selectPreset(
                        value == '自定义' ? null : value,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),
                _buildAboutButton(viewModel, colorScheme, aboutKey),
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
      fontFamily: 'monospace',
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
          _paramRow('多项式 POLY（Hex）', '0x${hexVal(p.poly)}', labelStyle, valueStyle),
          const SizedBox(height: 4),
          _paramRow('初始值 INIT（Hex）', '0x${hexVal(p.init)}', labelStyle, valueStyle),
          const SizedBox(height: 4),
          _paramRow('结果异或值 XOROUT（Hex）', '0x${hexVal(p.xorout)}', labelStyle, valueStyle),
          const SizedBox(height: 4),
          _paramRow('输入数据反转 REFIN', p.refin ? 'true' : 'false', labelStyle, valueStyle),
          const SizedBox(height: 4),
          _paramRow('输出数据反转 REFOUT', p.refout ? 'true' : 'false', labelStyle, valueStyle),
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
        Expanded(
          flex: 3,
          child: Text(label, style: labelStyle),
        ),
        Expanded(
          flex: 2,
          child: Text(value, style: valueStyle),
        ),
      ],
    );
  }

  Widget _buildAboutButton(CrcViewModel viewModel, ColorScheme colorScheme, GlobalKey aboutKey) {
    return GestureDetector(
      onTap: () => viewModel.toggleAboutPinned(),
      child: MouseRegion(
        key: aboutKey,
        onEnter: (_) => viewModel.setAboutHovered(true),
        onExit: (_) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!viewModel.isAboutPinned) {
              viewModel.setAboutHovered(false);
            }
          });
        },
        child: Tooltip(
          message: '查看 CRC 参数模型列表',
          child: Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
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
              child: DropdownButtonFormField<int>(
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
      fontFamily: 'monospace',
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
                    viewModel.currentBytes == null
                        ? '请输入数据'
                        : '无法计算（请检查输入）',
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
}
