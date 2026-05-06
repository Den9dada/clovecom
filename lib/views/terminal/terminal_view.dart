import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/terminal/session_type.dart';
import '../../viewmodels/terminal/terminal_viewmodel.dart';
import 'widgets/terminal_session_list.dart';
import 'widgets/terminal_tab_bar.dart';
import 'widgets/terminal_pane.dart';

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

    if (viewModel.sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 48, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '终端模块',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => viewModel.createLocalTerminal(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('打开本地终端'),
            ),
          ],
        ),
      );
    }

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
              TerminalTabBar(viewModel: viewModel),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Expanded(
                child: viewModel.selectedSession != null
                    ? TerminalPane(session: viewModel.selectedSession!)
                    : const SizedBox.shrink(),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              _buildStatusBar(context, viewModel),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    TerminalViewModel viewModel,
  ) {
    final session = viewModel.selectedSession;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          _statusDot(
            session?.status ?? SessionStatus.disconnected,
            colorScheme,
          ),
          const SizedBox(width: 6),
          Text(
            session?.statusLabel ?? 'No session',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          if (session != null)
            Text(
              session.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusDot(SessionStatus status, ColorScheme colors) {
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
