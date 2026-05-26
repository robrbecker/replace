import 'dart:io';

import 'package:args/args.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:replace/src/pm_version.dart';
import 'package:pubspec_manager/pubspec_manager.dart'
    hide Version, VersionConstraint;
import 'package:yaml/yaml.dart';

const _commandLowerMax = 'lower-max';
const _commandRaiseMax = 'raise-max';
const _commandRaiseMaxSdk = 'raise-max-sdk';
const _commandRaiseMin = 'raise-min';
const _commandRaiseMinSdk = 'raise-min-sdk';
const _commandRemove = 'remove';
const _commandSet = 'set';
const _commandSetAsdfDart = 'set-asdf-dart';
const _commandSetSdk = 'set-sdk';
const _commandTighten = 'tighten';

const _dart2Version = '2.19.6';
const _dart3Version = '3.11.6';
const _asdfExecutableEnv = 'PM_ASDF_BIN';
const _dartExecutableEnv = 'PM_DART_BIN';
const _dart3VersionOption = 'dart-3-version';

const _usageHeader = 'Usage: dart run pm <command> [arguments]';

Future<void> main(List<String> args) async {
  final exitCode = await _run(args);
  if (exitCode != 0) {
    // ignore: avoid_print
    stderr.writeln('pm failed with exit code $exitCode.');
  }
  exit(exitCode);
}

