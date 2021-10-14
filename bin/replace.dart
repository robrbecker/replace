import 'dart:io';
import 'package:cli_script/cli_script.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';

void main(List<String> args) async {
  var usage = 'replace <regexp> <replacement> <glob>';
  if (args.length < 3) {
    print(usage);
    return;
  }
  var regexp = args[0];
  var replacement = args[1];
  var glob = Glob(args[2]);

  var files = await glob
      .listFileSystem(const LocalFileSystem()).toList();
  var transformer = replace(regexp, replacement, all: true, caseSensitive: false);

  for (var f in files) {
    print(f.path);
    var contents = (await asStream(f).transform<String>(transformer).toList()).first;
    File(f.path).writeAsStringSync(contents);
  }
}

Stream<String> asStream(FileSystemEntity f) async* {
  yield await File(f.path).readAsString();
}