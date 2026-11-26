import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openSessionFromList(WidgetTester tester, String id) async {
  final item = find.byKey(ValueKey('session-list-$id'));
  await tester.tap(item, kind: PointerDeviceKind.mouse);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(item, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}
