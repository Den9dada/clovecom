// New Register 子页 — 手动创建寄存器定义并导出 Excel

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clovecom/utils/file_picker_compat.dart';
import '../../../viewmodels/ch341/i2c_tool_viewmodel.dart';
import '../../../models/i2c_register_map.dart';
import 'i2c_register_list.dart';

class I2cNewRegisterTab extends StatefulWidget {
  const I2cNewRegisterTab({super.key});
  @override
  State<I2cNewRegisterTab> createState() => _I2cNewRegisterTabState();
}

class _I2cNewRegisterTabState extends State<I2cNewRegisterTab> {
  final _moduleCtrl = TextEditingController(text: 'New Module');
  final _versionCtrl = TextEditingController(text: 'V1.0');
  final _ifCtrl = TextEditingController(text: 'I2C');
  final _speedCtrl = TextEditingController(text: '400');
  final _addrCtrl = TextEditingController(text: '0x00');
  final _baseCtrl = TextEditingController(text: '0x00000000');
  final List<_Reg> _regs = [];
  int? _selIdx;
  final Set<int> _checked = {};
  List<I2cRegister>? _cache;

  List<I2cRegister> get _mapped {
    _cache ??= _regs.map((r) => r.reg).toList();
    return _cache!;
  }

  int _p(String s) {
    s = s.trim();
    if (s.startsWith('0x') || s.startsWith('0X'))
      return int.tryParse(s.substring(2), radix: 16) ?? 0;
    return int.tryParse(s) ?? 0;
  }

