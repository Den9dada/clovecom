import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/desktop_theme.dart';
import 'ui/layout/responsive.dart';
import 'ui/widgets/ds_toast.dart';
import 'views/home/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform)) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(1240, 860),
        center: true,
        title: '通信助手',
        backgroundColor: Colors.white,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '通信助手',
    debugShowCheckedModeBanner: false,
    theme: buildDesktopTheme(),
    builder: (context, child) => DsToastHost(
      key: DsToastHostState.rootKey,
      child: ResponsiveScope(child: child!),
    ),
    home: const HomeView(),
  );
}
