import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/status_bar_service.dart';
import '../toolbox_tool_registry.dart';
import '../../../ui/widgets/ds_toast.dart';
import '../../../ui/widgets/ds_widgets.dart';
import '../../../viewmodels/toolbox/bin_link_viewmodel.dart';
import '../widgets/bin_link_minimap.dart';
import '../widgets/bin_link_segment_layout.dart';
import '../widgets/bin_link_segment_list.dart';
import '../widgets/bin_link_tool_bar.dart';
import '../widgets/hex_ascii_viewer.dart';

class BinLinkTool extends StatefulWidget {
  const BinLinkTool({super.key});

  @override
  State<BinLinkTool> createState() => _BinLinkToolState();
}

class _BinLinkToolState extends State<BinLinkTool>
    with AutomaticKeepAliveClientMixin {
  late final BinLinkViewModel _viewModel = BinLinkViewModel();
  var _dragging = false;

  @override
  bool get wantKeepAlive => true;

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
    StatusBarService().updateToolboxStatus(
      ToolboxToolRegistry.binLinkId,
      _buildStatus(),
    );
  }

  bool get _isCurrentTab {
    final controller = DefaultTabController.of(context);
    return controller.index ==
        ToolboxToolRegistry.slotOf(ToolboxToolRegistry.binLinkId);
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
          final paths = details.files
              .map((f) => f.path)
              .where((p) => p.isNotEmpty && p.toLowerCase().endsWith('.bin'))
              .toList();
          if (paths.isNotEmpty) {
            await _viewModel.importPaths(paths);
            if (mounted) _showError();
          }
          if (mounted) setState(() => _dragging = false);
        },
        child: _BinLinkToolContent(
          dragging: _dragging,
          onCustomFill: _showCustomFillDialog,
          onImportBin: _importBin,
        ),
      ),
    );
  }

  void _showCustomFillDialog() {
    final ctrl = TextEditingController(text: _viewModel.fillByteHex);
    showDialog(
      context: context,
      builder: (ctx) => DsDialog(
        title: const Text('自定义填充值'),
        content: DsInput(
          controller: ctrl,
          autofocus: true,
          expand: true,
          placeholder: '输入单字节HEX值，如 FF',
        ),
        actions: [
          DsButton(label: '取消', onPressed: () => Navigator.pop(ctx)),
          DsButton(
            label: '确认',
            variant: DsButtonVariant.brand,
            onPressed: () {
              _viewModel.setFillByte(ctrl.text);
              Navigator.pop(ctx);
              _showError();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importBin() async {
    final result = await FilePickerCompat.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['bin'],
    );
    if (result == null) return;
    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    await _viewModel.importPaths(paths);
    if (mounted) _showError();
  }

  StatusBarInfo _buildStatus() {
    if (_viewModel.lastError != null && _viewModel.lastError!.isNotEmpty) {
      return StatusBarInfo(
        text: _viewModel.lastError!,
        icon: Icons.error_outline,
        color: Colors.red,
      );
    }
    if (_viewModel.hasConflicts) {
      return StatusBarInfo(
        text:
            '${_viewModel.segments.length} 个段 | ${_viewModel.totalUsedFormatted} | 检测到重叠',
        icon: Icons.warning_amber,
        color: Colors.orange,
      );
    }
    if (_viewModel.segments.isNotEmpty) {
      var text =
          '${_viewModel.segments.length} 个段 | ${_viewModel.totalUsedFormatted}';
      final crc = _viewModel.outputCrc32Hex;
      if (_viewModel.outputCrc32 != null) text += ' | CRC32: $crc';
      return StatusBarInfo(text: text, icon: Icons.call_merge_outlined);
    }
    return const StatusBarInfo(text: '就绪 — 拖入或打开 BIN 文件');
  }

  void _showError() {
    final error = _viewModel.lastError;
    if (error == null || error.isEmpty) return;
    if (!mounted) return;
    showDsToast(error, kind: DsToastKind.error);
  }
}

class _BinLinkToolContent extends StatefulWidget {
  const _BinLinkToolContent({
    required this.dragging,
    required this.onCustomFill,
    required this.onImportBin,
  });

  final bool dragging;
  final VoidCallback onCustomFill;
  final Future<void> Function() onImportBin;

  @override
  State<_BinLinkToolContent> createState() => _BinLinkToolContentState();
}

class _BinLinkToolContentState extends State<_BinLinkToolContent> {
  double _scrollRatio = 0;
  double _viewportRatio = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        if (compact) {
          return _buildCompact(context);
        }
        return _buildWide(context);
      },
    );
  }

  Widget _buildWide(BuildContext context) {
    final viewModel = context.watch<BinLinkViewModel>();
    final previewEnd = viewModel.previewEndAddress;

    return Stack(
      children: [
        Column(
          children: [
            BinLinkToolBar(
              fillByte: viewModel.fillByte,
              canExport: viewModel.canExport,
              onImportBin: widget.onImportBin,
              onAddHexSegment: () => _showAddHexDialog(context),
              onAutoArrange: () {
                context.read<BinLinkViewModel>().autoArrange();
                _showError(context);
              },
              onCheckConflicts: () {
                final vm = context.read<BinLinkViewModel>();
                final msg = vm.checkConflicts();
                if (context.mounted) {
                  showDsToast(
                    msg,
                    kind: vm.hasConflicts
                        ? DsToastKind.warning
                        : DsToastKind.success,
                  );
                }
              },
              onExport: () async {
                await context.read<BinLinkViewModel>().exportLinked();
                if (context.mounted) _showError(context);
              },
              onFillByteChanged: (value) {
                if (value == -1) {
                  widget.onCustomFill();
                } else {
                  context.read<BinLinkViewModel>().setFillByteValue(value);
                }
              },
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 340, child: BinLinkSegmentList()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          flex: 1,
                          child: BinLinkSegmentLayout(
                            segments: viewModel.segments,
                            previewBaseAddress: viewModel.previewBaseAddress,
                            previewEndAddress: previewEnd,
                            overlappingPairs: viewModel.overlappingPairs,
                            layoutRevision: viewModel.layoutRevision,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          flex: 4,
                          child: Row(
                            children: [
                              Expanded(
                                child: HexAsciiViewer(
                                  bytes: viewModel.previewBytes,
                                  baseAddress: viewModel.previewBaseAddress,
                                  onScrollChanged: (offset, max) {
                                    setState(() {
                                      // 计算滚动比例：当前可视区域顶部在整个内容中的位置
                                      final totalContent =
                                          max + _viewerHeightEstimate(context);
                                      _scrollRatio = totalContent > 0
                                          ? (offset / totalContent).clamp(
                                              0.0,
                                              1.0,
                                            )
                                          : 0.0;
                                      // 可视区域占比
                                      _viewportRatio = totalContent > 0
                                          ? (_viewerHeightEstimate(context) /
                                                    totalContent)
                                                .clamp(0.0, 1.0)
                                          : 1.0;
                                    });
                                  },
                                ),
                              ),
                              BinLinkMinimap(
                                segments: viewModel.segments,
                                previewBaseAddress:
                                    viewModel.previewBaseAddress,
                                previewEndAddress: previewEnd,
                                layoutRevision: viewModel.layoutRevision,
                                scrollRatio: _scrollRatio,
                                viewportRatio: _viewportRatio,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.dragging)
          Positioned.fill(
            child: Container(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.15),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '拖放BIN文件到此处导入',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    final viewModel = context.watch<BinLinkViewModel>();
    final previewEnd = viewModel.previewEndAddress;

    return Stack(
      children: [
        Column(
          children: [
            BinLinkToolBar(
              fillByte: viewModel.fillByte,
              canExport: viewModel.canExport,
              onImportBin: widget.onImportBin,
              onAddHexSegment: () => _showAddHexDialog(context),
              onAutoArrange: () {
                context.read<BinLinkViewModel>().autoArrange();
                _showError(context);
              },
              onCheckConflicts: () {
                final vm = context.read<BinLinkViewModel>();
                final msg = vm.checkConflicts();
                if (context.mounted) {
                  showDsToast(
                    msg,
                    kind: vm.hasConflicts
                        ? DsToastKind.warning
                        : DsToastKind.success,
                  );
                }
              },
              onExport: () async {
                await context.read<BinLinkViewModel>().exportLinked();
                if (context.mounted) _showError(context);
              },
              onFillByteChanged: (value) {
                if (value == -1) {
                  widget.onCustomFill();
                } else {
                  context.read<BinLinkViewModel>().setFillByteValue(value);
                }
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const BinLinkSegmentList(),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: BinLinkSegmentLayout(
                        segments: viewModel.segments,
                        previewBaseAddress: viewModel.previewBaseAddress,
                        previewEndAddress: previewEnd,
                        overlappingPairs: viewModel.overlappingPairs,
                        layoutRevision: viewModel.layoutRevision,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 300,
                      child: HexAsciiViewer(
                        bytes: viewModel.previewBytes,
                        baseAddress: viewModel.previewBaseAddress,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (widget.dragging)
          Positioned.fill(
            child: Container(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.15),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '拖放BIN文件到此处导入',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showAddHexDialog(BuildContext context) {
    final addressCtrl = TextEditingController();
    final hexCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => DsDialog(
        title: const Text('新增HEX片段'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsInput(
              controller: addressCtrl,
              autofocus: true,
              expand: true,
              label: '片段地址',
              placeholder: '支持十六进制(0x...)或十进制',
            ),
            const SizedBox(height: 12),
            DsInput(
              controller: hexCtrl,
              maxLines: 4,
              expand: true,
              label: 'HEX数据',
              placeholder: '输入十六进制字节，如: 48 65 6C 6C 6F',
            ),
          ],
        ),
        actions: [
          DsButton(label: '取消', onPressed: () => Navigator.pop(ctx)),
          DsButton(
            label: '添加',
            variant: DsButtonVariant.brand,
            onPressed: () {
              context.read<BinLinkViewModel>().addManualHex(
                addressText: addressCtrl.text,
                hexText: hexCtrl.text,
              );
              Navigator.pop(ctx);
              _showError(context);
            },
          ),
        ],
      ),
    );
  }

  double _viewerHeightEstimate(BuildContext context) {
    // HEX 查看器的实际可视高度约为可用空间的一部分
    final size = MediaQuery.of(context).size;
    // 宽屏下约占总高度的 flex:4/(1+4) = 80%, 减去工具栏/状态栏/标题等约200px
    return (size.height - 200) * 0.55;
  }

  void _showError(BuildContext context) {
    final error = context.read<BinLinkViewModel>().lastError;
    if (error == null || error.isEmpty) return;
    showDsToast(error, kind: DsToastKind.error);
  }
}
