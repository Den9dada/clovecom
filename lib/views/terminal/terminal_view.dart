import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/terminal/session_type.dart';
import '../../viewmodels/terminal/terminal_viewmodel.dart';
import 'widgets/terminal_session_list.dart';
import 'widgets/terminal_tab_bar.dart';
import 'widgets/terminal_pane.dart';
import 'widgets/connect_dialog.dart';

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
      child: Builder(
        builder: (context) => _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final viewModel = context.watch<TerminalViewModel>();
    final colorScheme = Theme.of(context).colorScheme;
    final hasSessions = viewModel.sessions.isNotEmpty;

    return Row(
      children: [
        SizedBox(
          width: 200,
          child: TerminalSessionList(viewModel: viewModel),
        ),
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
                        onReconnect: () =>
                            viewModel.reconnectSession(viewModel.selectedSessionIndex),
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
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(6),
        ),
      ),
      child: Row(
        children: [
          _dot(session?.status ?? SessionStatus.disconnected, colorScheme),
          const SizedBox(width: 8),
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
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
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
