import 'package:clovecom/ui/widgets/ds_toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 锁定 clovertls 对齐的提示弹窗不变量：归一化异常前缀、同文去重、空消息丢弃。
void main() {
  Future<void> mountHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DsToastHost(key: DsToastHostState.rootKey, child: child!),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
  }

  testWidgets('剥离 Bad state/FormatException 前缀并修剪空白', (tester) async {
    await mountHost(tester);
    showDsToast('Bad state: 串口读取失败或设备已移除');
    await tester.pump();
    expect(find.text('串口读取失败或设备已移除'), findsOneWidget);
    expect(find.textContaining('Bad state:'), findsNothing);
  });

  testWidgets('同文同语义去重，重复错误不堆叠', (tester) async {
    await mountHost(tester);
    showDsToast('设备已拔出');
    showDsToast('设备已拔出');
    await tester.pump();
    expect(find.text('设备已拔出'), findsOneWidget);
  });

  testWidgets('不同语义视为不同提示，可并存', (tester) async {
    await mountHost(tester);
    showDsToast('同一文本', kind: DsToastKind.error);
    showDsToast('同一文本', kind: DsToastKind.warning);
    await tester.pump();
    expect(find.text('同一文本'), findsNWidgets(2));
  });

  testWidgets('空白或仅前缀的消息丢弃，不产生卡片', (tester) async {
    await mountHost(tester);
    showDsToast('   ');
    showDsToast('Bad state: ');
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}