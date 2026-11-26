import 'dart:async';
import 'dart:io';

import 'src/application/app_update.dart';
import 'src/application/communication_runtime.dart';
import 'src/application/communication_configuration_store.dart';
import 'src/io/app_update_preferences.dart';
import 'src/io/interface_scan.dart';
import 'src/platform/windows_app_update.dart';
import 'services/serial/serial_port_catalog.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/desktop_theme.dart';
import 'ui/layout/responsive.dart';
import 'ui/theme/app_theme_controller.dart';
import 'ui/widgets/ds_toast.dart';
import 'views/home/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop =
      !kIsWeb &&
      {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  if (desktop) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
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
  final runtime = CommunicationRuntime(
    configurationStore: FileCommunicationConfigurationStore(),
    interfaceScanner: () => scanInterfaceEndpoints(SerialPortCatalog()),
  );
  await runtime.initialize();
  runApp(MyApp(runtime: runtime, ownsRuntime: true, manageWindow: desktop));
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.runtime,
    this.ownsRuntime = false,
    this.manageWindow = false,
    this.updateController,
  });
  final CommunicationRuntime? runtime;
  final bool ownsRuntime, manageWindow;
  final AppUpdateController? updateController;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  late final CommunicationRuntime _runtime =
      widget.runtime ?? CommunicationRuntime();
  final _themeController = AppThemeController();
  AppUpdateController? _updateController;
  bool _ownsUpdateController = false;
  bool _closingWindow = false;
  bool _allowNativeClose = false;
  String? _reportedConfigurationError;
  bool get _ownsRuntime => widget.runtime == null || widget.ownsRuntime;

  @override
  void initState() {
    super.initState();
    if (widget.manageWindow) windowManager.addListener(this);
    _runtime.workspaceChanges.addListener(_configurationChanged);
    unawaited(_themeController.load());
    unawaited(_runtime.initialize());
    if (widget.updateController != null) {
      _updateController = widget.updateController;
    } else if (widget.manageWindow &&
        defaultTargetPlatform == TargetPlatform.windows) {
      _ownsUpdateController = true;
      unawaited(_initAppUpdate());
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _configurationChanged(),
    );
  }

  Future<void> _initAppUpdate() async {
    try {
      final dir = await getApplicationSupportDirectory();
      if (!mounted) return;
      final preferences = AppUpdatePreferences(
        File('${dir.path}/update_preferences.json'),
      );
      final interval = await preferences.load();
      if (!mounted) return;
      final controller = AppUpdateController(
        service: AppUpdateService(host: WindowsAppUpdateHost()),
        checkInterval: interval,
        saveInterval: preferences.save,
      )..start();
      setState(() => _updateController = controller);
    } catch (error) {
      debugPrint('初始化自动更新失败：$error');
    }
  }

  void _configurationChanged() {
    final error = _runtime.configurationError;
    if (error == null) {
      _reportedConfigurationError = null;
      return;
    }
    if (error == _reportedConfigurationError) return;
    _reportedConfigurationError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDsToast(error, kind: DsToastKind.error);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void onWindowClose() {
    unawaited(_closeWindow());
  }

  Future<void> _closeWindow() async {
    if (_closingWindow || _allowNativeClose) return;
    _closingWindow = true;
    try {
      await _runtime.flushConfiguration();
      if (_ownsRuntime) await _runtime.dispose();
      if (defaultTargetPlatform == TargetPlatform.windows) {
        // Windows 插件的 destroy 直接投递 WM_QUIT。放行 WM_CLOSE，
        // 让原生窗口在消息循环内销毁，插件也会再次通知 onWindowClose。
        _allowNativeClose = true;
        await windowManager.setPreventClose(false);
        await windowManager.close();
      } else {
        await windowManager.destroy();
      }
    } catch (error) {
      if (_allowNativeClose) {
        _allowNativeClose = false;
        try {
          await windowManager.setPreventClose(true);
        } catch (restoreError) {
          debugPrint('恢复窗口关闭拦截失败：$restoreError');
        }
      }
      showDsToast('退出未完成，可重试：$error', kind: DsToastKind.error);
    } finally {
      _closingWindow = false;
    }
  }

  @override
  void dispose() {
    if (widget.manageWindow) windowManager.removeListener(this);
    _runtime.workspaceChanges.removeListener(_configurationChanged);
    if (_ownsUpdateController) _updateController?.dispose();
    _themeController.dispose();
    if (_ownsRuntime) {
      unawaited(
        _runtime.dispose().catchError((Object error) {
          debugPrint('通信内核释放失败：$error');
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppThemeScope(
    controller: _themeController,
    child: ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) => MaterialApp(
        title: '通信助手',
        debugShowCheckedModeBanner: false,
        theme: buildDesktopTheme(scheme: _themeController.scheme),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => DsToastHost(
          key: DsToastHostState.rootKey,
          child: ResponsiveScope(child: child!),
        ),
        home: HomeView(
          communication: _runtime,
          updateController: _updateController,
          onExitForUpdate: _closeWindow,
        ),
      ),
    ),
  );
}
