import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import 'package:flutter/material.dart';

class FileDropZone extends StatefulWidget {
  const FileDropZone({
    super.key,
    required this.title,
    required this.subtitle,
    required this.allowedExtensions,
    required this.allowMultiple,
    required this.onFilesSelected,
  });

  final String title;
  final String subtitle;
  final List<String> allowedExtensions;
  final bool allowMultiple;
  final Future<void> Function(List<String> paths) onFilesSelected;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = _dragging ? colorScheme.primary : colorScheme.outline;

    return DropTarget(
      onDragDone: (details) async {
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList();
        await _handlePaths(paths);
      },
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dragging
              ? colorScheme.primaryContainer.withValues(alpha: 0.25)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: _dragging ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.upload_file_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('选择文件'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePickerCompat.pickFiles(
      allowMultiple: widget.allowMultiple,
      type: widget.allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: widget.allowedExtensions.isEmpty
          ? null
          : widget.allowedExtensions,
    );
    if (result == null) {
      return;
    }

    final paths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    await _handlePaths(paths);
  }

  Future<void> _handlePaths(List<String> paths) async {
    if (mounted) {
      setState(() => _dragging = false);
    }
    final accepted = paths.where(_isAllowed).toList();
    if (accepted.length != paths.length && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('包含不支持的文件类型，已忽略')));
    }
    if (accepted.isEmpty) {
      return;
    }
    await widget.onFilesSelected(
      widget.allowMultiple ? accepted : <String>[accepted.first],
    );
  }

  bool _isAllowed(String path) {
    if (widget.allowedExtensions.isEmpty) {
      return true;
    }
    final lower = path.toLowerCase();
    return widget.allowedExtensions.any((extension) {
      final normalized = extension.toLowerCase().replaceFirst('.', '');
      return lower.endsWith('.$normalized');
    });
  }
}
