import 'package:flutter/material.dart';

import '../../../models/terminal/session_type.dart';
import '../../../models/terminal/terminal_session.dart';
import '../../../viewmodels/terminal/terminal_viewmodel.dart';
import 'connect_dialog.dart';

class TerminalSessionList extends StatefulWidget {
  const TerminalSessionList({super.key, required this.viewModel});

  final TerminalViewModel viewModel;

  @override
  State<TerminalSessionList> createState() => _TerminalSessionListState();
}

class _TerminalSessionListState extends State<TerminalSessionList> {
  var _sshExpanded = true;
  var _serialExpanded = true;

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
              ExpansionTile(
                title: _sectionTitle(
                  'SSH 连接',
                  Icons.cloud_outlined,
                  widget.viewModel.sshSessions.length,
                  theme,
                ),
                initiallyExpanded: _sshExpanded,
                onExpansionChanged: (v) => _sshExpanded = v,
                dense: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding:
                    const EdgeInsets.only(left: 8, right: 8, bottom: 4),
                shape: const Border(),
                collapsedShape: const Border(),
                children: widget.viewModel.sshSessions.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: Text(
                            '暂无 SSH 连接',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ]
                    : widget.viewModel.sshSessions
                        .map(
                          (s) => _sessionItem(
                            s,
                            widget.viewModel,
                            theme,
                            colorScheme,
                          ),
                        )
                        .toList(),
              ),
              ExpansionTile(
                title: _sectionTitle(
                  '串口连接',
                  Icons.usb,
                  widget.viewModel.serialSessions.length,
                  theme,
                ),
                initiallyExpanded: _serialExpanded,
                onExpansionChanged: (v) => _serialExpanded = v,
                dense: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding:
                    const EdgeInsets.only(left: 8, right: 8, bottom: 4),
                shape: const Border(),
                collapsedShape: const Border(),
                children: widget.viewModel.serialSessions.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: Text(
                            '暂无串口连接',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ]
                    : widget.viewModel.serialSessions
                        .map(
                          (s) => _sessionItem(
                            s,
                            widget.viewModel,
                            theme,
                            colorScheme,
                          ),
                        )
                        .toList(),
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

  Widget _sectionTitle(
    String title,
    IconData icon,
    int count,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(title, style: theme.textTheme.labelSmall),
        const Spacer(),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
            ),
          ),
      ],
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
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: idx == vm.selectedSessionIndex
              ? colors.primaryContainer.withValues(alpha: 0.32)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            _statusDot(session.status, colors),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session.name,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  void _showConnectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ConnectDialog(viewModel: widget.viewModel),
    );
  }
}
