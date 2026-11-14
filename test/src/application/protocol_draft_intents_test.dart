import 'package:clovecom/protocol_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProtocolDraft draft;
  late List<Map<String, dynamic>> notifications;
  setUp(() {
    notifications = [];
    draft = ProtocolDraft.create(
      id: 'draft',
      name: '测试协议',
      onChanged: () => notifications.add(draft.values),
    );
  });

  test('添加长度字段只发布协调后的状态，失败不修改草稿', () {
    draft.set('fixedLength', 12);
    notifications.clear();
    final revision = draft.revision;
    draft.addConfiguredField(
      ProtocolField(name: 'length', size: 1, role: FieldRole.length),
    );
    expect(draft.revision, revision + 1);
    expect(notifications, hasLength(1));
    expect(notifications.single['fixedLength'], isNull);
    expect(notifications.single['lengthField'], 'length');
    final value = draft.values;
    expect(
      () => draft.addConfiguredField(ProtocolField(name: 'length', size: 2)),
      throwsFormatException,
    );
    expect(draft.values, value);
    expect(notifications, hasLength(1));
  });

  test('帧长模式只通知一次，缺少长度字段仍是可修改草稿', () {
    draft.setFrameMode(ProtocolFrameMode.length);
    expect(notifications, hasLength(1));
    expect(notifications.single['fixedLength'], isNull);
    expect(notifications.single['lengthField'], '');
    draft.addConfiguredField(
      ProtocolField(name: 'length', size: 1, role: FieldRole.length),
    );
    draft.setFrameMode(ProtocolFrameMode.length);
    notifications.clear();
    draft.setFrameMode(ProtocolFrameMode.fixed);
    expect(notifications, hasLength(1));
    expect(notifications.single['fixedLength'], 1);
    expect(notifications.single['lengthField'], isNull);
  });

  test('重排后按字段身份替换映射，观察者看不到解除后的中间状态', () {
    draft.addField(ProtocolField(name: 'a', size: 1), semantic: 'x');
    draft.addField(ProtocolField(name: 'b', size: 1), semantic: 'y');
    final identity = draft.fieldIdentity(0);
    draft.moveField(0, 1);
    notifications.clear();
    draft.assignFieldSemantic(identity, 'y');
    expect(notifications, hasLength(1));
    expect(notifications.single['mapping'], {'y': 'a'});
    draft.removeField(1);
    final revision = draft.revision;
    expect(() => draft.assignFieldSemantic(identity, 'x'), throwsStateError);
    expect(draft.revision, revision);
  });

  test('复合编辑使已有预览失效', () {
    draft.addField(ProtocolField(name: 'value', size: 1));
    draft.setFrameMode(ProtocolFrameMode.fixed);
    draft.testHex('01');
    expect(draft.preview, isNotNull);
    draft.assignFieldSemantic(draft.fieldIdentity(0), 'tagId');
    expect(draft.preview, isNull);
  });
}
