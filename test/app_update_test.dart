import 'dart:convert';
import 'dart:io';

import 'package:clovecom/src/application/app_update.dart';
import 'package:clovecom/src/io/app_update_download.dart';
import 'package:clovecom/src/io/app_update_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _feedXml({
  String version = '1.0.1.2',
  String tag = 'v1.0.1+2',
  String name = 'CloveCOM.Desktop',
  String publisher = 'CN=CloveCOM',
  String repo = 'Den9dada/clovecom',
}) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="$version" Uri="$appUpdateFeedUrl">
  <MainPackage Name="$name" Publisher="$publisher" Version="$version"
      ProcessorArchitecture="x64"
      Uri="https://github.com/$repo/releases/download/$tag/CloveCOM-$version-windows-x64.msix" />
</AppInstaller>
''';

class _FakeHost implements AppUpdateHost {
  _FakeHost({required this.installed, this.onDownload});

  final InstalledApp installed;
  final Future<AppUpdatePackage> Function(
    AppUpdateFeed feed,
    bool packaged,
    void Function(AppUpdateProgress)? onProgress,
  )?
  onDownload;
  int launchCount = 0;

  @override
  Future<InstalledApp> installedApp() async => installed;

  @override
  Future<void> openInstaller(String xml) async {}

  @override
  Future<AppUpdatePackage> download(
    AppUpdateFeed feed, {
    required bool packaged,
    void Function(AppUpdateProgress)? onProgress,
  }) => onDownload!(feed, packaged, onProgress);

  @override
  Future<void> launchInstaller(AppUpdatePackage package) async {
    launchCount++;
  }
}

void main() {
  group('AppVersion', () {
    test('按四段数字顺序比较版本号与构建号', () {
      expect(
        AppVersion.parse('1.0.0.1').compareTo(AppVersion.parse('1.0.0.2')),
        lessThan(0),
      );
      expect(
        AppVersion.parse('1.2.0.0').compareTo(AppVersion.parse('1.1.9.9')),
        greaterThan(0),
      );
      expect(
        AppVersion.parse('1.0.0.1').compareTo(AppVersion.parse('1.0.0.1')),
        0,
      );
    });

    test('拒绝非法格式或超出范围的版本号', () {
      expect(() => AppVersion.parse('1.0.0'), throwsFormatException);
      expect(() => AppVersion.parse('1.0.0.65536'), throwsFormatException);
    });
  });

  group('AppUpdateFeed', () {
    test('解析合法清单并推导出 setup.exe 地址', () {
      final installed = InstalledApp(
        version: AppVersion.parse('1.0.0.1'),
        packaged: false,
      );
      final feed = AppUpdateFeed.parse(_feedXml(), installed);
      expect(feed.version.toString(), '1.0.1.2');
      expect(
        feed.setupUri.toString(),
        'https://github.com/Den9dada/clovecom/releases/download/v1.0.1+2/CloveCOM-1.0.1.2-windows-x64-setup.exe',
      );
    });

    test('拒绝仓库来源或标签不一致的清单', () {
      final installed = InstalledApp(
        version: AppVersion.parse('1.0.0.1'),
        packaged: false,
      );
      expect(
        () => AppUpdateFeed.parse(
          _feedXml(repo: 'evil/clovecom-releases'),
          installed,
        ),
        throwsFormatException,
      );
      expect(
        () => AppUpdateFeed.parse(_feedXml(tag: 'v1.0.1+9'), installed),
        throwsFormatException,
      );
    });
  });

  group('AppUpdatePreferences', () {
    test('读写检查间隔并在文件缺失或损坏时回退默认值', () async {
      final dir = await Directory.systemTemp.createTemp('clovecom-pref-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/update_preferences.json');
      final prefs = AppUpdatePreferences(file);

      expect(await prefs.load(), AppUpdateInterval.sixHours);

      await prefs.save(AppUpdateInterval.day);
      expect(await prefs.load(), AppUpdateInterval.day);

      await file.writeAsString('{broken json');
      expect(await prefs.load(), AppUpdateInterval.sixHours);
    });
  });

  group('AppUpdateDownloader & Controller', () {
    test('通过本地 HTTP 下载并完成 SHA-256 校验与重启交接', () async {
      final payload = utf8.encode('fake-setup-installer-bytes');
      final expectedHash = sha256.convert(payload).toString();
      const setupName = 'CloveCOM-1.0.1.2-windows-x64-setup.exe';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) {
        if (req.uri.path.endsWith('/SHA256SUMS.txt')) {
          req.response
            ..statusCode = HttpStatus.ok
            ..write('$expectedHash  $setupName\n');
        } else if (req.uri.path.endsWith('/$setupName')) {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentLength = payload.length
            ..add(payload);
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        req.response.close();
      });

      final temp = await Directory.systemTemp.createTemp('clovecom-dl-test-');
      addTearDown(() => temp.delete(recursive: true));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final downloader = AppUpdateDownloader(
        openRequest: (uri) async {
          final localUri = Uri.http(
            '${server.address.address}:${server.port}',
            uri.path,
          );
          final req = await client.getUrl(localUri);
          req.followRedirects = false;
          return req.close();
        },
      );

      final host = _FakeHost(
        installed: InstalledApp(
          version: AppVersion.parse('1.0.0.1'),
          packaged: false,
        ),
        onDownload: (feed, packaged, onProgress) => downloader.download(
          feed,
          temp,
          packaged: packaged,
          onProgress: onProgress,
        ),
      );

      final controller = AppUpdateController(
        service: AppUpdateService(host: host, loadFeed: () async => _feedXml()),
      );
      addTearDown(controller.dispose);

      await controller.check();
      expect(controller.phase, AppUpdatePhase.available);
      expect(controller.visible, isTrue);

      await controller.download();
      expect(controller.phase, AppUpdatePhase.ready);

      var exited = false;
      await controller.restart(() async => exited = true);
      expect(host.launchCount, 1);
      expect(exited, isTrue);
    });
  });
}
