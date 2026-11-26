import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../src/application/app_update.dart';
import '../../src/platform/windows_app_update.dart';
import 'ds_toast.dart';
import 'ds_widgets.dart';

String appUpdateError(Object error) => switch (error) {
  SocketException() ||
  TimeoutException() ||
  HandshakeException() => '无法连接更新服务，请检查网络后重试。',
  HttpException(:final message) => message,
  FormatException(:final message) => message,
  FileSystemException() => '无法保存更新安装包，请检查磁盘空间和权限后重试。',
  PlatformException(:final message) => message ?? '无法启动更新安装程序。',
  MissingPluginException() => '当前环境不支持应用更新。',
  _ => '操作失败，请稍后重试。',
};

String appUpdateLabel(AppUpdateController controller) =>
    switch (controller.phase) {
      AppUpdatePhase.downloading =>
        controller.progress?.fraction == null
            ? '正在下载…'
            : '下载 ${(controller.progress!.fraction! * 100).floor()}%',
      AppUpdatePhase.ready => '重启',
      AppUpdatePhase.restarting => '正在重启…',
      _ => controller.error == null ? '更新' : '重试更新',
    };

class AppUpdateButton extends StatelessWidget {
  const AppUpdateButton({
    super.key,
    required this.controller,
    required this.onExit,
  });
  final AppUpdateController controller;
  final Future<void> Function() onExit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.visible) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: controller.error != null
              ? appUpdateError(controller.error!)
              : controller.phase == AppUpdatePhase.ready
              ? '保存工作后点击，退出应用并在后台安装新版，完成后自动重启。'
              : '发现新版本 ${controller.result!.feed!.version}',
          child: SizedBox(
            width: 132,
            height: 28,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                DsButton(
                  label: appUpdateLabel(controller),
                  icon: controller.phase == AppUpdatePhase.ready
                      ? Icons.restart_alt
                      : Icons.system_update_alt,
                  variant: DsButtonVariant.brand,
                  expand: true,
                  onPressed: controller.busy
                      ? null
                      : () async {
                          if (controller.phase == AppUpdatePhase.ready) {
                            await controller.restart(onExit);
                          } else {
                            await controller.download();
                          }
                          if (context.mounted && controller.error != null) {
                            showDsToast(
                              appUpdateError(controller.error!),
                              kind: DsToastKind.error,
                            );
                          }
                        },
                ),
                if (controller.phase == AppUpdatePhase.downloading)
                  LinearProgressIndicator(
                    value: controller.progress?.fraction,
                    minHeight: 2,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showAppUpdateDialog(
  BuildContext context, {
  AppUpdateController? controller,
  Future<void> Function()? onExitForUpdate,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      AppUpdateDialog(controller: controller, onExitForUpdate: onExitForUpdate),
);

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    this.service,
    this.controller,
    this.onExitForUpdate,
  });
  final AppUpdateService? service;
  final AppUpdateController? controller;
  final Future<void> Function()? onExitForUpdate;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late final AppUpdateController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        AppUpdateController(
          service:
              widget.service ?? AppUpdateService(host: WindowsAppUpdateHost()),
        );
    unawaited(_controller.check());
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final result = _controller.result;
      return DsDialog(
        title: SizedBox(
          width: 440,
          child: Row(
            children: [
              const Expanded(child: Text('检查更新')),
              Tooltip(
                message: '定时检查更新间隔',
                child: DsSelect<AppUpdateInterval>(
                  key: const ValueKey('app-update-interval'),
                  value: _controller.checkInterval,
                  enabled: !_controller.savingInterval,
                  items: [
                    for (final interval in AppUpdateInterval.values)
                      DropdownMenuItem(
                        value: interval,
                        child: Text(interval.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_controller.setCheckInterval(value));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        error: _controller.error == null
            ? null
            : appUpdateError(_controller.error!),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (result != null) Text('当前版本：${result.installed.version}'),
              if (_controller.phase == AppUpdatePhase.checking)
                const Text('正在检查更新…')
              else if (result != null) ...[
                if (result.feed == null)
                  const Text('当前暂无可用的正式发行版，请稍后再试。')
                else if (!result.available)
                  const Text('当前已是最新版本。')
                else ...[
                  Text('发现新版本：${result.feed!.version}'),
                  const Text('下载完成后可重启安装更新，请先保存工作。'),
                ],
              ],
              if (_controller.phase == AppUpdatePhase.downloading)
                LinearProgressIndicator(value: _controller.progress?.fraction),
              if (_controller.phase == AppUpdatePhase.ready)
                const Text('安装包已下载并通过校验，等待重启。'),
            ],
          ),
        ),
        actions: [
          DsButton(label: '关闭', onPressed: () => Navigator.of(context).pop()),
          DsButton(
            label: '重新检查',
            onPressed:
                _controller.busy || _controller.phase == AppUpdatePhase.ready
                ? null
                : _controller.check,
          ),
          if (result?.available == true)
            DsButton(
              label: appUpdateLabel(_controller),
              variant: DsButtonVariant.brand,
              onPressed: _controller.busy
                  ? null
                  : () {
                      if (_controller.phase == AppUpdatePhase.ready) {
                        unawaited(
                          _controller.restart(
                            widget.onExitForUpdate ?? () async {},
                          ),
                        );
                      } else {
                        unawaited(_controller.download());
                      }
                    },
            ),
        ],
      );
    },
  );
}
