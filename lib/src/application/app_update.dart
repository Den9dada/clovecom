import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

const appUpdateFeedUrl =
    'https://den9dada.github.io/clovecom/CloveCOM.appinstaller';

/// 与 Windows 包版本一致，构建号也参与升级判断。
class AppVersion implements Comparable<AppVersion> {
  AppVersion.parse(String value) {
    if (!RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(value)) {
      throw const FormatException('版本号应包含四段数字。');
    }
    _parts = value.split('.').map(int.parse).toList(growable: false);
    if (_parts.any((part) => part > 65535)) {
      throw const FormatException('版本号超出 Windows 支持的范围。');
    }
  }

  late final List<int> _parts;

  @override
  int compareTo(AppVersion other) {
    for (var index = 0; index < _parts.length; index++) {
      final result = _parts[index].compareTo(other._parts[index]);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => _parts.join('.');
}

class InstalledApp {
  const InstalledApp({
    required this.version,
    required this.packaged,
    this.name = 'CloveCOM.Desktop',
    this.publisher,
  });

  final AppVersion version;
  final bool packaged;
  final String name;
  final String? publisher;
}

class AppUpdateFeed {
  AppUpdateFeed.parse(this.xml, InstalledApp installed) {
    final root = XmlDocument.parse(xml).rootElement;
    final packages = root.findElements('MainPackage').toList();
    if (root.name.local != 'AppInstaller' ||
        root.namespaceUri !=
            'http://schemas.microsoft.com/appx/appinstaller/2018' ||
        root.getAttribute('Uri') != appUpdateFeedUrl ||
        packages.length != 1) {
      throw const FormatException('更新清单格式无效。');
    }
    final package = packages.single;
    version = AppVersion.parse(package.getAttribute('Version') ?? '');
    final uri = Uri.parse(package.getAttribute('Uri') ?? '');
    packageUri = uri;
    if (package.getAttribute('Name') != installed.name ||
        (installed.publisher != null &&
            package.getAttribute('Publisher') != installed.publisher) ||
        package.getAttribute('ProcessorArchitecture') != 'x64' ||
        root.getAttribute('Version') != version.toString() ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith(
          '/Den9dada/clovecom/releases/download/',
        ) ||
        !uri.path.endsWith('.msix')) {
      throw const FormatException('更新清单与当前应用或发布来源不匹配。');
    }
    final parts = version.toString().split('.');
    final tag = 'v${parts.take(3).join('.')}+${parts.last}';
    if (uri.pathSegments.length != 6 || uri.pathSegments[4] != tag) {
      throw const FormatException('更新包地址与版本不一致。');
    }
    setupUri = uri.resolve('CloveCOM-$version-windows-x64-setup.exe');
  }

  final String xml;
  late final AppVersion version;
  late final Uri setupUri;
  late final Uri packageUri;
}

class AppUpdateProgress {
  const AppUpdateProgress(this.received, this.total);
  final int received;
  final int? total;
  double? get fraction => total == null || total! <= 0
      ? null
      : (received / total!).clamp(0, 1).toDouble();
}

/// 安装前发现下载产物失效，需要重新下载。
class AppUpdatePackageInvalid extends FormatException {
  const AppUpdatePackageInvalid() : super('已下载的更新包发生变化或已丢失，请重新下载。');
}

/// 固定发行摘要和安装形态，不从可变文件重新建立信任。
class AppUpdatePackage {
  const AppUpdatePackage({
    required this.file,
    required this.expectedSha256,
    required this.packaged,
    required this.version,
  });

  final File file;
  final String expectedSha256;
  final bool packaged;
  final AppVersion version;

  Future<void> verify() async {
    try {
      if (!await file.exists()) throw const AppUpdatePackageInvalid();
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != expectedSha256) {
        throw const AppUpdatePackageInvalid();
      }
    } on FileSystemException {
      // 检查存在后、读取期间消失的文件，同样需要重新下载。
      if (!await file.exists()) throw const AppUpdatePackageInvalid();
      rethrow;
    }
  }
}

abstract interface class AppUpdateHost {
  Future<InstalledApp> installedApp();
  Future<void> openInstaller(String xml);
  Future<AppUpdatePackage> download(
    AppUpdateFeed feed, {
    required bool packaged,
    void Function(AppUpdateProgress)? onProgress,
  });
  Future<void> launchInstaller(AppUpdatePackage package);
}

class AppUpdateCheck {
  const AppUpdateCheck(this.installed, this.feed);
  final InstalledApp installed;
  final AppUpdateFeed? feed;
  bool get available =>
      feed != null && feed!.version.compareTo(installed.version) > 0;
}

/// 读取固定 HTTPS 清单；MSIX 交给系统更新，其他版本下载安装程序。
class AppUpdateService {
  AppUpdateService({required this.host, this.loadFeed = fetchAppUpdateFeed});
  final AppUpdateHost host;
  final Future<String?> Function() loadFeed;

  Future<AppUpdateCheck> check() async {
    final installed = await host.installedApp();
    final xml = await loadFeed();
    return AppUpdateCheck(
      installed,
      xml == null ? null : AppUpdateFeed.parse(xml, installed),
    );
  }

