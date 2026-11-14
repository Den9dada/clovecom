import 'package:flutter/foundation.dart';
import '../../protocol_editor.dart';
import '../widgets/ds_toast.dart';

/// 仅提供协议页面需要的状态，不引入定位应用控制器。
class AppController extends ChangeNotifier {
  AppController(this.application) {
    application.addListener(notifyListeners);
    selectedProtocolId = application.protocolDrafts.firstOrNull?.id;
  }
  final ProtocolLibrary application;
  final protocolSelectionNotifier = ChangeNotifier();
  String? selectedProtocolId;
  String? lastError;
  List<ProtocolDraft> get protocolDrafts => application.protocolDrafts;
  ({String? operation}) get snapshot => (operation: application.operation);
  void selectProtocol(String id) {
    selectedProtocolId = id;
    protocolSelectionNotifier.notifyListeners();
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
      lastError = null;
    } catch (error) {
      lastError = '$error';
      showDsToast('$error', kind: DsToastKind.error);
    }
    notifyListeners();
  }

  Future<void> saveProtocol(String id) =>
      _perform(() => application.saveProtocol(id));
  Future<void> deleteProtocol(String id) => _perform(() async {
    await application.deleteProtocol(id);
    if (selectedProtocolId == id) {
      selectedProtocolId = protocolDrafts.firstOrNull?.id;
    }
  });
  @override
  void dispose() {
    application.removeListener(notifyListeners);
    protocolSelectionNotifier.dispose();
    super.dispose();
  }
}
