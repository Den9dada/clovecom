import 'package:flutter/material.dart';

import '../../../models/terminal/session_type.dart';
import '../../../viewmodels/terminal/terminal_viewmodel.dart';

class TerminalTabBar extends StatelessWidget {
  const TerminalTabBar({super.key, required this.viewModel});

  final TerminalViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: viewModel.sessions.length,
        itemBuilder: (context, index) {
          final session = viewModel.sessions[index];
          final isSelected = index == viewModel.selectedSessionIndex;

          return GestureDetector(
            onTap: () => viewModel.selectSession(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statusDot(session.status, colorScheme),
                  const SizedBox(width: 6),
                  Text(
                    session.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => viewModel.closeSession(index),
                    borderRadius: BorderRadius.circular(8),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
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
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
