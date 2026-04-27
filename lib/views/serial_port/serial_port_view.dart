// 串口通信视图文件
// 
// 该文件实现了串口通信的用户界面，采用MVVM架构中的View层。
// 整体布局为左右分割，左侧为串口配置区，右侧为数据收发区。
// 
// 左侧配置区分为三部分：
// - 串口配置：端口选择、波特率、数据位、停止位、校验、流控、连接按键
// - 接收配置：ASCII/HEX显示、日志模式、自动换行、隐藏接收、保存文件、自动滚动、清空接收区
// - 发送配置：ASCII/HEX显示、循环发送、发送间隔
// 
// 右侧数据收发区：
// - 上方：数据日志（显示所有收发数据）
// - 下方：发送区（支持文本、十六进制、文件发送）

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/serial_port_model.dart';
import '../../viewmodels/serial_port_viewmodel.dart';
import '../../utils/hex_input_formatter.dart';
import '../../protocols/protocol_registry.dart';

/// 串口通信视图组件
class SerialPortView extends StatelessWidget {
  const SerialPortView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SerialPortViewModel(),
      child: const _SerialPortViewContent(),
    );
  }
}

/// 串口通信视图内容组件
class _SerialPortViewContent extends StatefulWidget {
  const _SerialPortViewContent();

  @override
  State<_SerialPortViewContent> createState() => _SerialPortViewContentState();
}

