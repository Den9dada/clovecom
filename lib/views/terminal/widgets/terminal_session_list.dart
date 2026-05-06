import 'package:flutter/material.dart';

import '../../../models/terminal/terminal_session.dart';
import '../../../viewmodels/terminal/terminal_viewmodel.dart';
import 'connect_dialog.dart';

class TerminalSessionList extends StatelessWidget {
  const TerminalSessionList({super.key, required this.viewModel});

  final TerminalViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text('会话列表', style: theme.textTheme.titleSmall),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              _sectionHeader('SSH 连接', Icons.cloud_outlined, theme),
              ...viewModel.sshSessions.map(
                (s) => _sessionItem(s, viewModel, theme, colorScheme),
              ),
              const SizedBox(height: 4),
              _sectionHeader('串口连接', Icons.usb, theme),
              ...viewModel.serialSessions.map(
                (s) => _sessionItem(s, viewModel, theme, colorScheme),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton.icon(
            onPressed: () => _showConnectDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新建连接'),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(title, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _sessionItem(
    TerminalSession session,
    TerminalViewModel vm,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final idx = vm.sessions.indexOf(session);
    return InkWell(
      onTap: () => vm.selectSession(idx),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: idx == vm.selectedSessionIndex
              ? colors.primaryContainer.withValues(alpha: 0.32)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(session.name, style: theme.textTheme.bodySmall),
      ),
    );
  }

  void _showConnectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ConnectDialog(viewModel: viewModel),
    );
  }
}
