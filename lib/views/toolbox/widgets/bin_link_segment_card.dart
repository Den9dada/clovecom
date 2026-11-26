import 'package:clovecom/widgets/app_dropdown.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/toolbox/bin_link_segment.dart';

class BinLinkSegmentCard extends StatefulWidget {
  const BinLinkSegmentCard({
    super.key,
    required this.segment,
    required this.index,
    required this.color,
    required this.hasOverlap,
    this.overlapName,
    required this.onToggleEnabled,
    required this.onRemove,
    required this.onEditAddress,
    this.onEditName,
    this.onAlignmentChanged,
  });

  final BinLinkSegment segment;
  final int index;
  final Color color;
  final bool hasOverlap;
  final String? overlapName;
  final VoidCallback onToggleEnabled;
  final VoidCallback onRemove;
  final ValueChanged<String> onEditAddress;
  final ValueChanged<String>? onEditName;
  final ValueChanged<int>? onAlignmentChanged;

  @override
  State<BinLinkSegmentCard> createState() => _BinLinkSegmentCardState();
}

class _BinLinkSegmentCardState extends State<BinLinkSegmentCard> {
  var _editingName = false;
  var _editingAddress = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _addrCtrl;
  final _nameFocus = FocusNode();
  final _addrFocus = FocusNode();

  static const _alignPresets = [
    (0, '无'),
    (1024, '1 KB'),
    (4096, '4 KB'),
    (65536, '64 KB'),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.segment.name);
    _addrCtrl = TextEditingController(
      text: '0x${widget.segment.address.toRadixString(16).toUpperCase()}',
    );
    _nameFocus.addListener(_onNameFocusLost);
    _addrFocus.addListener(_onAddrFocusLost);
  }

  @override
  void didUpdateWidget(BinLinkSegmentCard old) {
    super.didUpdateWidget(old);
    if (!_editingName && widget.segment.name != old.segment.name) {
      _nameCtrl.text = widget.segment.name;
    }
    if (!_editingAddress && widget.segment.address != old.segment.address) {
      _addrCtrl.text =
          '0x${widget.segment.address.toRadixString(16).toUpperCase()}';
    }
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onNameFocusLost);
    _addrFocus.removeListener(_onAddrFocusLost);
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _nameFocus.dispose();
    _addrFocus.dispose();
    super.dispose();
  }

  void _onNameFocusLost() {
    if (!_nameFocus.hasFocus && _editingName) {
      _commitName();
    }
  }

  void _onAddrFocusLost() {
    if (!_addrFocus.hasFocus && _editingAddress) {
      _commitAddress();
    }
  }

  void _commitName() {
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty && name != widget.segment.name) {
      widget.onEditName?.call(name);
    } else {
      _nameCtrl.text = widget.segment.name;
    }
    setState(() => _editingName = false);
  }

  void _commitAddress() {
    final text = _addrCtrl.text.trim();
    if (text.isNotEmpty) {
      widget.onEditAddress(text);
    }
    setState(() => _editingAddress = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final seg = widget.segment;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.hasOverlap ? cs.error : cs.outlineVariant,
          width: widget.hasOverlap ? 1.5 : 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: widget.onToggleEnabled,
              child: Tooltip(
                message: seg.enabled ? '点击禁用' : '点击启用',
                child: Container(
                  width: 16,
                  decoration: BoxDecoration(
                    color: seg.enabled ? widget.color : cs.onSurfaceVariant,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(7),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          seg.isManual
                              ? Icons.keyboard_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 16,
                          color: seg.enabled ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _editingName
                              ? SizedBox(
                                  height: 28,
                                  child: TextField(
                                    controller: _nameCtrl,
                                    focusNode: _nameFocus,
                                    autofocus: true,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (_) {
                                      _nameFocus.unfocus();
                                    },
                                  ),
                                )
                              : Tooltip(
                                  message: seg.name,
                                  child: GestureDetector(
                                    onTap: widget.onEditName != null
                                        ? () => setState(
                                            () => _editingName = true,
                                          )
                                        : null,
                                    child: Text(
                                      seg.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: seg.enabled
                                                ? null
                                                : cs.onSurfaceVariant,
                                            decoration:
                                                widget.onEditName != null
                                                ? TextDecoration.underline
                                                : null,
                                            decorationStyle:
                                                TextDecorationStyle.dotted,
                                          ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 20,
                          width: 20,
                          child: IconButton(
                            onPressed: widget.onRemove,
                            tooltip: '删除片段',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            icon: Icon(
                              Icons.close,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        _infoTag(context, '大小', seg.sizeFormatted),
                        _infoTag(context, 'CRC', seg.crcHex),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        _editingAddress
                            ? SizedBox(
                                width: 140,
                                height: 24,
                                child: TextField(
                                  controller: _addrCtrl,
                                  focusNode: _addrFocus,
                                  autofocus: true,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontFamily: 'Consolas'),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) {
                                    _addrFocus.unfocus();
                                  },
                                ),
                              )
                            : _infoTag(
                                context,
                                '地址',
                                '0x${seg.address.toRadixString(16).toUpperCase()}',
                                onTap: () =>
                                    setState(() => _editingAddress = true),
                              ),
                        _alignDropdown(context, cs),
                      ],
                    ),
                    if (widget.hasOverlap && widget.overlapName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.warning_amber, size: 12, color: cs.error),
                          const SizedBox(width: 4),
                          Text(
                            '与 ${widget.overlapName} 重叠',
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: cs.error),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTag(
    BuildContext context,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          children: [
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
                color: onTap != null ? cs.primary : null,
                decoration: onTap != null ? TextDecoration.underline : null,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alignDropdown(BuildContext context, ColorScheme cs) {
    final seg = widget.segment;
    final currentLabel = _alignPresets
        .firstWhere((p) => p.$1 == seg.alignment, orElse: () => (0, '自定义'))
        .$2;

    return AppPopupMenuButton<int>(
      initialValue: seg.alignment,
      onSelected: widget.onAlignmentChanged,
      tooltip: '对齐',
      child: Text.rich(
        TextSpan(
          text: '对齐: ',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          children: [
            TextSpan(
              text: currentLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.primary,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => _alignPresets.map((p) {
        return PopupMenuItem<int>(
          value: p.$1,
          height: 28,
          child: Text(p.$2, style: Theme.of(context).textTheme.labelSmall),
        );
      }).toList(),
    );
  }
}
