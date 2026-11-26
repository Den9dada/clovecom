import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clovecom/main.dart';
import 'package:clovecom/widgets/communication_session_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 在测试挂载组件前完成字体加载和系统通知。
  setUpAll(() async {
    final loader = FontLoader('MiSans')
      ..addFont(rootBundle.load('assets/fonts/MiSans/MiSans-Regular.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final mono = FontLoader('Consolas');
    final monoFile = File('C:/Windows/Fonts/consola.ttf');
    if (monoFile.existsSync()) {
      mono.addFont(
        Future.value(ByteData.sublistView(monoFile.readAsBytesSync())),
      );
      await mono.load();
    }
  });

  testWidgets('桌面页面截图与布局验证', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: const MyApp()));
    await tester.pump(const Duration(seconds: 1));
    final pages = {
      'interface': '接口通信',
      'toolbox': '工具箱',
      'ch34x': 'CH34x调试',
      'protocol': '协议编辑',
    };
    for (final page in pages.entries) {
      await tester.tap(find.text(page.value).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: page.value);
      expect(find.byTooltip('通信管理'), findsNothing);
      expect(
        find.byKey(const ValueKey('communication-session-list')),
        page.key == 'interface' ? findsOneWidget : findsNothing,
      );
      if (page.key == 'interface') {
        final content = tester.getRect(
          find.byKey(const ValueKey('home-content')),
        );
        final workspace = tester.getRect(
          find.byType(CommunicationSessionWorkspace),
        );
        final sidebar = tester.getRect(
          find.byKey(const ValueKey('communication-session-list')),
        );
        expect(workspace, content);
        expect(sidebar.top, content.top);
        expect(sidebar.right, content.right);
        expect(sidebar.bottom, content.bottom);
      }
      if (const bool.fromEnvironment('GUI_SCREENSHOTS')) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(() async {
          final dir = Directory('docs/design/clovecom-screenshots');
          await dir.create(recursive: true);
          await File('${dir.path}/${page.key}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
        image.dispose();
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
