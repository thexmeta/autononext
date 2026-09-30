import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:autononext/models/tracked_app.dart';
import 'package:autononext/services/install_location.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('autononext_loc_test_');
  });

  tearDown(() {
    // Restore permissions before deleting: a read-only dir cannot be removed.
    try {
      Process.runSync('chmod', ['-R', '755', tmp.path]);
    } catch (_) {}
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  TrackedApp app({
    String? launchCommand,
    String? packageName,
    String repoName = 'myrepo',
    String displayName = 'My App',
  }) {
    return TrackedApp(
      repoOwner: 'owner',
      repoName: repoName,
      displayName: displayName,
      launchCommand: launchCommand,
      packageName: packageName,
      createdAt: DateTime(2024),
    );
  }

  File makeExecutable(Directory dir, String name) {
    final file = File(p.join(dir.path, name));
    file.writeAsStringSync('#!/bin/sh\n');
    Process.runSync('chmod', ['755', file.path]);
    return file;
  }

  const resolver = InstallLocationResolver();

  test('resolve finds an executable placed on the injected PATH', () async {
    final binDir = Directory(p.join(tmp.path, 'bin'))..createSync();
    makeExecutable(binDir, 'mytool');

    final results = await resolver.resolve(
      app(repoName: 'mytool'),
      pathDirs: [binDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, hasLength(1));
    expect(
      results.single.path,
      File(p.join(binDir.path, 'mytool')).resolveSymbolicLinksSync(),
    );
    expect(results.single.source, 'PATH');
  });

  test('resolve dedupes PATH entries that reach the same file via a symlink', () async {
    final realDir = Directory(p.join(tmp.path, 'real'))..createSync();
    final linkDir = Directory(p.join(tmp.path, 'link'))..createSync();
    makeExecutable(realDir, 'mytool');
    Link(p.join(linkDir.path, 'mytool'))
        .createSync(p.join(realDir.path, 'mytool'));

    final results = await resolver.resolve(
      app(repoName: 'mytool'),
      pathDirs: [realDir.path, linkDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, hasLength(1));
  });

  test('resolve reports writable == true for a normal directory', () async {
    final binDir = Directory(p.join(tmp.path, 'bin'))..createSync();
    makeExecutable(binDir, 'mytool');

    final results = await resolver.resolve(
      app(repoName: 'mytool'),
      pathDirs: [binDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, hasLength(1));
    expect(results.single.writable, isTrue);
  });

  test('resolve reports writable == false for a read-only directory', () async {
    final readOnlyDir = Directory(p.join(tmp.path, 'ro'))..createSync();
    makeExecutable(readOnlyDir, 'mytool');
    Process.runSync('chmod', ['555', readOnlyDir.path]);
    addTearDown(() => Process.runSync('chmod', ['755', readOnlyDir.path]));

    final results = await resolver.resolve(
      app(repoName: 'mytool'),
      pathDirs: [readOnlyDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, hasLength(1));
    expect(results.single.writable, isFalse);
  });

  test('resolve marks a binary dropped in a temp dir as not package-owned', () async {
    final binDir = Directory(p.join(tmp.path, 'bin'))..createSync();
    makeExecutable(binDir, 'mytool');

    final results = await resolver.resolve(
      app(repoName: 'mytool'),
      pathDirs: [binDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, hasLength(1));
    // `dpkg -S`/`rpm -qf` must run and report no owning package, rather than
    // the field being hardcoded or the tool being skipped.
    expect(results.single.ownedByPackage, isFalse);
  });

  test('resolve prefers the launch command entry first when it exists', () async {
    final pathDir = Directory(p.join(tmp.path, 'bin'))..createSync();
    makeExecutable(pathDir, 'mytool');
    final explicit = makeExecutable(tmp, 'explicit-tool');

    final results = await resolver.resolve(
      app(launchCommand: explicit.path, repoName: 'mytool'),
      pathDirs: [pathDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, isNotEmpty);
    expect(results.first.source, 'launch command');
    expect(results.first.path, explicit.resolveSymbolicLinksSync());
  });

  test('resolve returns an empty list when nothing matches', () async {
    final emptyDir = Directory(p.join(tmp.path, 'empty'))..createSync();

    final results = await resolver.resolve(
      app(repoName: 'does-not-exist-xyz'),
      pathDirs: [emptyDir.path],
      home: p.join(tmp.path, 'home'),
    );

    expect(results, isEmpty);
  });

  test('isDirWritable answers without writing so probing leaves no stray file behind', () async {
    final dir = Directory(p.join(tmp.path, 'probe'))..createSync();
    final before =
        dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
    // A create-then-delete probe bumps the directory mtime even though it
    // removes the file again, so this detects a transient write too.
    final modifiedBefore = dir.statSync().modified;

    expect(await InstallLocationResolver.isDirWritable(dir.path), isTrue);
    // Called twice to catch a probe that creates and removes a file.
    expect(await InstallLocationResolver.isDirWritable(dir.path), isTrue);

    final after =
        dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
    expect(after, before, reason: 'writability must be a pure read');
    expect(
      dir.statSync().modified,
      modifiedBefore,
      reason: 'writability must not create or remove any directory entry',
    );
  });

  test('isDirWritable reports a chmod 555 directory as not writable', () async {
    final readOnly = Directory(p.join(tmp.path, 'ro2'))..createSync();
    Process.runSync('chmod', ['555', readOnly.path]);
    addTearDown(() => Process.runSync('chmod', ['755', readOnly.path]));

    expect(await InstallLocationResolver.isDirWritable(readOnly.path), isFalse);
  });
}
