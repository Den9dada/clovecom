import 'package:flutter/material.dart';
import 'tools/bin_editor_tool.dart';
import 'tools/bin_link_tool.dart';
import 'tools/crc_tool.dart';
import 'tools/hex_to_bin_tool.dart';

/// 工具箱入口描述符：稳定 id 是入口的唯一身份，槽位由注册表按列表位置分配。
/// 工具 widget 只引用 id，不再硬编码 tab 索引；新增/插入工具无需顺延槽号。
class ToolboxToolDefinition {
  const ToolboxToolDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String id;
  final String title;
  final IconData icon;
  final WidgetBuilder builder;
}

class ToolboxToolRegistry {
  ToolboxToolRegistry._();

  // 入口 id 的唯一来源：工具 widget 与状态栏都引用这些常量。
  static const String hexToBinId = 'hexToBin';
  static const String binEditorId = 'binEditor';
  static const String binLinkId = 'binLink';
  static const String crcId = 'crc';

  static final tools = <ToolboxToolDefinition>[
    ToolboxToolDefinition(
      id: hexToBinId,
      title: 'HEX/BIN互转',
      icon: Icons.transform_outlined,
      builder: (_) => const HexToBinTool(),
    ),
    ToolboxToolDefinition(
      id: binEditorId,
      title: 'BIN编辑',
      icon: Icons.edit_note_outlined,
      builder: (_) => const BinEditorTool(),
    ),
    ToolboxToolDefinition(
      id: binLinkId,
      title: 'BIN拼接',
      icon: Icons.call_merge_outlined,
      builder: (_) => const BinLinkTool(),
    ),
    ToolboxToolDefinition(
      id: crcId,
      title: 'CRC计算',
      icon: Icons.calculate_outlined,
      builder: (_) => const CrcTool(),
    ),
  ];

  /// 注册表按列表位置分配槽位；未知 id 返回 -1。
  static int slotOf(String id) => tools.indexWhere((t) => t.id == id);

  /// 槽位反查入口 id（供 ToolboxView 把 tab 索引映射到稳定 id）。
  static String idAt(int slot) =>
      slot >= 0 && slot < tools.length ? tools[slot].id : '';
}