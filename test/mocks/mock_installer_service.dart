import 'dart:async';
import 'dart:io';
import 'package:autononext/services/installer_service.dart';
import 'package:autononext/models/install_type.dart';
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/models/tracked_deb_package.dart';

class MockInstallerService extends InstallerService {
  bool shouldFail = false;
  String? failureMessage;
  int downloadCount = 0;
  int installCount = 0;
  int uninstallCount = 0;
  int launchDebCount = 0;
  int uninstallDebCount = 0;

  /// URLs passed to [downloadFile], in order.
  final List<String> downloadedUrls = [];

  Completer<void>? _downloadGate;

  /// Makes [downloadFile] block until [releaseDownload] is called, so a test
  /// can observe the sheet while the transfer is still in flight.
  void holdDownload() => _downloadGate = Completer<void>();

  void releaseDownload() {
    final gate = _downloadGate;
    _downloadGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  final Map<String, ({String? launchCommand, String? packageName})> _installResults = {};

  void setShouldFail(bool fail, {String? message}) {
    shouldFail = fail;
    failureMessage = message;
  }

  void setInstallResult(String packageName, ({String? launchCommand, String? packageName}) result) {
    _installResults[packageName] = result;
  }

  void reset() {
    downloadCount = 0;
    installCount = 0;
    uninstallCount = 0;
    launchDebCount = 0;
    uninstallDebCount = 0;
    downloadedUrls.clear();
    _installResults.clear();
  }

  @override
  Future<File> downloadFile(String url, String filename) async {
    downloadCount++;
    downloadedUrls.add(url);
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Simulated download error');
    }
    final gate = _downloadGate;
    if (gate != null) await gate.future;
    // A path handle only — no disk I/O. Real `dart:io` futures never complete
    // inside the fake-async zone of `testWidgets`, so creating a real temp file
    // here would hang any widget test that drives an install. Nothing reads the
    // file's contents; only `file.path` is used downstream.
    return File('${Directory.systemTemp.path}/mock_download_$downloadCount/$filename');
  }

  @override
  Future<void> launchDebPackage(TrackedDebPackage pkg) async {
    launchDebCount++;
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Simulated launch error');
    }
  }

  @override
  Future<void> uninstallDebPackage(TrackedDebPackage pkg) async {
    uninstallDebCount++;
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Simulated uninstall error');
    }
  }

  @override
  Future<({String? launchCommand, String? packageName})> installPackage(
    File file,
    InstallType type, {
    String? targetPath,
    String? binaryName,
  }) async {
    installCount++;
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Simulated install error');
    }

    final packageName = file.path.split('/').last;
    if (_installResults.containsKey(packageName)) {
      return _installResults[packageName]!;
    }

    return (launchCommand: '/usr/bin/$packageName', packageName: packageName);
  }

  @override
  Future<void> uninstallPackage(TrackedApp app) async {
    uninstallCount++;
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Simulated uninstall error');
    }
  }

  @override
  Future<void> launchApp(TrackedApp app) async {
    if (shouldFail) {
      throw Exception(failureMessage ?? 'Simulated launch error');
    }
  }

  @override
  InstallType? identifyAssetType(String filename, {TrackedApp? app}) {
    if (filename.endsWith('.deb')) return InstallType.deb;
    if (filename.endsWith('.rpm')) return InstallType.rpm;
    if (filename.endsWith('.AppImage')) return InstallType.appImage;
    if (filename.contains('flatpak')) return InstallType.flatpak;
    if (filename.contains('snap')) return InstallType.snap;
    return null;
  }
}