  Future<AppUpdatePackage> download(
    AppUpdateCheck check, {
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    if (!check.available) throw StateError('没有可下载的更新。');
    return host.download(
      check.feed!,
      packaged: check.installed.packaged,
      onProgress: onProgress,
    );
  }

  Future<void> install(AppUpdatePackage package) async {
    await package.verify();
    await host.launchInstaller(package);
  }
}

enum AppUpdatePhase {
  idle,
  checking,
  available,
  downloading,
  ready,
  restarting,
}

enum AppUpdateInterval {
  disabled('关闭', null),
  fiveMinutes('5分钟', Duration(minutes: 5)),
  sixHours('6小时', Duration(hours: 6)),
  day('一天', Duration(days: 1)),
  week('一周', Duration(days: 7));

  const AppUpdateInterval(this.label, this.duration);
  final String label;
  final Duration? duration;
}

/// 标题栏与检查更新弹窗共用一次检查、一次下载和同一份已校验安装包。
class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    required this.service,
    this.checkInterval = AppUpdateInterval.sixHours,
    this.saveInterval,
  });

  final AppUpdateService service;
  AppUpdateInterval checkInterval;
  final Future<void> Function(AppUpdateInterval)? saveInterval;
  bool savingInterval = false;
  bool _started = false;
  AppUpdatePhase phase = AppUpdatePhase.idle;
  AppUpdateCheck? result;
  AppUpdateProgress? progress;
  Object? error;
  AppUpdatePackage? _package;
  Timer? _initialTimer;
  Timer? _periodicTimer;
  bool _disposed = false;
  bool get visible => result?.available == true;
  bool get busy => const {
    AppUpdatePhase.checking,
    AppUpdatePhase.downloading,
    AppUpdatePhase.restarting,
  }.contains(phase);

  void start({
    Duration initialDelay = const Duration(seconds: 10),
    Duration? interval,
  }) {
    if (_disposed || _started) return;
    _started = true;
    if (checkInterval == AppUpdateInterval.disabled) return;
    _initialTimer = Timer(initialDelay, () => unawaited(check()));
    _periodicTimer = Timer.periodic(
      interval ?? checkInterval.duration!,
      (_) => unawaited(check()),
    );
  }

  Future<void> setCheckInterval(AppUpdateInterval value) async {
    if (_disposed || savingInterval || value == checkInterval) return;
    savingInterval = true;
    notifyListeners();
    try {
      await saveInterval?.call(value);
      if (_disposed) return;
      checkInterval = value;
      _initialTimer?.cancel();
      _periodicTimer?.cancel();
      _periodicTimer = null;
      if (_started && value.duration != null) {
        _periodicTimer = Timer.periodic(
          value.duration!,
          (_) => unawaited(check()),
        );
      }
    } catch (failure) {
      if (_disposed) return;
      error = failure;
    }
    if (_disposed) return;
    savingInterval = false;
    notifyListeners();
  }

  Future<void> check() async {
    // 已下载的包不因后台检查被替换，也不与下载、重启并发。
    if (_disposed || busy || phase == AppUpdatePhase.ready) return;
    phase = AppUpdatePhase.checking;
    error = null;
    notifyListeners();
    try {
      final next = await service.check();
      if (_disposed) return;
      result = next;
    } catch (failure) {
      if (_disposed) return;
      error = failure;
    }
    if (_disposed) return;
    phase = visible ? AppUpdatePhase.available : AppUpdatePhase.idle;
    notifyListeners();
  }

  Future<void> download() async {
    if (_disposed || busy || !visible || phase == AppUpdatePhase.ready) return;
    phase = AppUpdatePhase.downloading;
    progress = null;
    error = null;
    notifyListeners();
    try {
      final package = await service.download(
        result!,
        onProgress: (value) {
          if (_disposed) return;
          progress = value;
          notifyListeners();
        },
      );
      if (_disposed) return;
      _package = package;
      phase = AppUpdatePhase.ready;
    } catch (failure) {
      if (_disposed) return;
      error = failure;
      phase = AppUpdatePhase.available;
    }
    notifyListeners();
  }

  Future<void> restart(Future<void> Function() exit) async {
    if (_disposed || phase != AppUpdatePhase.ready) return;
    phase = AppUpdatePhase.restarting;
    error = null;
    notifyListeners();
    try {
      await service.install(_package!);
      // 安装器成功启动后再释放连接、落盘并退出窗口。
      await exit();
    } catch (failure) {
      if (_disposed) return;
      error = failure;
      if (failure is AppUpdatePackageInvalid) {
        _package = null;
        phase = AppUpdatePhase.available;
      } else {
        phase = AppUpdatePhase.ready;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _initialTimer?.cancel();
    _periodicTimer?.cancel();
    super.dispose();
  }
}

Future<String?> fetchAppUpdateFeed() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await (() async {
      final uri = Uri.parse(appUpdateFeedUrl).replace(
        queryParameters: {'check': '${DateTime.now().millisecondsSinceEpoch}'},
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('更新服务返回 HTTP ${response.statusCode}。');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 256 * 1024) {
          throw const FormatException('更新清单过大。');
        }
      }
      return utf8.decode(bytes).replaceFirst('\uFEFF', '');
    })().timeout(const Duration(seconds: 15));
  } finally {
    client.close(force: true);
  }
}
