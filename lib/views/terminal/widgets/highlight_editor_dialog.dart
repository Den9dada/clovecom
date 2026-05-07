import 'package:flutter/material.dart';

import '../../../models/terminal/highlight_rule.dart';

class HighlightEditorDialog extends StatefulWidget {
  final List<HighlightRule> customRules;

  const HighlightEditorDialog({super.key, required this.customRules});

  @override
  State<HighlightEditorDialog> createState() => _HighlightEditorDialogState();
}

class _HighlightEditorDialogState extends State<HighlightEditorDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.highlight, size: 20),
          const SizedBox(width: 8),
          Text('自定义高亮规则', style: theme.textTheme.titleSmall),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '添加正则表达式规则来高亮终端输出中的特定模式',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.customRules.isEmpty)
              _buildEmptyHint(theme, colorScheme)
            else
              ...widget.customRules.asMap().entries.map(
                (e) => _buildRuleItem(e.key, e.value, theme, colorScheme),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showAddRuleDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加规则'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _buildEmptyHint(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text('暂无自定义规则，点击下方"添加规则"开始', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildRuleItem(
    int index,
    HighlightRule rule,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: rule.enabled ? rule.color : colorScheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: rule.enabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rule.pattern,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                rule.enabled ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              tooltip: rule.enabled ? '禁用' : '启用',
              onPressed: () => _toggleRule(index),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: '编辑',
              onPressed: () => _showEditRuleDialog(context, index, rule),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: colorScheme.error,
              ),
              tooltip: '删除',
              onPressed: () => _deleteRule(index),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleRule(int index) {
    final viewModel = context
        .findAncestorStateOfType<_HighlightEditorDialogState>();
    if (viewModel == null) return;
    viewModel.widget.customRules[index].enabled =
        !viewModel.widget.customRules[index].enabled;
    viewModel.setState(() {});
  }

  void _deleteRule(int index) {
    final viewModel = context
        .findAncestorStateOfType<_HighlightEditorDialogState>();
    if (viewModel == null) return;
    viewModel.widget.customRules.removeAt(index);
    viewModel.setState(() {});
  }

  void _showAddRuleDialog(BuildContext context) {
    _showRuleForm(context, null, null);
  }

  void _showEditRuleDialog(
    BuildContext context,
    int index,
    HighlightRule rule,
  ) {
    _showRuleForm(context, index, rule);
  }

  void _showRuleForm(
    BuildContext context,
    int? index,
    HighlightRule? existing,
  ) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final patternCtrl = TextEditingController(text: existing?.pattern ?? '');
    var selectedColor = existing?.color ?? Colors.red;
    var selectedTarget = existing?.target ?? HighlightTarget.foreground;

    final colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.yellow,
      Colors.orange,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
      Colors.lime,
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(existing != null ? '编辑规则' : '添加规则'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '规则名称',
                        hintText: '例如: IPv4地址',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: patternCtrl,
                      decoration: const InputDecoration(
                        labelText: '正则表达式',
                        hintText: r'例如: \b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('颜色', style: Theme.of(ctx).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: colors.map((c) {
                        final isSelected = c.value == selectedColor.value;
                        return GestureDetector(
                          onTap: () => setState(() => selectedColor = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2.5)
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: c.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('目标', style: Theme.of(ctx).textTheme.bodySmall),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('前景'),
                          selected:
                              selectedTarget == HighlightTarget.foreground,
                          onSelected: (_) => setState(
                            () => selectedTarget = HighlightTarget.foreground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('背景'),
                          selected:
                              selectedTarget == HighlightTarget.background,
                          onSelected: (_) => setState(
                            () => selectedTarget = HighlightTarget.background,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final pattern = patternCtrl.text.trim();
                    if (name.isEmpty || pattern.isEmpty) return;

                    try {
                      RegExp(pattern);
                    } catch (_) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('正则表达式格式无效')),
                      );
                      return;
                    }

                    final rule = HighlightRule(
                      name: name,
                      pattern: pattern,
                      color: selectedColor,
                      target: selectedTarget,
                      enabled: existing?.enabled ?? true,
                    );

                    final parentState = context
                        .findAncestorStateOfType<_HighlightEditorDialogState>();
                    if (parentState == null) return;

                    if (existing != null && index != null) {
                      parentState.widget.customRules[index] = rule;
                    } else {
                      parentState.widget.customRules.add(rule);
                    }
                    parentState.setState(() {});
                    Navigator.of(ctx).pop();
                  },
                  child: Text(existing != null ? '保存' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
