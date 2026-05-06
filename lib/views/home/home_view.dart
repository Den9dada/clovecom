// 主页面视图文件
//
// 该文件实现了应用的主页面，采用TabBar进行模块切换。
// 包含四个Tab页：串口通信、USB通信、网络通信、工具箱。
//
// 主要功能：
// - 使用TabBar实现模块切换
// - 使用IndexedStack保持所有模块同时运行（切换Tab不会销毁之前的模块）
// - 支持滑动切换和点击切换

import 'package:flutter/material.dart';
import '../terminal/terminal_view.dart';
import '../serial_port/serial_port_view.dart';
import '../usb/usb_view.dart';
import '../network/network_view.dart';
import '../toolbox/toolbox_view.dart';

/// 主页面视图组件
///
/// 作为应用的主入口页面，提供TabBar导航。
/// 使用SingleTickerProviderStateMixin支持TabController的动画。
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

/// 主页面视图状态类
///
/// 管理TabController的生命周期，处理Tab切换逻辑。
class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  /// Tab控制器，管理Tab页的切换和动画
  late TabController _tabController;

  /// 当前选中的Tab索引
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 初始化Tab控制器，设置Tab数量为4
    // vsync参数用于动画同步，避免屏幕外动画消耗资源
    _tabController = TabController(length: 5, vsync: this);
    // 监听Tab切换
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    // 释放Tab控制器资源
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // 应用栏
      appBar: AppBar(
        toolbarHeight: 36,
        // 应用标题
        title: Row(
          children: [
            _buildMenuText(context, '文件'),
            _buildMenuText(context, '关于'),
          ],
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        // Tab栏，显示在应用栏底部
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          dividerColor: colorScheme.outlineVariant,
          labelStyle: Theme.of(context).textTheme.labelLarge,
          unselectedLabelStyle: Theme.of(context).textTheme.labelLarge,
          // Tab项列表
          tabs: const [
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal, size: 16),
                  SizedBox(width: 6),
                  Text('终端'),
                ],
              ),
            ),
            // 串口通信Tab
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.device_hub, size: 16),
                  SizedBox(width: 6),
                  Text('串口通信'),
                ],
              ),
            ),
            // USB通信Tab（预留）
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.usb, size: 16),
                  SizedBox(width: 6),
                  Text('USB通信'),
                ],
              ),
            ),
            // 网络通信Tab（预留）
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi, size: 16),
                  SizedBox(width: 6),
                  Text('网络通信'),
                ],
              ),
            ),
            // 工具箱Tab
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('工具箱'),
                ],
              ),
            ),
          ],
        ),
      ),
      // 使用 IndexedStack 保持所有模块同时运行
      // 切换Tab时不会销毁之前的模块，确保串口通信在后台继续工作
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          TerminalView(),
          // 串口通信页面
          SerialPortView(),
          // USB通信页面（预留）
          UsbView(),
          // 网络通信页面（预留）
          NetworkView(),
          // 工具箱页面
          ToolboxView(),
        ],
      ),
    );
  }

  Widget _buildMenuText(BuildContext context, String label) {
    return SizedBox(
      height: 28,
      child: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: Text(label),
      ),
    );
  }
}
