import 'dart:io';
import 'package:cli_script/cli_script.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';

const bool askForConfirmation = false;
const List<String> allowedDotfiles = [
  '.gitignore',
  '.pubignore',
  '.travis.yml',
  '.travis.yaml',
];

void main(List<String> origArgs) async {
  var usage = '''replace <regexp> <replacement> <glob_file_or_dir> ...
If you specify a directory, it will match ALL files in that directory recursively. Use with caution.
''';
  var args = <String>[]..addAll(origArgs);
  if (args.length < 3) {
    print(usage);
    return;
  }
  var regexp = args.removeAt(0);
  var replacement = args.removeAt(0);
  var files = Set<String>();

  while (args.length > 0) {
    var arg = args.removeAt(0);
    var dir = Directory(arg);
    if (dir.existsSync()) {
      for (var f in dir.listSync(recursive: true)) {
        if (isFileOk(f)) {
          files.add(f.path);
        }
      }
    } else {
      try {
        for (var f in await Glob(arg, recursive: true)
            .listFileSystem(const LocalFileSystem())
            .toList()) {
          if (isFileOk(f)) {
            files.add(f.path);
          }
        }
      } catch (x) {
        print(x);
      }
    }
  }

  // Ask for confirmation
  if (askForConfirmation) {
    for (var f in files) {
      print(f);
    }
    print('Continue?');
    stdin.readLineSync();
  }

  var transformer =
      replace(regexp, replacement, all: true, caseSensitive: false);
  for (var f in files) {
    print(f);
    try {
      var contents =
          (await asStream(File(f)).transform<String>(transformer).toList())
              .first;
      File(f).writeAsStringSync(contents);
    } catch (x) {
      stderr.writeln(x);
    }
  }
}

Stream<String> asStream(FileSystemEntity f) async* {
  yield await File(f.path).readAsString();
}

bool isFileOk(FileSystemEntity f) {
  if (!(f is File)) return false;
  if (!f.existsSync()) return false;

  // skip things under the .git directory
  var pieces = f.path.split(Platform.pathSeparator);
  if (pieces.contains('.git')) return false;

  var name = pieces.last;

  // allowed dotfiles
  if (allowedDotfiles.contains(name)) return true;

  // skip other dotfiles
  if (name.startsWith('.')) return false;

  return true;
}
