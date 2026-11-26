// 操作日志面板
//
// 显示 I2C 操作历史记录，每条记录含时间戳、操作描述、数据、成功/失败状态。

import 'package:material_ui/material_ui.dart';
import '../../../models/ch341_operation_result.dart';

class I2cLogPanel extends StatelessWidget {
  final List<Ch341OperationResult> logs;
  final VoidCallback? onClear;

  const I2cLogPanel({super.key, required this.logs, this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final okCount = logs.where((l) => l.success).length;
    final failCount = logs.where((l) => !l.success).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          // 头部：标题 + 统计 + 清除
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '操作日志',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '✓$okCount  ✗$failCount',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                if (logs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(
                      Icons.clear_all,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // 日志列表
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      '等待操作...',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final time =
                          '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'Consolas',
                                fontFamilyFallback: const [
                                  'Menlo',
                                  'Courier New',
                                  'MiSans',
                                ],
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              log.success ? Icons.check_circle : Icons.error,
                              size: 14,
                              color: log.success ? Colors.green : cs.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log.description,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  if (log.errorMessage != null)
                                    Text(
                                      log.errorMessage!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: cs.error,
                                      ),
                                    ),
                                  if (log.data != null && log.data!.isNotEmpty)
                                    Text(
                                      log.hexData,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'Consolas',
                                        fontFamilyFallback: const [
                                          'Menlo',
                                          'Courier New',
                                          'MiSans',
                                        ],
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
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
}
