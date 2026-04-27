// 主页面视图文件
// 
// 该文件实现了应用的主页面，采用TabBar进行模块切换。
// 包含三个Tab页：串口通信、USB通信、网络通信。
// 
// 主要功能：
// - 使用TabBar实现模块切换
// - 使用IndexedStack保持所有模块同时运行（切换Tab不会销毁之前的模块）
// - 支持滑动切换和点击切换

import 'package:flutter/material.dart';
import '../serial_port/serial_port_view.dart';
import '../usb/usb_view.dart';
import '../network/network_view.dart';

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
class _HomeViewState extends State<HomeView> with SingleTickerProviderStateMixin {
  /// Tab控制器，管理Tab页的切换和动画
  late TabController _tabController;

  /// 当前选中的Tab索引
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 初始化Tab控制器，设置Tab数量为3
    // vsync参数用于动画同步，避免屏幕外动画消耗资源
    _tabController = TabController(length: 3, vsync: this);
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
    return Scaffold(
      // 应用栏
      appBar: AppBar(
        // 应用标题
        title: const Text('通信助手'),
        // 应用栏背景色，使用主题的反primary色
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Tab栏，显示在应用栏底部
        bottom: TabBar(
          controller: _tabController,
          // Tab项列表
          tabs: const [
            // 串口通信Tab
            Tab(icon: Icon(Icons.device_hub), text: '串口通信'),
            // USB通信Tab（预留）
            Tab(icon: Icon(Icons.usb), text: 'USB通信'),
            // 网络通信Tab（预留）
            Tab(icon: Icon(Icons.wifi), text: '网络通信'),
          ],
        ),
      ),
      // 使用 IndexedStack 保持所有模块同时运行
      // 切换Tab时不会销毁之前的模块，确保串口通信在后台继续工作
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          // 串口通信页面
          SerialPortView(),
          // USB通信页面（预留）
          UsbView(),
          // 网络通信页面（预留）
          NetworkView(),
        ],
      ),
    );
  }
}