Future<int> _run(List<String> args) async {
  final parser = _buildParser();

  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    _printUsage(parser);
    return 64;
  }

  final showHelp = results['help'] as bool;
  if (showHelp) {
    _printUsage(parser);
    return 0;
  }

  final showVersion = results['version'] as bool;
  if (showVersion) {
    stdout.writeln(pmVersion);
    return 0;
  }

  final command = results.command;
  if (command == null) {
    _printUsage(parser);
    return 64;
  }

  final commandName = command.name;
  if (commandName == null) {
    _printUsage(parser);
    return 64;
  }

  final runPubGet = results['pub-get'] as bool;

  if (commandName == _commandTighten) {
    final rest = command.rest;
    if (rest.length > 1) {
      stderr.writeln(
        'Command "$commandName" accepts at most 1 argument: [lockfile_path]',
      );
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }

    final failOnParseError = results['fail-on-parse-error'] as bool;
    final recursive = results['recursive'] as bool;
    final requestedLockfilePath = rest.isEmpty ? null : rest.single.trim();
    if (requestedLockfilePath != null && requestedLockfilePath.isEmpty) {
      stderr.writeln('Lockfile path must not be empty.');
      return 64;
    }

    final pubspecFiles = _findPubspecFiles(recursive: recursive);
    if (pubspecFiles.isEmpty) {
      return 0;
    }

    var hadParseError = false;
    final changedPubspecDirectories = <String>{};
    final lockedVersionsCache = <String, Map<String, String>>{};
    for (final path in pubspecFiles) {
      final pubspecDirectory = File(path).parent;
      final lockfilePath = requestedLockfilePath == null
          ? '${pubspecDirectory.path}${Platform.pathSeparator}pubspec.lock'
          : requestedLockfilePath;
      final lockfile = File(lockfilePath);
      if (!lockfile.existsSync()) {
        if (recursive && requestedLockfilePath == null) {
          continue;
        }
        stderr.writeln('Lockfile not found: ${lockfile.path}');
        return 64;
      }

      final lockfileCacheKey = lockfile.absolute.path;
      Map<String, String> lockedVersions;
      if (lockedVersionsCache.containsKey(lockfileCacheKey)) {
        lockedVersions = lockedVersionsCache[lockfileCacheKey]!;
      } else {
        try {
          lockedVersions = _readLockedDependencyVersions(lockfile);
        } on FormatException catch (e) {
          stderr.writeln('Unable to parse ${lockfile.path}: ${e.message}');
          return 64;
        }
        lockedVersionsCache[lockfileCacheKey] = lockedVersions;
      }

      if (lockedVersions.isEmpty) {
        continue;
      }

      PubSpec pubspec;
      try {
        pubspec = PubSpec.loadFromPath(path);
      } catch (e) {
        hadParseError = true;
        stderr.writeln('Unable to parse $path: $e');
        if (failOnParseError) {
          return 1;
        }
        continue;
      }

      final before = File(path).readAsStringSync();
      final updateMessages = <String>[];

      for (final entry in lockedVersions.entries) {
        updateMessages.addAll(
          _applyToDependencies(
            pubspec.dependencies,
            entry.key,
            _Operation.raiseMin,
            entry.value,
            tighten: true,
          ),
        );
        updateMessages.addAll(
          _applyToDependencies(
            pubspec.devDependencies,
            entry.key,
            _Operation.raiseMin,
            entry.value,
            tighten: true,
          ),
        );
      }

      if (updateMessages.isEmpty) {
        continue;
      }

      final after = pubspec.toString();
      if (before == after) {
        continue;
      }

      pubspec.saveTo(path);
      changedPubspecDirectories.add(pubspecDirectory.path);
      for (final message in updateMessages) {
        stdout.writeln('$path: $message');
      }
    }

    if (failOnParseError && hadParseError) {
      return 1;
    }

    final pubGetExitCode = await _runPubGetForDirectories(
      enabled: runPubGet,
      directories: changedPubspecDirectories,
    );
    if (pubGetExitCode != 0) {
      return pubGetExitCode;
    }

    return 0;
  }

  if (commandName == _commandRemove) {
    final rest = command.rest;
    if (rest.isEmpty) {
      stderr.writeln(
        'Command "$commandName" requires at least 1 argument: <dependency> [dependency ...]',
      );
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }

    final dependencyNames = <String>[];
    for (final name in rest) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        stderr.writeln('Dependency names must not be empty.');
        return 64;
      }
      dependencyNames.add(trimmed);
    }

    final failOnParseError = results['fail-on-parse-error'] as bool;
    final recursive = results['recursive'] as bool;

    final pubspecFiles = _findPubspecFiles(recursive: recursive);
    if (pubspecFiles.isEmpty) {
      return 0;
    }

    var hadParseError = false;
    final changedPubspecDirectories = <String>{};
    for (final path in pubspecFiles) {
      PubSpec pubspec;
      try {
        pubspec = PubSpec.loadFromPath(path);
      } catch (e) {
        hadParseError = true;
        stderr.writeln('Unable to parse $path: $e');
        if (failOnParseError) {
          return 1;
        }
        continue;
      }

      final before = File(path).readAsStringSync();
      final updateMessages = _removeDependencies(pubspec, dependencyNames);

      if (updateMessages.isEmpty) {
        continue;
      }

      final after = pubspec.toString();
      if (before == after) {
        continue;
      }

      pubspec.saveTo(path);
      changedPubspecDirectories.add(File(path).parent.path);
      for (final message in updateMessages) {
        stdout.writeln('$path: $message');
      }
    }

    if (failOnParseError && hadParseError) {
      return 1;
    }

    final pubGetExitCode = await _runPubGetForDirectories(
      enabled: runPubGet,
      directories: changedPubspecDirectories,
    );
    if (pubGetExitCode != 0) {
      return pubGetExitCode;
    }

    return 0;
  }

  if (commandName == _commandSetAsdfDart) {
    final rest = command.rest;
    if (rest.isNotEmpty) {
      stderr.writeln('Command "$commandName" does not accept arguments.');
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }

    final requestedDart3Version =
        (command[_dart3VersionOption] as String).trim();
    if (requestedDart3Version.isEmpty) {
      stderr.writeln('Option --$_dart3VersionOption must not be empty.');
      return 64;
    }

    final semver.Version dart2Probe;
    final semver.Version dart3Probe;
    try {
      dart2Probe = semver.Version.parse(_dart2Version);
      dart3Probe = semver.Version.parse(requestedDart3Version);
    } on FormatException catch (e) {
      stderr.writeln(
        'Invalid version for --$_dart3VersionOption "$requestedDart3Version": ${e.message}',
      );
      return 64;
    }

    final recursive = results['recursive'] as bool;
    final failOnParseError = results['fail-on-parse-error'] as bool;
    final pubspecFiles = _findPubspecFiles(recursive: recursive);
    if (pubspecFiles.isEmpty) {
      if (recursive) {
        return 0;
      }
      final pubspecPath =
          '${Directory.current.path}${Platform.pathSeparator}pubspec.yaml';
      stderr.writeln('pubspec.yaml not found: $pubspecPath');
      return 64;
    }

    final asdfExecutable = Platform.environment[_asdfExecutableEnv] ?? 'asdf';
    var hadParseError = false;
    for (final pubspecPath in pubspecFiles) {
      final String sdkConstraintText;
      try {
        final pubspec = PubSpec.loadFromPath(pubspecPath);
        sdkConstraintText = pubspec.environment.sdk.trim();
      } catch (e) {
        hadParseError = true;
        stderr.writeln('Unable to parse $pubspecPath: $e');
        if (failOnParseError) {
          return 1;
        }
        continue;
      }

      if (sdkConstraintText.isEmpty) {
        hadParseError = true;
        stderr.writeln('$pubspecPath environment.sdk must not be empty.');
        if (failOnParseError) {
          return 1;
        }
        continue;
      }

      final semver.VersionConstraint sdkConstraint;
      try {
        sdkConstraint = semver.VersionConstraint.parse(
          _stripMatchingQuotes(sdkConstraintText),
        );
      } on FormatException catch (e) {
        hadParseError = true;
        stderr.writeln(
          'Invalid SDK constraint "$sdkConstraintText" in $pubspecPath: ${e.message}',
        );
        if (failOnParseError) {
          return 1;
        }
        continue;
      }

      final supportsDart2 = sdkConstraint.allows(dart2Probe);
      final supportsDart3 = sdkConstraint.allows(dart3Probe);

      late String dartVersionToSet;
      if (!supportsDart2 && supportsDart3) {
        dartVersionToSet = requestedDart3Version;
      } else if (supportsDart2) {
        dartVersionToSet = _dart2Version;
      } else {
        hadParseError = true;
        stderr.writeln(
          'Unable to determine Dart major from environment.sdk "$sdkConstraintText" in $pubspecPath.',
        );
        if (failOnParseError) {
          return 1;
        }
        continue;
      }

      final targetDirectory = File(pubspecPath).parent.path;
      final setResult = await Process.run(
        asdfExecutable,
        ['set', 'dart', dartVersionToSet],
        workingDirectory: targetDirectory,
      );

      final commandOutput = (setResult.stdout as String).trim();
      if (commandOutput.isNotEmpty) {
        stdout.writeln(commandOutput);
      }

      final commandError = (setResult.stderr as String).trim();
      if (commandError.isNotEmpty) {
        stderr.writeln(commandError);
      }

      if (setResult.exitCode != 0) {
        stderr.writeln(
          'Failed to run: asdf set dart $dartVersionToSet in $targetDirectory',
        );
        return setResult.exitCode;
      }

      stdout.writeln(
        'Set Dart to $dartVersionToSet in $targetDirectory based on SDK constraint $sdkConstraintText',
      );
    }

    if (failOnParseError && hadParseError) {
      return 1;
    }

    return 0;
  }

  final targetsSdk = _isSdkCommand(commandName);
  final rest = command.rest;
  late String dependencyName;
  late String versionText;
  if (targetsSdk) {
    if (rest.length != 1) {
      stderr.writeln(
        'Command "$commandName" requires exactly 1 argument: <version>',
      );
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }
    dependencyName = 'sdk';
    versionText = rest[0].trim();
    if (versionText.isEmpty) {
      stderr.writeln('Version must not be empty.');
      return 64;
    }
  } else {
    if (rest.length != 2) {
      stderr.writeln(
        'Command "$commandName" requires exactly 2 arguments: <dependency> <version>',
      );
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }

    dependencyName = rest[0].trim();
    versionText = rest[1].trim();
    if (dependencyName.isEmpty || versionText.isEmpty) {
      stderr.writeln('Dependency and version must not be empty.');
      return 64;
    }
  }

  final failOnParseError = results['fail-on-parse-error'] as bool;
  final recursive = results['recursive'] as bool;
  final tighten = results['tighten'] as bool;

  final op = _Operation.fromCommand(commandName);
  if (op == null) {
    stderr.writeln('Unknown command: $commandName');
    return 64;
  }

  if (op == _Operation.set) {
    try {
      semver.VersionConstraint.parse(versionText);
    } on FormatException catch (e) {
      stderr.writeln('Invalid version constraint "$versionText": ${e.message}');
      return 64;
    }
  } else {
    try {
      semver.Version.parse(versionText);
    } on FormatException catch (e) {
      stderr.writeln('Invalid version "$versionText": ${e.message}');
      return 64;
    }
  }

  final pubspecFiles = _findPubspecFiles(recursive: recursive);
  if (pubspecFiles.isEmpty) {
    return 0;
  }

  var hadParseError = false;
  final changedPubspecDirectories = <String>{};
  for (final path in pubspecFiles) {
    PubSpec pubspec;
    try {
      pubspec = PubSpec.loadFromPath(path);
    } catch (e) {
      hadParseError = true;
      stderr.writeln('Unable to parse $path: $e');
      if (failOnParseError) {
        return 1;
      }
      continue;
    }

    final before = File(path).readAsStringSync();

    final updateMessages = <String>[];
    if (targetsSdk) {
      updateMessages
          .addAll(_applyToSdk(pubspec, op, versionText, tighten: tighten));
    } else {
      updateMessages.addAll(
        _applyToDependencies(
          pubspec.dependencies,
          dependencyName,
          op,
          versionText,
          tighten: tighten,
        ),
      );
      updateMessages.addAll(
        _applyToDependencies(
          pubspec.devDependencies,
          dependencyName,
          op,
          versionText,
          tighten: tighten,
        ),
      );
    }

    final changed = updateMessages.isNotEmpty;

    if (!changed) {
      continue;
    }

    final after = pubspec.toString();
    if (before == after) {
      continue;
    }

    pubspec.saveTo(path);
    changedPubspecDirectories.add(File(path).parent.path);
    for (final message in updateMessages) {
      stdout.writeln('$path: $message');
    }
  }

  if (failOnParseError && hadParseError) {
    return 1;
  }

  final pubGetExitCode = await _runPubGetForDirectories(
    enabled: runPubGet,
    directories: changedPubspecDirectories,
  );
  if (pubGetExitCode != 0) {
    return pubGetExitCode;
  }

  return 0;
}