  Future<void> _export() async {
    final cfg = I2cChipConfig(
      moduleName: _moduleCtrl.text.isEmpty ? 'New' : _moduleCtrl.text.trim(),
      version: _versionCtrl.text.trim(),
      interfaceType: _ifCtrl.text.isEmpty ? 'I2C' : _ifCtrl.text.trim(),
      speed: int.tryParse(_speedCtrl.text) ?? 400,
      deviceAddress: _p(_addrCtrl.text),
      baseAddress: _p(_baseCtrl.text),
    );
    final map = I2cRegisterMap(
      filePath: '',
      chipConfig: cfg,
      registers: _mapped,
    );
    final r = await FilePickerCompat.saveFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      fileName: '${cfg.moduleName}.xlsx',
    );
    if (r != null) context.read<I2cToolViewModel>().exportNewMap(map, r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width > 800;
    final form = _chipForm(cs);
    final list = _regList(cs);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 220, child: form),
          const VerticalDivider(width: 1),
          SizedBox(width: 240, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selIdx != null
                ? _editor(_selIdx!)
                : Center(
                    child: Text(
                      '← 选中寄存器后编辑',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: form),
        const Divider(height: 1),
        Expanded(child: list),
      ],
    );
  }

  Widget _chipForm(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '芯片配置',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _regs.isEmpty ? null : _export,
                child: const Text('导出Excel', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _tf('模块名称', _moduleCtrl, cs),
          Row(
            children: [
              Expanded(child: _tf('版本', _versionCtrl, cs)),
              const SizedBox(width: 8),
              Expanded(child: _tf('接口类型', _ifCtrl, cs)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _tf('速率(kHz)', _speedCtrl, cs)),
              const SizedBox(width: 8),
              Expanded(child: _tf('设备地址', _addrCtrl, cs)),
            ],
          ),
          _tf('基地址', _baseCtrl, cs),
        ],
      ),
    );
  }

  Widget _regList(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  if (_checked.length == _regs.length)
                    _checked.clear();
                  else
                    for (int i = 0; i < _regs.length; i++) _checked.add(i);
                }),
                icon: Icon(
                  _regs.isEmpty
                      ? Icons.check_box_outline_blank
                      : _checked.length == _regs.length
                      ? Icons.check_box
                      : _checked.isEmpty
                      ? Icons.check_box_outline_blank
                      : Icons.indeterminate_check_box,
                  size: 18,
                  color: cs.primary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              if (_checked.isNotEmpty)
                Text(
                  '${_checked.length}/${_regs.length}',
                  style: TextStyle(fontSize: 11, color: cs.primary),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() => _regs.add(_Reg()));
                    _cache = null;
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加寄存器', style: TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
              if (_checked.isNotEmpty) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      final s = _checked.toList()
                        ..sort((a, b) => b.compareTo(a));
                      for (final i in s) _regs.removeAt(i);
                      _checked.clear();
                      _selIdx = null;
                      _cache = null;
                    }),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(
                      '删除(${_checked.length})',
                      style: TextStyle(fontSize: 10, color: cs.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: I2cRegisterList(
            registers: _mapped,
            selectedIndex: _selIdx,
            showCheckbox: true,
            checkedIndices: _checked,
            onSelect: (i) => setState(() => _selIdx = i),
            onDoubleTap: (i) => setState(() => _selIdx = i),
            onToggleCheck: (i) => setState(
              () => _checked.contains(i) ? _checked.remove(i) : _checked.add(i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bitWidthSel(_Reg r, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('位宽', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 3),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 8,
              label: Text('8', style: TextStyle(fontSize: 11)),
            ),
            ButtonSegment(
              value: 16,
              label: Text('16', style: TextStyle(fontSize: 11)),
            ),
          ],
          selected: {r.bitWidth},
          onSelectionChanged: (v) => setState(() {
            r.bitWidth = v.first;
            _cache = null;
          }),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: WidgetStateProperty.all(const Size(36, 28)),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
          ),
        ),
      ],
    );
  }

  Widget _tf(String label, TextEditingController c, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 30,
            child: TextField(
              controller: c,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(int idx) {
    final r = _regs[idx];
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '寄存器编辑',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() {
                  _regs.removeAt(idx);
                  _selIdx = null;
                  _cache = null;
                }),
                icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _tf('寄存器名称', r.nCtrl, cs)),
              const SizedBox(width: 8),
              SizedBox(width: 90, child: _tf('偏移(Hex)', r.oCtrl, cs)),
              const SizedBox(width: 8),
              _bitWidthSel(r, cs),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '位域定义',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: r.canAddBitField
                    ? () {
                        setState(() {
                          r.addBitField();
                        });
                        _cache = null;
                      }
                    : null,
                child: Text(
                  r.canAddBitField ? '+ 添加位域' : '位域已满',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (r.f.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '暂无位域，点击添加',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...r.f.asMap().entries.map((e) {
              final b = e.value;
              return Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _tf('名称', b.nCtrl, cs)),
                        const SizedBox(width: 4),
                        SizedBox(width: 52, child: _tf('高位', b.hCtrl, cs)),
                        const SizedBox(width: 4),
                        SizedBox(width: 52, child: _tf('低位', b.lCtrl, cs)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () =>
                              setState(() => b.a = b.a == 'RW' ? 'R' : 'RW'),
                          child: Container(
                            width: 40,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: b.a == 'R'
                                    ? Colors.orange.shade300
                                    : cs.primary.withValues(alpha: 0.4),
                              ),
                              borderRadius: BorderRadius.circular(4),
                              color: b.a == 'R'
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : cs.primary.withValues(alpha: 0.06),
                            ),
                            child: Text(
                              b.a,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: b.a == 'R'
                                    ? Colors.orange.shade700
                                    : cs.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: _tf('描述', b.dCtrl, cs)),
                        IconButton(
                          onPressed: () {
                            setState(() => r.f.removeAt(e.key));
                            _cache = null;
                          },
                          icon: Icon(Icons.close, size: 14, color: cs.error),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _moduleCtrl.dispose();
    _versionCtrl.dispose();
    _ifCtrl.dispose();
    _speedCtrl.dispose();
    _addrCtrl.dispose();
    _baseCtrl.dispose();
    for (final r in _regs) r.dispose();
    super.dispose();
  }
}

class _Reg {
  final nCtrl = TextEditingController();
  final oCtrl = TextEditingController(text: '0x00');
  final List<_Bf> f = [];
  int bitWidth = 8; // 8 或 16

  /// 为新位域自动计算高位起始值（到位 0 为止）
  int _nextMsb() {
    if (f.isEmpty) return bitWidth - 1;
    int lowest = bitWidth;
    for (final bf in f) {
      final h = int.tryParse(bf.hCtrl.text.trim());
      if (h == null) continue;
      final lText = bf.lCtrl.text.trim();
      final lsb = lText.isEmpty ? h : (int.tryParse(lText) ?? h).clamp(0, h);
      if (lsb < lowest) lowest = lsb;
    }
    return lowest - 1;
  }

  bool get canAddBitField => _nextMsb() >= 0;

  _Bf? addBitField() {
    final msb = _nextMsb();
    if (msb < 0) return null;
    final bf = _Bf(msb: msb);
    f.add(bf);
    return bf;
  }

  I2cRegister get reg {
    final s = oCtrl.text.trim();
    final off = s.startsWith('0x') || s.startsWith('0X')
        ? int.tryParse(s.substring(2), radix: 16) ?? 0
        : int.tryParse(s) ?? 0;
    return I2cRegister(
      name: nCtrl.text.isEmpty ? 'REG' : nCtrl.text,
      offset: off,
      bitWidth: bitWidth,
      bitFields: f.map((x) => x.bf).toList(),
    );
  }

  void dispose() {
    nCtrl.dispose();
    oCtrl.dispose();
    for (final x in f) x.dispose();
  }
}

class _Bf {
  final nCtrl = TextEditingController();
  final hCtrl = TextEditingController();
  final lCtrl = TextEditingController();
  final dCtrl = TextEditingController();
  String a = 'RW';

  _Bf({required int msb}) {
    hCtrl.text = '$msb';
  }

  I2cRegisterBitField get bf {
    final h = int.tryParse(hCtrl.text.trim()) ?? 7;
    final lText = lCtrl.text.trim();
    final l = lText.isEmpty ? h : (int.tryParse(lText) ?? h).clamp(0, h);
    return I2cRegisterBitField(
      msb: h,
      lsb: l,
      fieldName: nCtrl.text.isEmpty ? 'FIELD' : nCtrl.text,
      access: a,
      description: dCtrl.text,
    );
  }

  void dispose() {
    nCtrl.dispose();
    hCtrl.dispose();
    lCtrl.dispose();
    dCtrl.dispose();
  }
}
