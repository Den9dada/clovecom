import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../application/app_update.dart';

/// 下载与校验完成前只写 .part 文件，失败时清理本次独立缓存目录。
class AppUpdateDownloader {
  AppUpdateDownloader({this.openRequest});

  // 测试可把逻辑上的 GitHub 请求送到本地 HTTP 服务。
  final Future<HttpClientResponse> Function(Uri)? openRequest;
  static const _maxPackageBytes = 512 * 1024 * 1024;

  Future<AppUpdatePackage> download(
    AppUpdateFeed feed,
    Directory temp, {
    bool packaged = false,
    void Function(AppUpdateProgress)? onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final directory = await temp.createTemp('clovecom-update-');
    IOSink? sink;
    try {
      Future<HttpClientResponse> request(Uri uri) async {
        for (var redirects = 0; redirects <= 5; redirects++) {
          if (uri.scheme != 'https' ||
              uri.userInfo.isNotEmpty ||
              uri.hasPort ||
              !const {
                'github.com',
                'release-assets.githubusercontent.com',
                'objects.githubusercontent.com',
              }.contains(uri.host)) {
            throw const FormatException('更新下载重定向到不受信任的地址。');
          }
          if (uri.host == 'github.com' &&
              !uri.path.startsWith(
                '/Den9dada/clovecom/releases/download/',
              )) {
            throw const FormatException('更新下载已离开指定的发行仓库。');
          }
          final response = await (() async {
            if (openRequest != null) return openRequest!(uri);
            final request = await client.getUrl(uri);
            request.followRedirects = false;
            return request.close();
          })().timeout(const Duration(seconds: 20));
          if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            if (location == null) throw const FormatException('下载重定向缺少地址。');
            await response.drain<void>().timeout(const Duration(seconds: 20));
            uri = uri.resolve(location);
            continue;
          }
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException('更新下载失败：HTTP ${response.statusCode}。');
          }
          return response;
        }
        throw const FormatException('更新下载重定向次数过多。');
      }

      final packageUri = packaged ? feed.packageUri : feed.setupUri;
      final name = packageUri.pathSegments.last;
      final sumsResponse = await request(packageUri.resolve('SHA256SUMS.txt'));
      final sumsBytes = <int>[];
      await for (final chunk in sumsResponse.timeout(
        const Duration(seconds: 30),
      )) {
        sumsBytes.addAll(chunk);
        if (sumsBytes.length > 256 * 1024) {
          throw const FormatException('更新校验清单过大。');
        }
      }
      final hashes = <String>[];
      for (final line in const LineSplitter().convert(utf8.decode(sumsBytes))) {
        final match = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line);
        if (match?.group(2) == name) hashes.add(match!.group(1)!.toLowerCase());
      }
      if (hashes.length != 1) {
        throw const FormatException('发行版缺少唯一的安装包 SHA-256 校验值。');
      }

      final response = await request(packageUri);
      final length = response.contentLength;
      if (length > _maxPackageBytes) throw const FormatException('更新安装包过大。');
      final part = File('${directory.path}/$name.part');
      sink = part.openWrite();
      var received = 0;
      var bufferedSinceFlush = 0;
      const flushThreshold = 256 * 1024;
      onProgress?.call(AppUpdateProgress(0, length > 0 ? length : null));
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        bufferedSinceFlush += chunk.length;
        if (received > _maxPackageBytes) {
          throw const FormatException('更新安装包过大。');
        }
        sink.add(chunk);
        // 按 256KB 批量等待磁盘写入，兼顾吞吐性能与内存占用上限。
        if (bufferedSinceFlush >= flushThreshold) {
          await sink.flush();
          bufferedSinceFlush = 0;
        }
        onProgress?.call(
          AppUpdateProgress(received, length > 0 ? length : null),
        );
      }
      await sink.close();
      sink = null;
      if (received == 0 || (length >= 0 && received != length)) {
        throw const FormatException('更新安装包下载不完整，请重试。');
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != hashes.single) {
        throw const FormatException('更新安装包校验失败，请重新下载。');
      }
      final file = await part.rename('${directory.path}/$name');
      return AppUpdatePackage(
        file: file,
        expectedSha256: hashes.single,
        packaged: packaged,
        version: feed.version,
      );
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {
        // 保留最初的网络或文件错误。
      }
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
