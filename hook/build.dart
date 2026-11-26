// 仅供构建 hook 使用的包保留为开发依赖，不进入应用运行时依赖声明。
// ignore_for_file: depend_on_referenced_packages
// CloveCOM：声明系统 Winsock DLL；不编译、下载或分发原生库。
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets ||
        input.config.code.targetOS != OS.windows) {
      return;
    }
    output.assets.code.add(
      CodeAsset(
        package: 'clovecom',
        name: 'src/third_party/windows_winsock.g.dart',
        linkMode: DynamicLoadingSystem(Uri.file('ws2_32.dll')),
      ),
    );
  });
}
