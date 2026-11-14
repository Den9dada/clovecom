import 'package:flutter/foundation.dart';
import '../../protocol_editor.dart';
import '../widgets/ds_dialog.dart';
import '../widgets/ds_toast.dart';

/// 仅提供协议页面需要的状态，不引入定位应用控制器。
class AppController extends ChangeNotifier {
  AppController(this.application) {
    application.addListener(notifyListeners);
    _action.addListener(notifyListeners);
    selectedProtocolId = application.protocolDrafts.firstOrNull?.id;
  }
  final ProtocolLibrary application;

  /// 协议操作（保存/删除互斥）共用的异步反馈深模块：内化防重入、
  /// 清旧错、错误保留与销毁守卫；瞬态呈现经 onFailed 注入 Toast 适配器。
  final _action = DsDialogAction();
  final protocolSelectionNotifier = ChangeNotifier();
  String? selectedProtocolId;
  String? get lastError => _action.error;
  List<ProtocolDraft> get protocolDrafts => application.protocolDrafts;
  ({String? operation}) get snapshot => (operation: application.operation);
  void selectProtocol(String id) {
    selectedProtocolId = id;
    protocolSelectionNotifier.notifyListeners();
  }

  Future<void> _perform(Future<void> Function() action) => _action.run(
    action,
    onFailed: (error) => showDsToast('$error', kind: DsToastKind.error),
  );

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
    _action.removeListener(notifyListeners);
    _action.dispose();
    protocolSelectionNotifier.dispose();
    super.dispose();
  }
}
