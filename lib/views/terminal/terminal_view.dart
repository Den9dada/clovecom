import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/terminal/session_type.dart';
import '../../models/terminal/terminal_theme_scheme.dart';
import '../../models/terminal/highlight_rule.dart';
import '../../viewmodels/terminal/terminal_viewmodel.dart';
import 'widgets/terminal_session_list.dart';
import 'widgets/terminal_tab_bar.dart';
import 'widgets/terminal_pane.dart';
import 'widgets/connect_dialog.dart';
import 'widgets/highlight_editor_dialog.dart';

class TerminalView extends StatefulWidget {
  const TerminalView({super.key});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView>
    with AutomaticKeepAliveClientMixin {
  late final TerminalViewModel _viewModel = TerminalViewModel();

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
      child: Builder(builder: (context) => _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    final viewModel = context.watch<TerminalViewModel>();
    final colorScheme = Theme.of(context).colorScheme;
    final hasSessions = viewModel.sessions.isNotEmpty;

    return Row(
      children: [
        SizedBox(width: 200, child: TerminalSessionList(viewModel: viewModel)),
        VerticalDivider(width: 1, color: colorScheme.outlineVariant),
        Expanded(
          child: Column(
            children: [
              if (hasSessions) ...[
                TerminalTabBar(viewModel: viewModel),
                Divider(height: 1, color: colorScheme.outlineVariant),
              ],
              Expanded(
                child: hasSessions && viewModel.selectedSession != null
                    ? TerminalPane(
                        session: viewModel.selectedSession!,
                        theme: viewModel.currentThemeScheme.theme,
                        onReconnect: () => viewModel.reconnectSession(
                          viewModel.selectedSessionIndex,
                        ),
                      )
                    : _buildEmptyPane(context, viewModel, colorScheme),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              _statusBar(context, viewModel),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPane(
    BuildContext context,
    TerminalViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 48, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text('未打开会话', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '请点击左侧 新建连接 或下方按钮开始',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => _openSsh(context, viewModel),
                icon: const Icon(Icons.cloud, size: 16),
                label: const Text('SSH 连接'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _openSerial(context, viewModel),
                icon: const Icon(Icons.usb, size: 16),
                label: const Text('串口连接'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSsh(BuildContext context, TerminalViewModel viewModel) {
    showDialog(
      context: context,
      builder: (_) => ConnectDialog(viewModel: viewModel, initialMode: 0),
    );
  }

  void _openSerial(BuildContext context, TerminalViewModel viewModel) {
    showDialog(
      context: context,
      builder: (_) => ConnectDialog(viewModel: viewModel, initialMode: 1),
    );
  }

  Widget _statusBar(BuildContext context, TerminalViewModel viewModel) {
    final session = viewModel.selectedSession;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
      ),
      child: Row(
        children: [
          _dot(session?.status ?? SessionStatus.disconnected, colorScheme),
          const SizedBox(width: 6),
          Text(
            session?.statusLabel ?? 'Idle',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          if (session != null)
            Text(
              session.name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (session != null) const SizedBox(width: 8),
          _buildHighlightMenu(context, viewModel, theme),
          const SizedBox(width: 4),
          _buildThemeMenu(context, viewModel, theme),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildThemeMenu(
    BuildContext context,
    TerminalViewModel viewModel,
    ThemeData theme,
  ) {
    return PopupMenuButton<String>(
      offset: const Offset(0, -300),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 200),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.palette, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 3),
          Text(
            viewModel.currentThemeScheme.name,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.primary,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 14,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
      itemBuilder: (context) {
        return TerminalThemeScheme.presets.map((scheme) {
          final isSelected = scheme.name == viewModel.currentThemeScheme.name;
          return PopupMenuItem<String>(
            value: scheme.name,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 32,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: scheme.theme.background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.theme.foreground,
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  scheme.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check, size: 14, color: theme.colorScheme.primary),
              ],
            ),
          );
        }).toList();
      },
      onSelected: (name) {
        final scheme = TerminalThemeScheme.presets.firstWhere(
          (s) => s.name == name,
        );
        viewModel.setThemeScheme(scheme);
      },
    );
  }

  Widget _buildHighlightMenu(
    BuildContext context,
    TerminalViewModel viewModel,
    ThemeData theme,
  ) {
    return PopupMenuButton<String>(
      offset: const Offset(0, -300),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.highlight,
            size: 13,
            color:
                viewModel.activeHighlightRuleSet != null ||
                    viewModel.customRules.isNotEmpty
                ? theme.colorScheme.tertiary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          Text(
            viewModel.activeHighlightRuleSet?.name ?? '高亮规则',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color:
                  viewModel.activeHighlightRuleSet != null ||
                      viewModel.customRules.isNotEmpty
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 14,
            color:
                viewModel.activeHighlightRuleSet != null ||
                    viewModel.customRules.isNotEmpty
                ? theme.colorScheme.tertiary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        items.add(
          PopupMenuItem<String>(
            value: '__none__',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 32,
            child: Row(
              children: [
                Icon(
                  viewModel.activeHighlightRuleSet == null &&
                          viewModel.customRules.isEmpty
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '无高亮',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        );

        items.add(const PopupMenuDivider(height: 1));

        for (final preset in HighlightPresets.presets) {
          final isSelected =
              viewModel.activeHighlightRuleSet?.name == preset.name;
          items.add(
            PopupMenuItem<String>(
              value: '__preset__${preset.name}',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              height: 32,
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: isSelected
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          preset.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        Text(
                          preset.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        items.add(const PopupMenuDivider(height: 1));

        items.add(
          PopupMenuItem<String>(
            value: '__custom__',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 32,
            child: Row(
              children: [
                Icon(
                  Icons.edit,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '自定义规则...',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        );

        return items;
      },
      onSelected: (value) {
        if (value == '__none__') {
          viewModel.setActiveHighlightRuleSet(null);
        } else if (value.startsWith('__preset__')) {
          final name = value.substring('__preset__'.length);
          final preset = HighlightPresets.presets.firstWhere(
            (p) => p.name == name,
          );
          viewModel.setActiveHighlightRuleSet(preset);
        } else if (value == '__custom__') {
          showDialog(
            context: context,
            builder: (_) =>
                HighlightEditorDialog(customRules: viewModel.customRules),
          ).then((_) {
            viewModel.notifyListeners();
          });
        }
      },
    );
  }

  Widget _dot(SessionStatus status, ColorScheme colors) {
    final color = status == SessionStatus.connected
        ? colors.primary
        : status == SessionStatus.connecting
        ? Colors.orange
        : colors.outline;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