Future<int> _runPubGetForDirectories({
  required bool enabled,
  required Set<String> directories,
}) async {
  if (!enabled || directories.isEmpty) {
    return 0;
  }

  final dartExecutable = Platform.environment[_dartExecutableEnv] ?? 'dart';
  final sortedDirectories = directories.toList()..sort();
  for (final directory in sortedDirectories) {
    final versionResult = await Process.run(
      dartExecutable,
      ['--version'],
      workingDirectory: directory,
    );

    final versionOutput = (versionResult.stdout as String).trim();
    if (versionOutput.isNotEmpty) {
      stdout.writeln(versionOutput);
    }

    final versionError = (versionResult.stderr as String).trim();
    if (versionError.isNotEmpty) {
      stderr.writeln(versionError);
    }

    if (versionResult.exitCode != 0) {
      stderr.writeln('Failed to run: dart --version in $directory');
      return versionResult.exitCode;
    }

    stdout.writeln('Running dart pub get in $directory');
    final result = await Process.run(
      dartExecutable,
      ['pub', 'get'],
      workingDirectory: directory,
    );

    final commandOutput = (result.stdout as String).trim();
    if (commandOutput.isNotEmpty) {
      stdout.writeln(commandOutput);
    }

    final commandError = (result.stderr as String).trim();
    if (commandError.isNotEmpty) {
      stderr.writeln(commandError);
    }

    if (result.exitCode != 0) {
      stderr.writeln('Failed to run: dart pub get in $directory');
      return result.exitCode;
    }
  }

  return 0;
}

