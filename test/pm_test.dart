import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory scratchRoot;

  setUp(() {
    scratchRoot = Directory.systemTemp.createTempSync('pm_test_');
  });

  tearDown(() {
    if (scratchRoot.existsSync()) {
      scratchRoot.deleteSync(recursive: true);
    }
  });

  group('pm CLI', () {
    test('--version prints pm package version', () async {
      final workDir = _copyFixture('basic', scratchRoot);

      final result = await _runPm(
        ['--version'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString().trim(), _readRootPackageVersion());
    });

    test('-v prints pm package version', () async {
      final workDir = _copyFixture('basic', scratchRoot);

      final result = await _runPm(
        ['-v'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString().trim(), _readRootPackageVersion());
    });

    test('set-sdk updates environment sdk constraint in current pubspec',
        () async {
      final workDir = _copyFixture('sdk_basic', scratchRoot);

      final result = await _runPm(
        ['set-sdk', '>=3.3.0 <4.0.0'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
        result.stdout.toString(),
        contains("sdk '>=3.0.0 <4.0.0' updated to '>=3.3.0 <4.0.0'"),
      );

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasSdkConstraint(content, '>=3.3.0 <4.0.0'), isTrue);
    });

    test('raise-min-sdk updates minimum sdk in recursive scan', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min-sdk', '3.4.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '>=3.4.0 <4.0.0'), isTrue);
    });

    test('raise-max-sdk updates upper sdk bound in recursive scan', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPm(
        ['raise-max-sdk', '5.0.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '>=3.0.0 <5.0.0'), isTrue);
    });

    test('sdk commands respect fail-on-parse-error', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);
      _writeMalformedPubspec(workDir, 'packages/bad/pubspec.yaml');

      final result = await _runPm(
        ['raise-min-sdk', '3.4.0', '--fail-on-parse-error', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Unable to parse'));
    });

    test('set-asdf-dart uses Dart 3 when sdk requires Dart 3', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: sdk_dart3_fixture
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
''');

      final asdfBinary = _createFakeAsdfBin(workDir, expectedVersion: '3.11.6');
      final result = await _runPm(
        ['set-asdf-dart'],
        workingDirectory: workDir.path,
        environment: {
          'PM_ASDF_BIN': asdfBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('Set Dart to 3.11.6'));
      expect(_readAsdfLog(workDir), equals('set dart 3.11.6\n'));
    });

    test('set-asdf-dart uses Dart 2 when sdk allows Dart 2', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: sdk_dart2_fixture
version: 0.0.1
environment:
  sdk: '>=2.19.0 <3.0.0'
''');

      final asdfBinary = _createFakeAsdfBin(workDir, expectedVersion: '2.19.6');
      final result = await _runPm(
        ['set-asdf-dart'],
        workingDirectory: workDir.path,
        environment: {
          'PM_ASDF_BIN': asdfBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('Set Dart to 2.19.6'));
      expect(_readAsdfLog(workDir), equals('set dart 2.19.6\n'));
    });

    test('set-asdf-dart allows overriding Dart 3 version', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: sdk_dart3_override_fixture
version: 0.0.1
environment:
  sdk: '>=3.12.0 <4.0.0'
''');

      final asdfBinary = _createFakeAsdfBin(workDir, expectedVersion: '3.12.1');
      final result = await _runPm(
        ['set-asdf-dart', '--dart-3-version', '3.12.1'],
        workingDirectory: workDir.path,
        environment: {
          'PM_ASDF_BIN': asdfBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('Set Dart to 3.12.1'));
      expect(_readAsdfLog(workDir), equals('set dart 3.12.1\n'));
    });

    test('set-asdf-dart supports recursive mode', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: sdk_recursive_set_asdf_root
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final nestedDir = Directory(p.join(workDir.path, 'packages', 'nested'))
        ..createSync(recursive: true);
      File(p.join(nestedDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sdk_recursive_set_asdf_nested
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
''');

      final asdfBinary = _createCwdLoggingAsdfBin(workDir);
      final result = await _runPm(
        ['set-asdf-dart', '-r'],
        workingDirectory: workDir.path,
        environment: {
          'PM_ASDF_BIN': asdfBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final calls = _readAsdfCwdLog(workDir)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(calls, hasLength(2));
      expect(calls.any((line) => line.endsWith(workDir.path)), isTrue);
      expect(calls.any((line) => line.endsWith(nestedDir.path)), isTrue);
    });

    test('--pub-get runs dart pub get when pubspec is modified', () async {
      final workDir = _copyFixture('basic', scratchRoot);
      final dartBinary = _createFakeDartBin(workDir);

      final result = await _runPm(
        ['set', 'path', '1.9.1', '--pub-get'],
        workingDirectory: workDir.path,
        environment: {
          'PM_DART_BIN': dartBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('Dart SDK version: fake'));
      final lines = _readDartPubGetLog(workDir)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(1));
      expect(p.basename(lines.single), equals(p.basename(workDir.path)));
    });

    test('--pub-get does not run dart pub get when pubspec is unchanged',
        () async {
      final workDir = _copyFixture('basic', scratchRoot);
      final dartBinary = _createFakeDartBin(workDir);

      final result = await _runPm(
        ['set', 'path', '^1.9.0', '--pub-get'],
        workingDirectory: workDir.path,
        environment: {
          'PM_DART_BIN': dartBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(_readDartPubGetLog(workDir), isEmpty);
    });

    test('--pubget alias runs dart pub get when pubspec is modified', () async {
      final workDir = _copyFixture('basic', scratchRoot);
      final dartBinary = _createFakeDartBin(workDir);

      final result = await _runPm(
        ['set', 'path', '1.9.1', '--pubget'],
        workingDirectory: workDir.path,
        environment: {
          'PM_DART_BIN': dartBinary.path,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final lines = _readDartPubGetLog(workDir)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(1));
      expect(p.basename(lines.single), equals(p.basename(workDir.path)));
    });

    test('set updates plain and hosted dependency styles', () async {
      final workDir = _copyFixture('basic', scratchRoot);

      final result = await _runPm(
        ['set', 'path', '1.9.1'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
          result.stdout.toString(), contains("path ^1.9.0 updated to 1.9.1"));

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(content, contains('path: 1.9.1'));
      expect(content, contains('version: 1.9.1'));
    });

    test('remove removes multiple dependencies across declaration styles',
        () async {
      final workDir = _copyFixture('remove_basic', scratchRoot);

      final result = await _runPm(
        ['remove', 'path', 'collection', 'http_parser'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_containsDependencyKey(content, 'path'), isFalse);
      expect(_containsDependencyKey(content, 'collection'), isFalse);
      expect(_containsDependencyKey(content, 'http_parser'), isFalse);
      expect(_containsDependencyKey(content, 'lints'), isTrue);
    });

    test('remove requires at least one package name', () async {
      final workDir = _copyFixture('remove_basic', scratchRoot);

      final result = await _runPm(
        ['remove'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 64);
      expect(
        result.stderr.toString(),
        contains('requires at least 1 argument: <dependency> [dependency ...]'),
      );
    });

    test('raise-min updates root fixture during recursive scan', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min', 'path', '1.9.1', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
        result.stdout.toString(),
        contains("path ^1.9.0 updated to '>=1.9.1 <2.0.0'"),
      );

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '>=1.9.1 <2.0.0'), isTrue);
    });

    test('raise-max then lower-max updates exclusive upper bound', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final raiseResult = await _runPm(
        ['raise-max', 'path', '3.0.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );
      expect(raiseResult.exitCode, 0, reason: raiseResult.stderr.toString());

      final loweredResult = await _runPm(
        ['lower-max', 'path', '2.5.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );
      expect(loweredResult.exitCode, 0,
          reason: loweredResult.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(raiseResult.stdout.toString());
      _expectUpdateOutput(loweredResult.stdout.toString());
      expect(
        loweredResult.stdout.toString(),
        contains("path '>=1.9.0 <3.0.0' updated to '>=1.9.0 <2.5.0'"),
      );

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '>=1.9.0 <2.5.0'), isTrue);
    });

    test('tighten defaults to true for dependency updates in recursive scan',
        () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min', 'path', '1.9.1', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(result.stdout.toString(), contains('updated to ^1.9.1'));

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '^1.9.1'), isTrue);
    });

    test('tighten defaults to true for sdk updates in recursive scan',
        () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min-sdk', '3.4.0', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(result.stdout.toString(), contains('sdk'));
      expect(result.stdout.toString(), contains('updated to ^3.4.0'));

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '^3.4.0'), isTrue);
    });

    test('--tighten supports 0.x caret compression', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: zero_major_fixture
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  path: '>=0.17.0 <0.19.0'
''');

      final result = await _runPm(
        ['raise-min', 'path', '0.18.2'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasConstraint(content, 'path', '^0.18.2'), isTrue);
    });

    test('--tighten keeps non-equivalent ranges as ranges', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: crossing_major_fixture
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  path: '>=1.2.3 <4.0.0'
''');

      final result = await _runPm(
        ['raise-min', 'path', '1.3.0'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasConstraint(content, 'path', '>=1.3.0 <4.0.0'), isTrue);
      expect(content, isNot(contains('path: ^1.3.0')));
    });

    test('--no-tighten opts out and preserves explicit range output', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min', 'path', '1.9.1', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasConstraint(content, 'path', '>=1.9.1 <2.0.0'), isTrue);
      expect(content, isNot(contains('path: ^1.9.1')));
    });

    test(
        'fail-on-parse-error returns non-zero when recursive scan hits malformed pubspec',
        () async {
      final workDir = _copyFixture('recursive', scratchRoot);
      _writeMalformedPubspec(workDir, 'packages/bad/pubspec.yaml');

      final result = await _runPm(
        ['set', 'path', '1.9.1', '--fail-on-parse-error', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Unable to parse'));
    });

    test('tighten raises minimums from pubspec.lock by default', () async {
      final workDir = _copyFixture('tighten_basic', scratchRoot);
      _writeTightenLockfile(workDir);

      final result = await _runPm(
        ['tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(content, 'args', '^2.3.0'), isTrue);
      expect(_hasConstraint(content, 'path', '^1.9.1'), isTrue);
      expect(_hasConstraint(content, 'version', '>=0.2.3 <1.0.0'), isTrue);
      expect(_hasConstraint(content, 'test', '^1.25.15'), isTrue);
    });

    test('tighten accepts a custom lockfile path', () async {
      final workDir = _copyFixture('tighten_basic', scratchRoot);
      final customLockPath = p.join(workDir.path, 'custom.lock');
      _writeTightenLockfile(workDir, relativePath: 'custom.lock');

      final result = await _runPm(
        ['tighten', customLockPath],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(content, 'args', '^2.3.0'), isTrue);
      expect(_hasConstraint(content, 'path', '^1.9.1'), isTrue);
      expect(_hasConstraint(content, 'version', '>=0.2.3 <1.0.0'), isTrue);
      expect(_hasConstraint(content, 'test', '^1.25.15'), isTrue);
    });

    test('tighten recursive uses each pubspec directory lockfile', () async {
      final workDir = _copyFixture('tighten_basic', scratchRoot);
      final nestedDir = Directory(p.join(workDir.path, 'packages', 'nested'))
        ..createSync(recursive: true);
      File(p.join(nestedDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: nested_tighten_fixture
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  path: '>=1.8.0 <2.0.0'
''');

      _writeTightenLockfile(workDir, pathVersion: '1.9.1');
      _writeTightenLockfile(
        nestedDir,
        pathVersion: '1.10.0',
      );

      final result = await _runPm(
        ['tighten', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());

      final rootContent =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      final nestedContent =
          File(p.join(nestedDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(rootContent, 'path', '^1.9.1'), isTrue);
      expect(_hasConstraint(nestedContent, 'path', '^1.10.0'), isTrue);
    });
  });
}

Future<void> _assertPubGetParses(String workingDirectory) async {
  final result = await Process.run('dart', ['pub', 'get'],
      workingDirectory: workingDirectory);
  expect(
    result.exitCode,
    0,
    reason:
        'dart pub get failed in $workingDirectory\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
}

Directory _copyFixture(String fixtureName, Directory parent) {
  final source = Directory(
    p.join(_repoRoot.path, 'test', 'fixtures', 'pm', fixtureName),
  );
  if (!source.existsSync()) {
    throw StateError('Fixture not found: ${source.path}');
  }

  final target = Directory(p.join(parent.path, fixtureName))
    ..createSync(recursive: true);
  _copyDirectory(source, target);
  return target;
}

Directory _writePubspecFixture(Directory parent, String pubspecContent) {
  final workDir = Directory(
      p.join(parent.path, 'custom_${DateTime.now().microsecondsSinceEpoch}'))
    ..createSync(recursive: true);
  File(p.join(workDir.path, 'pubspec.yaml'))
      .writeAsStringSync(pubspecContent.trimLeft());
  return workDir;
}

void _writeMalformedPubspec(Directory root, String relativePath) {
  File(p.join(root.path, relativePath))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: malformed_fixture
version: 0.0.1
dependencies:
  foo: ^1.0.0
  foo: ^2.0.0
''');
}

void _writeTightenLockfile(
  Directory root, {
  String relativePath = 'pubspec.lock',
  String pathVersion = '1.9.1',
}) {
  File(p.join(root.path, relativePath))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
# Generated by pub
# See https://dart.dev/tools/pub/glossary#lockfile
packages:
  args:
    dependency: "direct main"
    description:
      name: args
      sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      url: "https://pub.dev"
    source: hosted
    version: "2.3.0"
  cli_script:
    dependency: "direct main"
    description:
      name: cli_script
      sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      url: "https://pub.dev"
    source: hosted
    version: "0.2.3"
  path:
    dependency: transitive
    description:
      name: path
      sha256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
      url: "https://pub.dev"
    source: hosted
    version: "$pathVersion"
  test:
    dependency: "direct dev"
    description:
      name: test
      sha256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
      url: "https://pub.dev"
    source: hosted
    version: "1.25.15"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');
}

void _copyDirectory(Directory source, Directory target) {
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    final destinationPath = p.join(target.path, relative);

    if (entity is Directory) {
      Directory(destinationPath).createSync(recursive: true);
    } else if (entity is File) {
      File(destinationPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

Future<ProcessResult> _runPm(
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
}) {
  final packageConfig =
      p.join(_repoRoot.path, '.dart_tool', 'package_config.json');
  final script = p.join(_repoRoot.path, 'bin', 'pm.dart');

  return Process.run(
    'dart',
    ['--packages=$packageConfig', script, ...args],
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

File _createFakeAsdfBin(Directory workDir, {required String expectedVersion}) {
  final asdfScript = File(p.join(workDir.path, 'asdf_stub.sh'));
  final logPath = p.join(workDir.path, '.asdf_calls.log');

  asdfScript.writeAsStringSync('''
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' "\${1:-}" "\${2:-}" "\${3:-}" >> "$logPath"
if [[ "\${1:-}" != "set" || "\${2:-}" != "dart" || "\${3:-}" != "$expectedVersion" ]]; then
  echo "unexpected args: $expectedVersion expected" >&2
  exit 9
fi
''');
  Process.runSync('chmod', ['+x', asdfScript.path]);
  return asdfScript;
}

String _readAsdfLog(Directory workDir) {
  final logFile = File(p.join(workDir.path, '.asdf_calls.log'));
  if (!logFile.existsSync()) {
    return '';
  }
  return logFile.readAsStringSync();
}

File _createCwdLoggingAsdfBin(Directory workDir) {
  final asdfScript = File(p.join(workDir.path, 'asdf_cwd_stub.sh'));
  final logPath = p.join(workDir.path, '.asdf_cwd_calls.log');

  asdfScript.writeAsStringSync('''
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "set" || "\${2:-}" != "dart" ]]; then
  echo "unexpected args: \${1:-} \${2:-}" >&2
  exit 11
fi
pwd >> "$logPath"
''');
  Process.runSync('chmod', ['+x', asdfScript.path]);
  return asdfScript;
}

String _readAsdfCwdLog(Directory workDir) {
  final logFile = File(p.join(workDir.path, '.asdf_cwd_calls.log'));
  if (!logFile.existsSync()) {
    return '';
  }
  return logFile.readAsStringSync();
}

File _createFakeDartBin(Directory workDir) {
  final dartScript = File(p.join(workDir.path, 'dart_stub.sh'));
  final logPath = p.join(workDir.path, '.dart_pub_get_calls.log');

  dartScript.writeAsStringSync('''
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  echo "Dart SDK version: fake"
  exit 0
fi
if [[ "\${1:-}" != "pub" || "\${2:-}" != "get" ]]; then
  echo "unexpected args: \${1:-} \${2:-}" >&2
  exit 10
fi
pwd >> "$logPath"
''');
  Process.runSync('chmod', ['+x', dartScript.path]);
  return dartScript;
}

String _readDartPubGetLog(Directory workDir) {
  final logFile = File(p.join(workDir.path, '.dart_pub_get_calls.log'));
  if (!logFile.existsSync()) {
    return '';
  }
  return logFile.readAsStringSync();
}

Directory get _repoRoot => Directory.current;

String _readRootPackageVersion() {
  final content =
      File(p.join(_repoRoot.path, 'pubspec.yaml')).readAsStringSync();
  final match =
      RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(content);
  if (match == null) {
    throw StateError('Could not read version from root pubspec.yaml');
  }
  return match.group(1)!;
}

bool _hasConstraint(String content, String key, String constraint) {
  return content.contains("$key: $constraint") ||
      content.contains("$key: '$constraint'") ||
      content.contains('$key: "$constraint"');
}

bool _hasSdkConstraint(String content, String constraint) {
  return content.contains('sdk: $constraint') ||
      content.contains("sdk: '$constraint'") ||
      content.contains('sdk: "$constraint"');
}

bool _containsDependencyKey(String content, String key) {
  final matcher = RegExp('^\\s{2}${RegExp.escape(key)}:', multiLine: true);
  return matcher.hasMatch(content);
}

void _expectUpdateOutput(String stdout) {
  expect(
    stdout,
    matches(RegExp(r'^[^\s]+ .+ updated to .+$', multiLine: true)),
    reason:
        'Expected update output lines in format: <dep> <before> updated to <after>',
  );
}
