// USB通信视图文件
// 
// 该文件实现了USB通信模块的占位页面。
// 目前为预留功能，显示"功能开发中"的提示信息。
// 
// 后续开发计划：
// - 实现USB设备枚举和连接
// - 支持USB数据传输
// - 提供USB设备信息显示

import 'package:flutter/material.dart';

/// USB通信视图组件
/// 
/// 作为USB通信模块的占位页面，显示功能开发中的提示。
/// 后续将实现完整的USB通信功能。
class UsbView extends StatelessWidget {
  const UsbView({super.key});

  @override
  Widget build(BuildContext context) {
    // 居中显示功能开发提示
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // USB图标
          Icon(Icons.usb, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          // 模块标题
          Text(
            'USB通信模块',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          // 开发状态提示
          Text(
            '功能开发中...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
