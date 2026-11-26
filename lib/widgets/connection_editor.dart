import 'package:material_ui/material_ui.dart';

import '../src/application/communication_runtime.dart';
import '../src/io/connections.dart';
import '../src/io/interface_params.dart';
import '../src/io/nic_scanner.dart';
import '../ui/widgets/ds_toast.dart';
import 'app_dropdown.dart';

String connectionProtocolLabel(InterfaceProtocol p) => switch (p) {
  InterfaceProtocol.tcpClient => 'TCP 客户端',
  InterfaceProtocol.tcpServer => 'TCP 服务端',
  InterfaceProtocol.udp => 'UDP',
};
const serialParityLabels = {
  '0': 'None',
  '1': 'Odd',
  '2': 'Even',
  '3': 'Mark',
  '4': 'Space',
};
const serialFlowControlLabels = {
  'none': 'None',
  'rts_cts': 'RTS/CTS',
  'dtr_dsr': 'DTR/DSR',
  'xon_xoff': 'XON/XOFF',
};

typedef ConnectionEndpoint = ({
  InterfaceKind kind,
  String address,
  String name,
});

class ConnectionEditor extends StatefulWidget {
  const ConnectionEditor({
    super.key,
    this.definition,
    required this.runtime,
    this.onError,
    this.tagColorField,
    required this.onSubmit,
    required this.builder,
  });
  final ConnectionDefinition? definition;
  final CommunicationRuntime runtime;
  final ValueChanged<Object>? onError;
  final Widget? tagColorField;
  final ValueChanged<ConnectionDefinition> onSubmit;
  final Widget Function(VoidCallback connect, Widget fields) builder;
  @override
  State<ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<ConnectionEditor>
    with SingleTickerProviderStateMixin {
  final _serialForm = GlobalKey<FormState>();
  final _networkForm = GlobalKey<FormState>();
  late final TabController _tabs;

  bool get _isSerial => _tabs.index == 0;
  final Map<String, TextEditingController> _fields = {};
  late String _networkKind;
  final _networkBindings = <String, ({String nic, String localPort})>{};
  late String _parity;
  late String _flow;
  late bool _autoReconnect;
  late bool _broadcast;
  @override
  void initState() {
    super.initState();
    final d = widget.definition;
    final serial = d?.serial;
    final isSerial = d?.isSerial ?? true;
    _networkKind = d?.protocol?.name ?? 'tcpClient';
    _tabs = TabController(
      length: 2,
      initialIndex: isSerial ? 0 : 1,
      vsync: this,
    );
    _networkBindings.addAll({
      'tcpClient': (
        nic: d?.tcpClient.nicKey ?? '',
        localPort: '${d?.tcpClient.localPort ?? 0}',
      ),
      'tcpServer': (
        nic: d?.tcpServer.nicKey ?? '',
        localPort: '${d?.tcpServer.localPort ?? 0}',
      ),
      'udp': (nic: d?.udp.nicKey ?? '', localPort: '${d?.udp.localPort ?? 0}'),
    });
    _parity = serial?.parity.toString() ?? '0';
    _flow = serial?.flowControl ?? 'none';
    _autoReconnect = d?.tcpClient.autoReconnect ?? false;
    _broadcast = d?.udp.mode == UdpMode.broadcast;
    final initial = {
      'name': d?.name ?? '',
      'port': serial?.serialPort ?? '',
      'baud': '${serial?.baudRate ?? 115200}',
      'dataBits': '${serial?.dataBits ?? 8}',
      'stopBits': '${serial?.stopBits ?? 1}',
      'nic': switch (d?.protocol) {
        InterfaceProtocol.tcpClient => d!.tcpClient.nicKey,
        InterfaceProtocol.tcpServer => d!.tcpServer.nicKey,
        InterfaceProtocol.udp => d!.udp.nicKey,
        _ => '',
      },
      'localPort':
          '${switch (d?.protocol) {
            InterfaceProtocol.tcpClient => d!.tcpClient.localPort,
            InterfaceProtocol.tcpServer => d!.tcpServer.localPort,
            InterfaceProtocol.udp => d!.udp.localPort,
            _ => 0,
          }}',
      'host': d?.tcpClient.remoteHost ?? '127.0.0.1',
      'remotePort': '${d?.tcpClient.remotePort ?? 9000}',
      'unicastHost': d?.udp.unicastHost ?? '',
      'unicastPort': '${d?.udp.unicastPort ?? 9000}',
      'broadcastHost': d?.udp.broadcastHost ?? '255.255.255.255',
      'broadcastPort': '${d?.udp.broadcastPort ?? 9000}',
    };
    for (final e in initial.entries) {
      _fields[e.key] = TextEditingController(text: e.value);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _fields[key]!.text.trim();
  int _number(String key) => int.parse(_value(key));
  String get _name {
    final name = _value('name');
    if (name.isNotEmpty) return name;
    if (_isSerial) return _value('port').toUpperCase();
    final protocol = connectionProtocolLabel(
      InterfaceProtocol.values.byName(_networkKind),
    );
    return '$protocol ${_value('nic')}'.trim();
  }

  static const double _controlHeight = 34;

  TextStyle? _fieldTextStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium;

  InputDecoration _controlDecoration(
    BuildContext context, {
    String? hintText,
    bool readOnly = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      fillColor: readOnly ? colors.surfaceContainer : null,
      constraints: const BoxConstraints(minHeight: _controlHeight),
      prefixIcon: const SizedBox.shrink(),
      prefixIconConstraints: const BoxConstraints.tightFor(
        width: 10,
        height: _controlHeight,
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
    );
  }

  Widget _labeledField(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 4),
      child,
    ],
  );

