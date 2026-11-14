import 'package:flutter/material.dart';
import 'tools/bin_editor_tool.dart';
import 'tools/bin_link_tool.dart';
import 'tools/crc_tool.dart';
import 'tools/hex_to_bin_tool.dart';

class ToolboxToolDefinition {
  const ToolboxToolDefinition({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder builder;
}

class ToolboxToolRegistry {
  ToolboxToolRegistry._();

  static final tools = <ToolboxToolDefinition>[
    ToolboxToolDefinition(
      title: 'HEX/BIN互转',
      icon: Icons.transform_outlined,
      builder: (_) => const HexToBinTool(),
    ),
    ToolboxToolDefinition(
      title: 'BIN编辑',
      icon: Icons.edit_note_outlined,
      builder: (_) => const BinEditorTool(),
    ),
    ToolboxToolDefinition(
      title: 'BIN拼接',
      icon: Icons.call_merge_outlined,
      builder: (_) => const BinLinkTool(),
    ),
    ToolboxToolDefinition(
      title: 'CRC计算',
      icon: Icons.calculate_outlined,
      builder: (_) => const CrcTool(),
    ),
  ];
}
