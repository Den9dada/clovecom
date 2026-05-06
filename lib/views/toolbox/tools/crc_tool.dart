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

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: const _CrcToolContent(),
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
                _buildAboutButton(viewModel, colorScheme),
              ],
            ),
            if (viewModel.isCustomMode) ...[
              const SizedBox(height: 10),
              _buildCustomParams(viewModel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAboutButton(CrcViewModel viewModel, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => viewModel.toggleAboutPinned(),
      child: MouseRegion(
        onEnter: (_) => viewModel.setAboutHovered(true),
        onExit: (_) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!viewModel.isAboutPinned) {
              viewModel.setAboutHovered(false);
            }
          });
        },
        child: Tooltip(
          message: '点击查看 CRC 参数模型列表',
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
