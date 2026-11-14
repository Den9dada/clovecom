// 芯片配置信息卡片

import 'package:flutter/material.dart';
import '../../../models/i2c_register_map.dart';

class I2cChipConfigCard extends StatelessWidget {
  final I2cChipConfig config;
  final int registerCount;
  final String speedLabel; // 当前实际使用的速率挡位

  const I2cChipConfigCard({
    super.key,
    required this.config,
    required this.registerCount,
    this.speedLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.memory, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.moduleName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (config.version.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      config.version,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            _infoRow(context, '接口', config.interfaceType),
            _infoRow(context, '设备地址', config.deviceAddressHex),
            _infoRow(
              context,
              '速率',
              '${config.speed} kHz${speedLabel.isNotEmpty ? ' → $speedLabel' : ''}',
            ),
            _infoRow(
              context,
              '基地址',
              '0x${config.baseAddress.toRadixString(16).toUpperCase().padLeft(8, '0')}',
            ),
            _infoRow(
              context,
              '字节序',
              config.littleEndian ? 'Little-Endian' : 'Big-Endian',
            ),
            _infoRow(context, '寄存器数', '$registerCount 个'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Flexible(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