/// 串口通信视图内容状态类
class _SerialPortViewContentState extends State<_SerialPortViewContent> {
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _packetSizeController = TextEditingController(text: '1024');
  final TextEditingController _intervalController = TextEditingController(text: '100');
  final TextEditingController _loopIntervalController = TextEditingController(text: '1000');

  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<SerialPortViewModel>();
      _errorSub = viewModel.errorStream.listen((message) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message, style: const TextStyle(fontSize: 13)),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(12),
            ),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _sendController.dispose();
    _scrollController.dispose();
    _packetSizeController.dispose();
    _intervalController.dispose();
    _loopIntervalController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SerialPortViewModel>();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 顶部：端口选择行（横跨全宽）
          _buildPortBar(viewModel, colorScheme),
          const SizedBox(height: 12),
          // 下方：左侧配置区 + 右侧数据收发区
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧：配置区
                SizedBox(
                  width: 260,
                  child: _buildConfigPanel(viewModel, colorScheme),
                ),
                const SizedBox(width: 12),
                // 右侧：数据收发区
                Expanded(
                  child: _buildDataPanel(viewModel, colorScheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建顶部端口选择行（横跨全宽，对齐配置区和数据日志区）
  Widget _buildPortBar(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // 端口选择
            Icon(Icons.device_hub, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '选择端口',
                ),
                initialValue: viewModel.config.portName.isEmpty ? null : viewModel.config.portName,
                items: viewModel.availablePorts.map((port) {
                  return DropdownMenuItem(
                    value: port.portName,
                    child: Tooltip(
                      message: '${port.friendlyName}\n${port.hardwareID}',
                      child: Text(port.displayText, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                    ),
                  );
                }).toList(),
                onChanged: viewModel.state.isConnected ? null : (value) {
                  if (value != null) {
                    final port = viewModel.availablePorts.firstWhere(
                      (p) => p.portName == value,
                      orElse: () => PortDetailInfo(portName: value, friendlyName: '', hardwareID: '', manufactureName: ''),
                    );
                    viewModel.updateConfig(portName: value, portFriendlyName: port.friendlyName);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: viewModel.refreshPorts,
              tooltip: '刷新串口列表',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 16),
            // 波特率
            Icon(Icons.speed, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                initialValue: viewModel.config.baudRate,
                items: [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600].map((rate) {
                  return DropdownMenuItem(value: rate, child: Text('$rate'));
                }).toList(),
                onChanged: viewModel.state.isConnected ? null : (v) => viewModel.updateConfig(baudRate: v!),
              ),
            ),
            const SizedBox(width: 16),
            // 连接按钮
            _buildConnectionButton(viewModel, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 构建连接按钮
  Widget _buildConnectionButton(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    final isConnected = viewModel.state.isConnected;
    return SizedBox(
      width: 120,
      child: FilledButton.icon(
        onPressed: () async {
          if (isConnected) {
            await viewModel.disconnect();
          } else {
            await viewModel.connect();
          }
        },
        icon: Icon(isConnected ? Icons.link_off : Icons.link, size: 16),
        label: Text(isConnected ? '断开连接' : '打开串口'),
        style: FilledButton.styleFrom(
          backgroundColor: isConnected ? colorScheme.error : colorScheme.primary,
          foregroundColor: isConnected ? colorScheme.onError : colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  /// 构建配置面板
  Widget _buildConfigPanel(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 串口配置
          _buildSerialConfig(viewModel, colorScheme),
          const SizedBox(height: 12),
          // 接收配置
          _buildReceiveConfig(viewModel, colorScheme),
          const SizedBox(height: 12),
          // 发送配置
          _buildSendConfig(viewModel, colorScheme),
        ],
      ),
    );
  }

  /// 构建串口高级配置（数据位、停止位、校验、流控）
  Widget _buildSerialConfig(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.settings_outlined, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('串口参数', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(height: 16),
            // 数据位
            _buildDropdown<int>(
              label: '数据位',
              value: viewModel.config.dataBits,
              items: [5, 6, 7, 8].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
              onChanged: viewModel.state.isConnected ? null : (v) => viewModel.updateConfig(dataBits: v!),
            ),
            const SizedBox(height: 8),
            // 停止位
            _buildDropdown<int>(
              label: '停止位',
              value: viewModel.config.stopBits,
              items: [1, 2].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
              onChanged: viewModel.state.isConnected ? null : (v) => viewModel.updateConfig(stopBits: v!),
            ),
            const SizedBox(height: 8),
            // 校验
            _buildDropdown<String>(
              label: '校验',
              value: viewModel.config.parity,
              items: ['None', 'Odd', 'Even', 'Mark', 'Space'].map((v) {
                String label;
                switch (v) {
                  case 'None': label = '无校验';
                  case 'Odd': label = '奇校验';
                  case 'Even': label = '偶校验';
                  case 'Mark': label = '标记';
                  case 'Space': label = '空格';
                  default: label = v;
                }
                return DropdownMenuItem(value: v, child: Text(label));
              }).toList(),
              onChanged: viewModel.state.isConnected ? null : (v) => viewModel.updateConfig(parity: v!),
            ),
            const SizedBox(height: 8),
            // 流控
            _buildDropdown<String>(
              label: '流控',
              value: viewModel.config.flowControl,
              items: ['None', 'XON/XOFF', 'RTS/CTS', 'DTR/DSR'].map((v) {
                return DropdownMenuItem(value: v, child: Text(v));
              }).toList(),
              onChanged: viewModel.state.isConnected ? null : (v) => viewModel.updateConfig(flowControl: v!),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建通用下拉框
  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 45,
          child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: DropdownButtonFormField<T>(
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            initialValue: value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 构建接收配置
  Widget _buildReceiveConfig(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    final config = viewModel.displayConfig;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.download_outlined, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('接收配置', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(height: 12),
            // 开关选项 - 使用 Wrap 布局更紧凑
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                _buildCompactSwitch(
                  title: 'HEX显示',
                  value: config.receiveHex,
                  onChanged: (v) => viewModel.updateDisplayConfig(receiveHex: v),
                ),
                _buildCompactSwitch(
                  title: '日志模式',
                  value: config.logMode,
                  onChanged: (v) => viewModel.updateDisplayConfig(logMode: v),
                ),
                _buildCompactSwitch(
                  title: '自动换行',
                  value: config.autoWrap,
                  onChanged: (v) => viewModel.updateDisplayConfig(autoWrap: v),
                ),
                _buildCompactSwitch(
                  title: '隐藏接收',
                  value: config.hideReceive,
                  onChanged: (v) => viewModel.updateDisplayConfig(hideReceive: v),
                ),
                _buildCompactSwitch(
                  title: '保存文件',
                  value: config.saveToFile,
                  onChanged: (v) => viewModel.updateDisplayConfig(saveToFile: v),
                ),
                _buildCompactSwitch(
                  title: '自动滚动',
                  value: config.autoScroll,
                  onChanged: (v) => viewModel.updateDisplayConfig(autoScroll: v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 清空接收区按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: viewModel.clearMessages,
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('清空接收区', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建发送配置
  Widget _buildSendConfig(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    final config = viewModel.displayConfig;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.upload_outlined, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('发送配置', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const Divider(height: 12),
            // 开关选项
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                _buildCompactSwitch(
                  title: 'HEX发送',
                  value: config.sendHex,
                  onChanged: (v) {
                    if (_sendController.text.isNotEmpty) {
                      if (v) {
                        _sendController.text = viewModel.convertTextToHex(_sendController.text);
                      } else {
                        final text = viewModel.convertHexToText(_sendController.text);
                        if (text != null) {
                          _sendController.text = text;
                        }
                      }
                    }
                    viewModel.updateDisplayConfig(sendHex: v);
                  },
                ),
                _buildCompactSwitch(
                  title: '循环发送',
                  value: config.loopSend,
                  onChanged: (v) => viewModel.updateDisplayConfig(loopSend: v),
                ),
                _buildCompactSwitch(
                  title: '追加回车',
                  value: config.appendCR,
                  onChanged: (v) => viewModel.updateDisplayConfig(appendCR: v),
                ),
                _buildCompactSwitch(
                  title: '追加新行',
                  value: config.appendLF,
                  onChanged: (v) => viewModel.updateDisplayConfig(appendLF: v),
                ),
              ],
            ),
            // 循环发送间隔
            if (config.loopSend) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('间隔:', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _loopIntervalController,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        isDense: true,
                        suffixText: 'ms',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      onChanged: (value) {
                        final interval = int.tryParse(value);
                        if (interval != null && interval > 0) {
                          viewModel.updateDisplayConfig(loopInterval: interval);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建紧凑开关项（用于 Wrap 布局）
  Widget _buildCompactSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 115,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Flexible(
            child: Text(
              title, 
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建数据收发面板
  Widget _buildDataPanel(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return Card(
      child: Column(
        children: [
          // 数据日志
          Expanded(
            flex: 3,
            child: _buildLogArea(viewModel, colorScheme),
          ),
          // 发送区
          Expanded(
            flex: 2,
            child: _buildSendArea(viewModel, colorScheme),
          ),
        ],
      ),
    );
  }

  /// 构建数据日志区
  Widget _buildLogArea(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (viewModel.displayConfig.autoScroll) {
        _scrollToBottom();
      }
    });

    final messages = viewModel.messages;
    final displayConfig = viewModel.displayConfig;

    return Column(
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(Icons.article_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text('数据日志', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              // 统计信息
              Text(
                'RX: ${viewModel.formatBytes(viewModel.stats.receivedBytes)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.tertiary),
              ),
              const SizedBox(width: 12),
              Text(
                'TX: ${viewModel.formatBytes(viewModel.stats.sentBytes)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.primary),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 消息列表
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text('暂无数据', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.5))),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _buildMessageItem(message, colorScheme, displayConfig.receiveHex);
                  },
                ),
        ),
      ],
    );
  }

  /// 构建消息项
  Widget _buildMessageItem(SerialPortMessage message, ColorScheme colorScheme, bool showHex) {
    final timeStr = DateFormat('HH:mm:ss.SSS').format(message.timestamp);
    // HEX模式下优先显示hexData，无hexData时回退到data（如协议日志）
    final displayData = (showHex && message.hexData.isNotEmpty) ? message.hexData : message.data;
    final isSent = message.isSent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间戳
          Text(
            timeStr,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.6),
              fontFamily: 'Roboto Mono',
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          // RX/TX标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isSent ? colorScheme.primary.withOpacity(0.2) : colorScheme.tertiary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              isSent ? 'TX' : 'RX',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isSent ? colorScheme.primary : colorScheme.tertiary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 数据内容
          Expanded(
            child: Text(
              displayData,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'Roboto Mono',
                fontSize: 12,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建发送区
  Widget _buildSendArea(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(Icons.upload_outlined, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('数据发送', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
          // Tab栏
          TabBar(
            tabs: const [
              Tab(text: '数据发送'),
              Tab(text: '文件发送'),
              Tab(text: '固件升级'),
            ],
            labelStyle: Theme.of(context).textTheme.labelSmall,
            unselectedLabelStyle: Theme.of(context).textTheme.labelSmall,
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            dividerHeight: 1,
          ),
          // Tab内容
          Expanded(
            child: TabBarView(
              children: [
                _buildTextSendArea(viewModel, colorScheme),
                _buildFileSendArea(viewModel, colorScheme),
                _buildFirmwareUpgradeArea(viewModel, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建文本发送区
  Widget _buildTextSendArea(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // HEX提示信息
          if (viewModel.displayConfig.sendHex) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'HEX格式：每两个十六进制字符用空格隔开，如：48 65 6C 6C 6F',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 输入框和发送按钮
          Expanded(
            child: Row(
              children: [
                // 输入框
                Expanded(
                  child: TextField(
                    controller: _sendController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      hintText: viewModel.displayConfig.sendHex ? '输入HEX数据' : '输入文本数据',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    inputFormatters: viewModel.displayConfig.sendHex
                        ? [HexInputFormatter()]
                        : [],
                  ),
                ),
                const SizedBox(width: 8),
                // 发送按钮
                SizedBox(
                  width: 80,
                  child: FilledButton(
                    onPressed: viewModel.state.isConnected
                        ? () async {
                            if (_sendController.text.isNotEmpty) {
                              await viewModel.sendDataWithLoopCheck(_sendController.text);
                            }
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('发送'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建文件发送区
  Widget _buildFileSendArea(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 文件选择
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          viewModel.fileSendConfig.fileName.isEmpty ? '未选择文件' : viewModel.fileSendConfig.fileName,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: viewModel.selectFile,
                child: const Text('选择文件'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 协议选择
          Row(
            children: [
              Text('协议:', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                  ),
                  value: viewModel.fileSendConfig.protocolName,
                  items: ProtocolRegistry.protocols.map((p) {
                    return DropdownMenuItem(
                      value: p.name,
                      child: Text(p.name, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: viewModel.fileSendConfig.isSending
                      ? null
                      : (v) {
                          if (v != null) {
                            viewModel.updateFileSendConfig(protocolName: v);
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 发送配置（仅分包发送协议显示）
          if (viewModel.fileSendConfig.protocolName == '分包发送')
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('每包:', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _packetSizeController,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            isDense: true,
                            suffixText: 'B',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final size = int.tryParse(v);
                            if (size != null && size > 0) viewModel.updateFileSendConfig(packetSize: size);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Text('间隔:', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _intervalController,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            isDense: true,
                            suffixText: 'ms',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final interval = int.tryParse(v);
                            if (interval != null && interval > 0) viewModel.updateFileSendConfig(sendInterval: interval);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          // 进度条
          if (viewModel.fileSendConfig.fileSize > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: viewModel.fileSendConfig.progress,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(viewModel.fileSendConfig.progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
          const Spacer(),
          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: viewModel.state.isConnected && !viewModel.fileSendConfig.isSending
                      ? viewModel.startFileSend
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('开始发送'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.tertiary,
                    foregroundColor: colorScheme.onTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: viewModel.fileSendConfig.isSending ? viewModel.stopFileSend : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                  ),
                ),
              ),
             ],
          ),
        ],
      ),
    );
  }

  /// 构建固件升级区
  Widget _buildFirmwareUpgradeArea(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    final config = viewModel.firmwareConfig;
    final isUpgrading = config.isUpgrading;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 固件文件选择
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.system_update_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          config.firmwareName.isEmpty ? '未选择固件 (.bin)' : config.firmwareName,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: isUpgrading ? null : viewModel.selectFirmwareFile,
                child: const Text('选择固件'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 升级脚本选择
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.code_outlined, size: 16, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          config.scriptName.isEmpty ? '默认脚本（分包发送）' : config.scriptName,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (config.scriptName.isNotEmpty)
                IconButton(
                  onPressed: isUpgrading ? null : viewModel.clearFirmwareScript,
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: '恢复默认',
                  visualDensity: VisualDensity.compact,
                ),
              OutlinedButton(
                onPressed: isUpgrading ? null : viewModel.selectFirmwareScript,
                child: const Text('选择脚本'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条（仅在选择了固件或正在升级时显示）
          if (config.firmwareSize > 0 || isUpgrading) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isUpgrading && config.progress <= 0 ? null : config.progress,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(config.progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
          const Spacer(),
          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: viewModel.state.isConnected && !isUpgrading
                      ? viewModel.startFirmwareUpgrade
                      : null,
                  icon: const Icon(Icons.upgrade, size: 16),
                  label: const Text('开始升级'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.tertiary,
                    foregroundColor: colorScheme.onTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isUpgrading ? viewModel.stopFirmwareUpgrade : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
