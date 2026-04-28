import 'dart:typed_data';

import 'package:flutter/material.dart';

class HexAsciiViewer extends StatelessWidget {
  const HexAsciiViewer({super.key, required this.bytes, this.baseAddress = 0});

  final Uint8List bytes;
  final int baseAddress;

  static const int _bytesPerLine = 16;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Text('地址', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 78),
                Text('HEX', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text('ASCII', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          Expanded(
            child: bytes.isEmpty
                ? Center(
                    child: Text(
                      '拖入或导入文件后显示 HEX/ASCII 数据',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: (bytes.length / _bytesPerLine).ceil(),
                    itemBuilder: (context, index) {
                      final start = index * _bytesPerLine;
                      final end = (start + _bytesPerLine).clamp(
                        0,
                        bytes.length,
                      );
                      final lineBytes = bytes.sublist(start, end);
                      final offset = (baseAddress + start)
                          .toRadixString(16)
                          .padLeft(8, '0')
                          .toUpperCase();
                      final hex = lineBytes
                          .map(
                            (byte) => byte
                                .toRadixString(16)
                                .padLeft(2, '0')
                                .toUpperCase(),
                          )
                          .join(' ');
                      final ascii = String.fromCharCodes(
                        lineBytes.map(
                          (byte) => byte >= 0x20 && byte <= 0x7E ? byte : 0x2E,
                        ),
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 3,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 82,
                              child: Text(offset, style: _mono(context)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(hex, style: _mono(context))),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 132,
                              child: Text(ascii, style: _mono(context)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  TextStyle _mono(BuildContext context) {
    return Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontFamily: 'Consolas', height: 1.35) ??
        const TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.35);
  }
}