List<String> _applyToDependencies(
  Dependencies dependencies,
  String dependencyName,
  _Operation operation,
  String inputVersion, {
  required bool tighten,
}) {
  final dependency = dependencies[dependencyName];
  if (dependency == null) {
    return const [];
  }

  if (dependency is! DependencyVersioned) {
    return const [];
  }

  final versionedDependency = dependency as DependencyVersioned;
  final currentText = versionedDependency.versionConstraint.trim();

  if (operation == _Operation.set) {
    final nextText = _toYamlConstraint(inputVersion.trim(), currentText);
    if (nextText == currentText) {
      return const [];
    }
    versionedDependency.versionConstraint = nextText;
    return [_buildUpdateMessage(dependency.name, currentText, nextText)];
  }

  final target = semver.Version.parse(inputVersion);
  final normalizedCurrent = _stripMatchingQuotes(currentText);

  semver.VersionConstraint currentConstraint;
  try {
    currentConstraint = semver.VersionConstraint.parse(normalizedCurrent);
  } on FormatException catch (e) {
    stderr.writeln(
      'Skipping ${dependency.name}: invalid version constraint "$currentText" (${e.message})',
    );
    return const [];
  }
  final bounds = _ConstraintBounds.fromConstraint(currentConstraint);
  if (bounds == null) {
    stderr.writeln(
      'Skipping ${dependency.name}: unsupported version constraint "$currentText"',
    );
    return const [];
  }

  final nextBounds = bounds.copy();
  switch (operation) {
    case _Operation.lowerMax:
      if (_hasLowerOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMax:
      if (_hasHigherOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMin:
      if (_hasHigherOrEqualInclusiveMin(bounds, target)) {
        return const [];
      }
      nextBounds.min = target;
      nextBounds.includeMin = true;
    case _Operation.set:
      throw StateError('Unexpected operation in bounds transform.');
  }

  if (!nextBounds.isValid()) {
    stderr.writeln(
      'Skipping ${dependency.name}: resulting range would be empty (${nextBounds.toConstraintString(tighten: false)})',
    );
    return const [];
  }

  final nextText = _toYamlConstraint(
    nextBounds.toConstraintString(tighten: tighten),
    currentText,
  );
  if (nextText == currentText) {
    return const [];
  }

  versionedDependency.versionConstraint = nextText;
  return [_buildUpdateMessage(dependency.name, currentText, nextText)];
}

List<String> _applyToSdk(
  PubSpec pubspec,
  _Operation operation,
  String inputVersion, {
  required bool tighten,
}) {
  final currentText = pubspec.environment.sdk.trim();
  if (currentText.isEmpty) {
    return const [];
  }

  if (operation == _Operation.set) {
    final nextText = _toYamlConstraint(inputVersion.trim(), currentText);
    if (nextText == currentText) {
      return const [];
    }
    pubspec.environment.sdk = nextText;
    return [_buildUpdateMessage('sdk', currentText, nextText)];
  }

  final target = semver.Version.parse(inputVersion);
  final normalizedCurrent = _stripMatchingQuotes(currentText);

  semver.VersionConstraint currentConstraint;
  try {
    currentConstraint = semver.VersionConstraint.parse(normalizedCurrent);
  } on FormatException catch (e) {
    stderr.writeln(
      'Skipping sdk: invalid version constraint "$currentText" (${e.message})',
    );
    return const [];
  }

  final bounds = _ConstraintBounds.fromConstraint(currentConstraint);
  if (bounds == null) {
    stderr.writeln(
      'Skipping sdk: unsupported version constraint "$currentText"',
    );
    return const [];
  }

  final nextBounds = bounds.copy();
  switch (operation) {
    case _Operation.lowerMax:
      if (_hasLowerOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMax:
      if (_hasHigherOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMin:
      if (_hasHigherOrEqualInclusiveMin(bounds, target)) {
        return const [];
      }
      nextBounds.min = target;
      nextBounds.includeMin = true;
    case _Operation.set:
      throw StateError('Unexpected operation in bounds transform.');
  }

  if (!nextBounds.isValid()) {
    stderr.writeln(
      'Skipping sdk: resulting range would be empty (${nextBounds.toConstraintString(tighten: false)})',
    );
    return const [];
  }

  final nextText = _toYamlConstraint(
    nextBounds.toConstraintString(tighten: tighten),
    currentText,
  );
  if (nextText == currentText) {
    return const [];
  }

  pubspec.environment.sdk = nextText;
  return [_buildUpdateMessage('sdk', currentText, nextText)];
}

List<String> _removeDependencies(
  PubSpec pubspec,
  List<String> dependencyNames,
) {
  final messages = <String>[];

  for (final dependencyName in dependencyNames) {
    final inDependencies = pubspec.dependencies[dependencyName] != null;
    if (inDependencies) {
      pubspec.dependencies.remove(dependencyName);
      messages.add('$dependencyName removed from dependencies');
    }

    final inDevDependencies = pubspec.devDependencies[dependencyName] != null;
    if (inDevDependencies) {
      pubspec.devDependencies.remove(dependencyName);
      messages.add('$dependencyName removed from dev_dependencies');
    }
  }

  return messages;
}

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Print this usage information.')
    ..addFlag('version',
        abbr: 'v', negatable: false, help: 'Print the pm version and exit.')
    ..addFlag(
      'fail-on-parse-error',
      negatable: false,
      help:
          'If a pubspec.yaml cannot be parsed, fail immediately and set the exit code',
    )
    ..addFlag(
      'recursive',
      abbr: 'r',
      negatable: false,
      help: 'Recurse through subdirectories and run on all pubspec.yaml files',
    )
    ..addFlag(
      'tighten',
      defaultsTo: true,
      help:
          'When updating range constraints, rewrite equivalent ranges as caret constraints (for example >=3.0.0 <4.0.0 to ^3.0.0). Disable with --no-tighten.',
    )
    ..addFlag(
      'pub-get',
      aliases: ['pubget'],
      negatable: false,
      help:
          'Run dart pub get in each directory containing a pubspec.yaml that was modified by the command.',
    );

  for (final command in [
    _commandLowerMax,
    _commandRemove,
    _commandRaiseMax,
    _commandRaiseMaxSdk,
    _commandRaiseMin,
    _commandRaiseMinSdk,
    _commandSet,
    _commandSetAsdfDart,
    _commandSetSdk,
    _commandTighten,
  ]) {
    parser.addCommand(command);
  }

  parser.commands[_commandSetAsdfDart]?.addOption(
    _dart3VersionOption,
    defaultsTo: _dart3Version,
    help:
        'Dart 3 version to set when environment.sdk requires Dart 3 (default: $_dart3Version).',
  );

  return parser;
}

void _printUsage(ArgParser parser) {
  stdout.writeln(_usageHeader);
  stdout.writeln('');
  stdout.writeln('Global options:');
  stdout.writeln(parser.usage);
  stdout.writeln('Available commands:');
  stdout.writeln('(dependencies)');
  stdout.writeln('  set         Set the version of a dependency');
  stdout
      .writeln('  remove      Remove one or more dependencies by package name');
  stdout.writeln(
      '  lower-max   Lower the maximum allowed version (exclusive) of a dependency.');
  stdout.writeln(
      '  raise-max   Raise the maximum allowed version (exclusive) of a dependency.');
  stdout.writeln(
      '  raise-min   Raise the minimum allowed version (inclusive) of a dependency.');
  stdout.writeln('(sdk)');
  stdout.writeln(
      '  set-sdk     Set the SDK version constraint in environment.sdk.');
  stdout.writeln(
      '  set-asdf-dart Set local asdf Dart version from environment.sdk (Dart 3 -> --dart-3-version, default 3.11.6; Dart 2 -> 2.19.6).');
  stdout.writeln(
      '  raise-max-sdk Raise the maximum allowed SDK version (exclusive) in environment.sdk.');
  stdout.writeln(
      '  raise-min-sdk Raise the minimum allowed SDK version (inclusive) in environment.sdk.');
  stdout.writeln('(pubspec.yaml)');
  stdout.writeln(
      '  tighten     Raise all minimum dependency versions from pubspec.lock (or a provided lockfile path).');
}

bool _isSdkCommand(String commandName) {
  return commandName == _commandSetSdk ||
      commandName == _commandRaiseMinSdk ||
      commandName == _commandRaiseMaxSdk;
}

List<String> _findPubspecFiles({required bool recursive}) {
  final root = Directory.current;
  if (!recursive) {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    return file.existsSync() ? [file.absolute.path] : const [];
  }

  final paths = <String>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final parts = entity.path.split(Platform.pathSeparator);
    if (parts.contains('.git')) {
      continue;
    }

    if (parts.isEmpty || parts.last != 'pubspec.yaml') {
      continue;
    }
    paths.add(entity.absolute.path);
  }

  final result = paths.toList()..sort();
  return result;
}

bool _hasHigherOrEqualInclusiveMin(
  _ConstraintBounds bounds,
  semver.Version target,
) {
  final min = bounds.min;
  if (min == null) {
    return false;
  }
  final cmp = min.compareTo(target);
  if (cmp > 0) {
    return true;
  }
  if (cmp < 0) {
    return false;
  }
  return bounds.includeMin;
}

bool _hasHigherOrEqualExclusiveMax(
  _ConstraintBounds bounds,
  semver.Version target,
) {
  final max = bounds.max;
  if (max == null) {
    return false;
  }
  final cmp = max.compareTo(target);
  if (cmp > 0) {
    return true;
  }
  if (cmp < 0) {
    return false;
  }
  return !bounds.includeMax;
}

bool _hasLowerOrEqualExclusiveMax(
  _ConstraintBounds bounds,
  semver.Version target,
) {
  final max = bounds.max;
  if (max == null) {
    return false;
  }
  final cmp = max.compareTo(target);
  if (cmp < 0) {
    return true;
  }
  if (cmp > 0) {
    return false;
  }
  return !bounds.includeMax;
}

enum _Operation {
  lowerMax,
  raiseMax,
  raiseMin,
  set;

  static _Operation? fromCommand(String command) {
    switch (command) {
      case _commandLowerMax:
        return _Operation.lowerMax;
      case _commandRaiseMax:
      case _commandRaiseMaxSdk:
        return _Operation.raiseMax;
      case _commandRaiseMin:
      case _commandRaiseMinSdk:
        return _Operation.raiseMin;
      case _commandSet:
      case _commandSetSdk:
        return _Operation.set;
    }
    return null;
  }
}

class _ConstraintBounds {
  _ConstraintBounds({
    this.min,
    this.includeMin = true,
    this.max,
    this.includeMax = false,
  });

  semver.Version? min;
  bool includeMin;
  semver.Version? max;
  bool includeMax;

  static _ConstraintBounds? fromConstraint(
      semver.VersionConstraint constraint) {
    if (constraint == semver.VersionConstraint.any) {
      return _ConstraintBounds(min: null, max: null);
    }

    if (constraint is semver.Version) {
      return _ConstraintBounds(
        min: constraint,
        includeMin: true,
        max: constraint,
        includeMax: true,
      );
    }

    if (constraint is semver.VersionRange) {
      return _ConstraintBounds(
        min: constraint.min,
        includeMin: constraint.includeMin,
        max: constraint.max,
        includeMax: constraint.includeMax,
      );
    }

    return null;
  }

  _ConstraintBounds copy() => _ConstraintBounds(
        min: min,
        includeMin: includeMin,
        max: max,
        includeMax: includeMax,
      );

  bool isValid() {
    if (min == null || max == null) {
      return true;
    }
    final cmp = min!.compareTo(max!);
    if (cmp < 0) {
      return true;
    }
    if (cmp > 0) {
      return false;
    }
    return includeMin && includeMax;
  }

  String toConstraintString({required bool tighten}) {
    if (tighten) {
      final tightened = _toCaretConstraint();
      if (tightened != null) {
        return tightened;
      }
    }

    if (min == null && max == null) {
      return 'any';
    }

    if (min != null && max != null && min == max && includeMin && includeMax) {
      return min.toString();
    }

    final pieces = <String>[];
    if (min != null) {
      pieces.add('${includeMin ? '>=' : '>'}$min');
    }
    if (max != null) {
      final displayMax = includeMax ? max! : _normalizeExclusiveMax(max!);
      pieces.add('${includeMax ? '<=' : '<'}$displayMax');
    }
    return pieces.join(' ');
  }

  String? _toCaretConstraint() {
    if (min == null || max == null) {
      return null;
    }
    if (!includeMin || includeMax) {
      return null;
    }

    final minVersion = min!;
    if (minVersion.isPreRelease) {
      return null;
    }

    final expectedMax = _caretUpperBound(minVersion);
    final normalizedMax = _normalizeExclusiveMax(max!);
    if (expectedMax != normalizedMax) {
      return null;
    }

    return '^$minVersion';
  }
}

semver.Version _caretUpperBound(semver.Version version) {
  if (version.major > 0) {
    return semver.Version(version.major + 1, 0, 0);
  }
  if (version.minor > 0) {
    return semver.Version(0, version.minor + 1, 0);
  }
  return semver.Version(0, 0, version.patch + 1);
}

semver.Version _normalizeExclusiveMax(semver.Version version) {
  if (!version.isPreRelease) {
    return version;
  }

  final pre = version.preRelease;
  if (pre.length == 1 && pre.first == 0) {
    return semver.Version(version.major, version.minor, version.patch);
  }

  return version;
}

String _stripMatchingQuotes(String text) {
  if (text.length < 2) {
    return text;
  }

  final first = text[0];
  final last = text[text.length - 1];
  if ((first == '\'' || first == '"') && first == last) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}

String _toYamlConstraint(String value, String existingValue) {
  final trimmed = value.trim();
  final needsQuoting = RegExp(r'\s').hasMatch(trimmed);
  if (!needsQuoting) {
    return trimmed;
  }

  final existingTrimmed = existingValue.trim();
  final useDoubleQuote = existingTrimmed.length >= 2 &&
      existingTrimmed.startsWith('"') &&
      existingTrimmed.endsWith('"');

  if (useDoubleQuote) {
    final escaped = trimmed.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }

  final escaped = trimmed.replaceAll("'", "''");
  return "'$escaped'";
}

String _buildUpdateMessage(String name, String before, String after) {
  final beforeDisplay = _formatConstraintForMessage(before);
  final afterDisplay = _formatConstraintForMessage(after);
  return '$name $beforeDisplay updated to $afterDisplay';
}

String _formatConstraintForMessage(String value) {
  final normalized = _stripMatchingQuotes(value.trim());
  if (_looksLikeRangeConstraint(normalized)) {
    final escaped = normalized.replaceAll("'", "''");
    return "'$escaped'";
  }
  return normalized;
}

bool _looksLikeRangeConstraint(String value) {
  if (value.contains(' ') || value.contains('||')) {
    return true;
  }
  return value.startsWith('>=') ||
      value.startsWith('<=') ||
      value.startsWith('>') ||
      value.startsWith('<');
}

Map<String, String> _readLockedDependencyVersions(File lockfile) {
  final content = lockfile.readAsStringSync();
  final parsed = loadYaml(content);
  if (parsed is! YamlMap) {
    throw const FormatException('Lockfile root must be a YAML map.');
  }

  final packagesNode = parsed['packages'];
  if (packagesNode is! YamlMap) {
    throw const FormatException('Lockfile is missing a valid "packages" map.');
  }

  final versions = <String, String>{};
  for (final entry in packagesNode.entries) {
    final packageName = entry.key;
    final packageConfig = entry.value;
    if (packageName is! String || packageConfig is! YamlMap) {
      continue;
    }

    final versionValue = packageConfig['version'];
    if (versionValue is! String) {
      continue;
    }

    try {
      semver.Version.parse(versionValue.trim());
    } on FormatException {
      continue;
    }
    versions[packageName] = versionValue.trim();
  }

  final sortedKeys = versions.keys.toList()..sort();
  return {for (final key in sortedKeys) key: versions[key]!};
}
