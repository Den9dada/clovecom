import 'package:clovecom/protocol_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/protocol_messages.dart';

void main() {
  test('复制及切换保留独立草稿，类型冲突阻止整体保存但允许单类型测试', () {
    final draft = ProtocolDraft(messageDefinition());
    draft.addMessage(copySelected: true);
    expect(draft.messageCount, 2);
    draft.renameMessage('复制定位');
    expect(() => draft.renameMessage('默认消息'), throwsFormatException);
    expect(draft.selectedMessageName, '复制定位');
    draft.updateField(3, {'sampleValue': '12'});
    expect(draft.validate(), isNotEmpty);
    expect(draft.validateSelected(), isEmpty);
    expect(
      draft.testHex(draft.generateSampleHex(), selectedOnly: true).succeeded,
      isTrue,
    );
    draft.selectMessage(0);
    expect(draft.field(3)['sampleValue'], '');
    draft.selectMessage(1);
    expect(draft.field(3)['sampleValue'], '12');
    draft.updateField(1, {
      'fixed': [4],
    });
    expect(draft.validate(), isEmpty);
    expect(draft.build().messageTypes[1].fields[3].sampleValue, '12');
    draft.addMessage(copySelected: true);
    draft.addMessage(copySelected: true);
    draft.updateField(1, {
      'fixed': [5],
    });
    draft.selectMessage(2);
    draft.updateField(1, {
      'fixed': [6],
    });
    final messages = draft.build().messageTypes;
    expect(messages.map((m) => m.id).toSet().length, messages.length);
  });

  test('无效的其他消息不阻止当前消息测试，空协议禁止保存且可以重新新增', () {
    final draft = ProtocolDraft(mixedProtocol());
    draft.selectMessage(1);
    draft.updateField(2, {'size': '无效'});
    draft.selectMessage(0);
    expect(draft.validate().single, contains('心跳'));
    expect(
      draft.testHex('AA 55 01 07 08 09', selectedOnly: true).succeeded,
      isTrue,
    );
    expect(draft.testHex('AA 55 01 07 08 09').succeeded, isFalse);
    while (draft.messageCount > 0) {
      draft.removeMessage();
    }
    expect(draft.validate(), isNotEmpty);
    draft.addMessage();
    expect(draft.messageCount, 1);
    expect(draft.fieldCount, 0);
  });

  test('任意消息修改、Hex 或测试范围修改后预览失效，丢弃恢复整个集合', () {
    final original = mixedProtocol();
    final draft = ProtocolDraft(original);
    draft.testHex('AA 55 01 07 08 09 AA 55 02 2A');
    expect(draft.preview!.frames.length, 2);
    draft.testSelectedOnly = true;
    expect(draft.preview, isNull);
    draft.testHex('AA 55 01 07 08 09', selectedOnly: true);
    draft.inputHex = 'AA';
    expect(draft.preview, isNull);
    draft.selectMessage(1);
    draft.renameMessage('改名');
    draft.set('name', '协议改名');
    draft.discard();
    expect(draft.build().toJson(), original.toJson());
    expect(draft.selectedMessageIndex, 0);
    expect(draft.isDirty, isFalse);
  });

  test('保存期间继续修改其他消息保留草稿，丢弃回到该次保存的完整快照', () {
    final draft = ProtocolDraft(mixedProtocol());
    draft.selectMessage(1);
    draft.renameMessage('心跳新名');
    final saved = draft.build();
    final revision = draft.revision;
    draft.selectMessage(2);
    draft.renameMessage('观测新名');
    draft.acceptSaved(saved, savedRevision: revision);
    expect(draft.messageName(2), '观测新名');
    expect(draft.isDirty, isTrue);
    draft.discard();
    expect(draft.messageName(1), '心跳新名');
    expect(draft.messageName(2), '观测');
  });
}
