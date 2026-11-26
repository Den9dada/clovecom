import 'package:clovecom/services/status_bar_service.dart';
import 'package:clovecom/views/toolbox/toolbox_tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('入口注册表分配槽位', () {
    test('四个入口 id 映射到互异槽位 0-3', () {
      final ids = [
        ToolboxToolRegistry.hexToBinId,
        ToolboxToolRegistry.binEditorId,
        ToolboxToolRegistry.binLinkId,
        ToolboxToolRegistry.crcId,
      ];
      final slots = ids.map(ToolboxToolRegistry.slotOf).toList();
      expect(slots, [0, 1, 2, 3]);
      expect(slots.toSet().length, 4);
    });

    test('idAt 与 slotOf 往返一致', () {
      for (final tool in ToolboxToolRegistry.tools) {
        final slot = ToolboxToolRegistry.slotOf(tool.id);
        expect(ToolboxToolRegistry.idAt(slot), tool.id);
      }
    });

    test('未知 id 返回 -1，越界槽位返回空 id', () {
      expect(ToolboxToolRegistry.slotOf('nope'), -1);
      expect(ToolboxToolRegistry.idAt(-1), '');
      expect(ToolboxToolRegistry.idAt(99), '');
    });

    test('每个入口描述符 id 非空且唯一', () {
      final ids = ToolboxToolRegistry.tools.map((t) => t.id).toList();
      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(ids.toSet().length, ids.length);
    });
  });

  group('状态栏按入口 id 键控', () {
    test('活跃入口映射到工具箱主 tab，非活跃不覆盖，切换取缓存', () {
      // 槽位 1 = 工具箱主 tab（ADR-0005 导航重排后）
      final bar = StatusBarService();
      const a = StatusBarInfo(text: 'HEX 状态');
      const b = StatusBarInfo(text: '拼接状态');
      const c = StatusBarInfo(text: '拼接状态2');

      bar.setActiveToolboxTool(ToolboxToolRegistry.hexToBinId);
      bar.updateToolboxStatus(ToolboxToolRegistry.hexToBinId, a);
      expect(bar.statusFor(1).text, 'HEX 状态');

      // 非活跃入口上报不覆盖当前显示。
      bar.updateToolboxStatus(ToolboxToolRegistry.binLinkId, b);
      expect(bar.statusFor(1).text, 'HEX 状态');

      // 切换到拼接入口，取其已缓存状态。
      bar.setActiveToolboxTool(ToolboxToolRegistry.binLinkId);
      expect(bar.statusFor(1).text, '拼接状态');

      // 活跃入口更新即时反映。
      bar.updateToolboxStatus(ToolboxToolRegistry.binLinkId, c);
      expect(bar.statusFor(1).text, '拼接状态2');
    });
  });
}