  Widget _interfaceSelector({required bool serial}) => ListenableBuilder(
    listenable: widget.runtime,
    builder: (context, _) {
      final scan = widget.runtime.interfaceScan;
      final address = _value(serial ? 'port' : 'nic');
      final options = serial
          ? <String, String>{
              for (final port in scan?.serialPorts ?? [])
                port.portName.toUpperCase(): '串口 · ${port.displayText}',
              '': '串口 · 手动输入',
            }
          : <String, String>{
              '': NicEndpoint.kAutoNicLabel,
              for (final nic in scan?.nics ?? []) nic.ip: '网卡 · ${nic.label}',
              if (address.isNotEmpty && !(scan?.containsNic(address) ?? false))
                address: '网卡 · $address',
            };
      final lookup = serial ? address.toUpperCase() : address;
      final colors = Theme.of(context).colorScheme;
      return _labeledField(
        serial ? '串口接口' : '网卡接口',
        Row(
          children: [
            Expanded(
              child: AppDropdownFormField<String>(
                key: ValueKey(
                  serial
                      ? 'connection-serial-interface'
                      : 'connection-network-interface',
                ),
                value: options.containsKey(lookup) ? lookup : '',
                style: _fieldTextStyle(context),
                decoration: const InputDecoration(
                  constraints: BoxConstraints.tightFor(height: _controlHeight),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                ),
                items: [
                  for (final option in options.entries)
                    DropdownMenuItem(
                      value: option.key,
                      child: Text(
                        option.value,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _fields[serial ? 'port' : 'nic']!.text = value);
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: _controlHeight,
              height: _controlHeight,
              child: IconButton(
                tooltip: '刷新接口列表',
                onPressed: widget.runtime.refreshInterfaceAvailability,
                style: IconButton.styleFrom(
                  backgroundColor: colors.surfaceContainerLowest,
                  side: BorderSide(color: colors.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 16),
              ),
            ),
          ],
        ),
      );
    },
  );
  void _rememberBinding() {
    _networkBindings[_networkKind] = (
      nic: _value('nic'),
      localPort: _value('localPort'),
    );
  }

  void _selectProtocol(String protocol) {
    _rememberBinding();
    _networkKind = protocol;
    final binding = _networkBindings[protocol]!;
    _fields['localPort']!.text = binding.localPort;
  }

  int _localPort(String protocol) {
    final text = _networkBindings[protocol]!.localPort;
    final port = text.isEmpty ? 0 : int.tryParse(text);
    if (port == null || !isValidLocalPort(port)) {
      throw FormatException(
        '${connectionProtocolLabel(InterfaceProtocol.values.byName(protocol))}本地端口须为 0 至 65535',
      );
    }
    return port;
  }

  Widget _field(
    String key,
    String label, {
    String? hintText,
    bool number = false,
    bool optional = false,
    bool readOnly = false,
  }) => _labeledField(
    label,
    TextFormField(
      key: ValueKey('connection-$key'),
      controller: _fields[key],
      readOnly: readOnly,
      textAlignVertical: TextAlignVertical.center,
      style: _fieldTextStyle(context),
      onChanged: key == 'port' ? (_) => setState(() {}) : null,
      decoration: _controlDecoration(
        context,
        hintText: hintText,
        readOnly: readOnly,
      ),
      keyboardType: number ? TextInputType.number : null,
      validator: (text) {
        final value = text?.trim() ?? '';
        if (value.isEmpty && !optional) return '请填写$label';
        if (number && value.isNotEmpty && int.tryParse(value) == null) {
          return '请输入整数';
        }
        return null;
      },
    ),
  );
  void _submit() {
    final form = _isSerial ? _serialForm : _networkForm;
    if (form.currentState?.validate() != true) return;
    try {
      final id =
          widget.definition?.id ??
          'connection-${DateTime.now().microsecondsSinceEpoch}';
      ConnectionDefinition d;
      if (_isSerial) {
        d = ConnectionDefinition.serial(
          ConnectionConfig(
            id: id,
            name: _name,
            protocolId: '',
            kind: TransportKind.serial,
            serialPort: _value('port').toUpperCase(),
            baudRate: _number('baud'),
            dataBits: _number('dataBits'),
            stopBits: _number('stopBits'),
            parity: int.parse(_parity),
            flowControl: _flow,
          ),
        );
        final previous = widget.definition?.serial;
        if (previous != null) {
          final values = d.serial!.toJson();
          d = ConnectionDefinition.serial(
            ConnectionConfig.fromJson({
              ...previous.toJson(),
              for (final key in [
                'name',
                'serialPort',
                'baudRate',
                'dataBits',
                'stopBits',
                'parity',
                'flowControl',
              ])
                key: values[key],
            }),
          );
        }
      } else {
        _rememberBinding();
        final p = InterfaceProtocol.values.byName(_networkKind);
        final client = TcpClientPrefs(
          nicKey: _networkBindings['tcpClient']!.nic,
          localPort: _localPort('tcpClient'),
          remoteHost: _value('host'),
          remotePort: _number('remotePort'),
          autoReconnect: _autoReconnect,
        );
        final server = TcpServerPrefs(
          nicKey: _networkBindings['tcpServer']!.nic,
          localPort: _localPort('tcpServer'),
        );
        final udp = UdpPrefs(
          nicKey: _networkBindings['udp']!.nic,
          localPort: _localPort('udp'),
          mode: _broadcast ? UdpMode.broadcast : UdpMode.unicast,
          unicastHost: _value('unicastHost'),
          unicastPort: _number('unicastPort'),
          broadcastHost: _value('broadcastHost'),
          broadcastPort: _number('broadcastPort'),
        );
        if (p == InterfaceProtocol.tcpClient && !client.hasValidTarget ||
            p == InterfaceProtocol.udp && !udp.hasValidTarget) {
          throw const FormatException('目的地址与端口无效');
        }
        d = ConnectionDefinition.network(
          id: id,
          name: _name,
          protocol: p,
          tcpClient: client,
          tcpServer: server,
          udp: udp,
        );
      }
      widget.onSubmit(d);
    } catch (error) {
      final onError = widget.onError;
      if (onError == null) {
        showDsToast('$error', kind: DsToastKind.error);
      } else {
        onError(error);
      }
    }
  }

  Widget _dropdownField({
    Key? key,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) => _labeledField(
    label,
    AppDropdownFormField<String>(
      key: key,
      value: value,
      style: _fieldTextStyle(context),
      decoration: const InputDecoration(
        constraints: BoxConstraints.tightFor(height: _controlHeight),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      ),
      items: items,
      onChanged: onChanged,
    ),
  );

  Widget _checkboxRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );

  Widget _protocolSelector() => _dropdownField(
    key: const ValueKey('connection-protocol'),
    label: '接口协议',
    value: _networkKind,
    items: [
      for (final protocol in InterfaceProtocol.values)
        DropdownMenuItem(
          value: protocol.name,
          child: Text(connectionProtocolLabel(protocol)),
        ),
    ],
    onChanged: (value) => setState(() => _selectProtocol(value!)),
  );

  List<Widget> _serialFields() => [
    _interfaceSelector(serial: true),
    const SizedBox(height: 12),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _field('port', '串口名称', hintText: '例如 COM3')),
        const SizedBox(width: 12),
        Expanded(child: _field('baud', '波特率', number: true)),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _field('dataBits', '数据位', number: true)),
        const SizedBox(width: 12),
        Expanded(child: _field('stopBits', '停止位', number: true)),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _dropdownField(
            label: '校验位',
            value: _parity,
            items: [
              for (final entry in serialParityLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _parity = value!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dropdownField(
            label: '流控',
            value: _flow,
            items: [
              for (final entry in serialFlowControlLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _flow = value!),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _networkFields() => [
    _interfaceSelector(serial: false),
    const SizedBox(height: 10),
    _protocolSelector(),
    const SizedBox(height: 10),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            'nic',
            '本地 IP',
            hintText: '自动选择',
            optional: true,
            readOnly: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _field(
            'localPort',
            '本地端口（0 或留空自动）',
            number: true,
            optional: true,
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    if (_networkKind == 'tcpClient') ...[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _field('host', '远端地址')),
          const SizedBox(width: 12),
          Expanded(child: _field('remotePort', '远端端口', number: true)),
        ],
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: _checkboxRow(
          label: '自动重连',
          value: _autoReconnect,
          onChanged: (value) => setState(() => _autoReconnect = value),
        ),
      ),
    ],
    if (_networkKind == 'udp') ...[
      Align(
        alignment: Alignment.centerLeft,
        child: _checkboxRow(
          label: 'UDP 广播',
          value: _broadcast,
          onChanged: (value) => setState(() => _broadcast = value),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _field(
              _broadcast ? 'broadcastHost' : 'unicastHost',
              '目的地址',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _field(
              _broadcast ? 'broadcastPort' : 'unicastPort',
              '目的端口',
              number: true,
            ),
          ),
        ],
      ),
    ],
  ];

  Widget _tabForm(GlobalKey<FormState> key, List<Widget> fields) => Form(
    key: key,
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: fields,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return widget.builder(
      _submit,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  'name',
                  '会话名称（可选）',
                  hintText: '留空将使用接口名称',
                  optional: true,
                ),
              ),
              if (widget.tagColorField case final field?) ...[
                const SizedBox(width: 12),
                SizedBox(width: 196, child: field),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: TabBar(
              controller: _tabs,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: theme.textTheme.labelLarge,
              unselectedLabelStyle: theme.textTheme.bodyMedium,
              labelColor: colors.onSurface,
              unselectedLabelColor: colors.onSurfaceVariant,
              indicator: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.outlineVariant),
              ),
              tabs: const [
                Tab(height: 28, text: '串口'),
                Tab(height: 28, text: '网络'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _tabForm(_serialForm, _serialFields()),
                _tabForm(_networkForm, _networkFields()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
