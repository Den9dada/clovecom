// 寄存器列表 — StatefulWidget 确保 itemBuilder 引用稳定（避免闭包重建）

import 'package:material_ui/material_ui.dart';
import '../../../models/i2c_register_map.dart';

class I2cRegisterList extends StatefulWidget {
  final List<I2cRegister> registers;
  final int? selectedIndex;
  final void Function(int index) onSelect;
  final void Function(int index) onDoubleTap;
  final bool showCheckbox;
  final Set<int>? checkedIndices;
  final void Function(int index)? onToggleCheck;

  const I2cRegisterList({
    super.key,
    required this.registers,
    this.selectedIndex,
    required this.onSelect,
    required this.onDoubleTap,
    this.showCheckbox = false,
    this.checkedIndices,
    this.onToggleCheck,
  });

  @override
  State<I2cRegisterList> createState() => _I2cRegisterListState();
}

class _I2cRegisterListState extends State<I2cRegisterList> {
  // 稳定的实例方法引用，避免每帧重建闭包导致 ListView 全部重建
  Widget _itemBuilder(BuildContext context, int index) {
    final reg = widget.registers[index];
    final cs = Theme.of(context).colorScheme;

    Color? statusColor;
    if (reg.isModified) {
      statusColor = Colors.blue;
    } else if (reg.hasBeenRead) {
      statusColor = Colors.green;
    }

    final isSelected = index == widget.selectedIndex;
    final isChecked = widget.checkedIndices?.contains(index) ?? false;

    return Container(
      color: isChecked
          ? cs.primary.withValues(alpha: 0.08)
          : isSelected
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (widget.showCheckbox)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: isChecked,
                  onChanged: (_) => widget.onToggleCheck?.call(index),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: cs.outlineVariant, width: 1.5),
                ),
              ),
            )
          else
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor ?? cs.outlineVariant,
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(index),
              onDoubleTap: () => widget.onDoubleTap(index),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      reg.offsetHex,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Consolas',
                        fontFamilyFallback: const [
                          'Menlo',
                          'Courier New',
                          'MiSans',
                        ],
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      reg.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _permColor(reg, cs),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _permLabel(reg),
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sepBuilder(BuildContext context, int index) =>
      const Divider(height: 1, indent: 12);

  Color _permColor(I2cRegister reg, ColorScheme cs) {
    if (reg.bitFields.isEmpty) return cs.outline;
    if (reg.bitFields.every((bf) => bf.isReadOnly)) return Colors.orange;
    return cs.primary;
  }

  String _permLabel(I2cRegister reg) {
    if (reg.bitFields.isEmpty) return '--';
    final ro = reg.bitFields.any((bf) => bf.isReadOnly);
    final rw = reg.bitFields.any((bf) => bf.isReadWrite);
    if (ro && !rw) return 'R';
    if (rw && !ro) return 'RW';
    return 'R/RW';
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: widget.registers.length,
      itemBuilder: _itemBuilder,
      separatorBuilder: _sepBuilder,
    );
  }
}
