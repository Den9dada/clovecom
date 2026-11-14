// I2C 工具主页面 — 3 个子 Tab + 公共设备栏
// 架构：仅设备栏监听 ViewModel 变化，3 个 Tab 不随 VM 通知重建

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../services/status_bar_service.dart';
import '../../viewmodels/ch341/i2c_tool_viewmodel.dart';
import 'widgets/i2c_device_bar.dart';
import 'widgets/i2c_register_tab.dart';
import 'widgets/i2c_new_register_tab.dart';
import 'widgets/i2c_transform_tab.dart';

class I2cToolView extends StatefulWidget {
  const I2cToolView({super.key});

  @override
  State<I2cToolView> createState() => _I2cToolViewState();
}

class _I2cToolViewState extends State<I2cToolView>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  int _cur = 0;

  // 缓存 Tab 页面（VM 变化时不重建子 Tab）
  late final _tabs = <Widget>[
    const I2cRegisterTab(),
    const I2cNewRegisterTab(),
    const I2cTransformTab(),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() => _cur = _tabCtrl.index);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChangeNotifierProvider(
      create: (_) {
        final vm = I2cToolViewModel();
        vm.loadDriver();
        vm.refreshDevices();
        return vm;
      },
      child: _I2cStatusBinder(
        child: Consumer<I2cToolViewModel>(
          builder: (context, vm, _) {
            return DropTarget(
              onDragEntered: (_) => vm.setDragHint(true),
              onDragExited: (_) => vm.setDragHint(false),
              onDragDone: (detail) {
                vm.setDragHint(false);
                final f = detail.files.firstOrNull;
                if (f != null && f.path.endsWith('.xlsx'))
                  vm.loadExcelFile(f.path);
              },
              child: Stack(
                children: [
                  Scaffold(
                    backgroundColor: cs.surface,
                    body: Column(
                      children: [
                        I2cDeviceBar(viewModel: vm),
                        Container(
                          color: cs.surface,
                          child: TabBar(
                            controller: _tabCtrl,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelColor: cs.primary,
                            unselectedLabelColor: cs.onSurfaceVariant,
                            indicatorColor: cs.primary,
                            indicatorWeight: 2,
                            dividerColor: cs.outlineVariant,
                            labelStyle: Theme.of(context).textTheme.labelLarge,
                            tabs: const [
                              Tab(
                                height: 34,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.table_chart, size: 16),
                                    SizedBox(width: 6),
                                    Text('Register'),
                                  ],
                                ),
                              ),
                              Tab(
                                height: 34,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.note_add, size: 16),
                                    SizedBox(width: 6),
                                    Text('New Register'),
                                  ],
                                ),
                              ),
                              Tab(
                                height: 34,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.swap_horiz, size: 16),
                                    SizedBox(width: 6),
                                    Text('Transform'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: IndexedStack(index: _cur, children: _tabs),
                        ),
                      ],
                    ),
                  ),
                  if (vm.showDragHint) _dragOverlay(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _dragOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: cs.primary.withValues(alpha: 0.12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_present, size: 48),
                  SizedBox(height: 12),
                  Text(
                    '松开以加载寄存器映射',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text('支持 .xlsx 格式', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _I2cStatusBinder extends StatefulWidget {
  const _I2cStatusBinder({required this.child});
  final Widget child;

  @override
  State<_I2cStatusBinder> createState() => _I2cStatusBinderState();
}

class _I2cStatusBinderState extends State<_I2cStatusBinder> {
  late final I2cToolViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<I2cToolViewModel>();
    _vm.addListener(_updateStatus);
    _updateStatus();
  }

  @override
  void dispose() {
    _vm.removeListener(_updateStatus);
    super.dispose();
  }

  void _updateStatus() {
    final vm = _vm;
    if (!vm.driverLoaded) {
      StatusBarService().update(
        4,
        const StatusBarInfo(
          text: 'CH341 驱动未加载',
          icon: Icons.error_outline,
          color: Colors.red,
        ),
      );
      return;
    }
    if (vm.isConnected && vm.selectedDeviceIndex != null) {
      final dev = vm.availableDevices
          .where((d) => d.deviceIndex == vm.selectedDeviceIndex)
          .firstOrNull;
      StatusBarService().update(
        4,
        StatusBarInfo(
          text: '已连接 ${dev?.description ?? "CH341 #${vm.selectedDeviceIndex}"}',
          icon: Icons.check_circle,
          color: Colors.green,
        ),
      );
      return;
    }
    final count = vm.availableDevices.length;
    StatusBarService().update(
      4,
      StatusBarInfo(
        text: count > 0 ? '就绪 — $count 个设备可用' : '就绪 — 未检测到设备',
        icon: Icons.circle_outlined,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
