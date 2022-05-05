# replace
Easy to use cross-platform regex replace command line util.
Can't remember the arguments to the `find` command? or how `xargs` works?
Maybe `sed` is a little different on your Mac than in Linux?

Forget all that stuff and just `replace string newval **/*.dart`

This tool is pretty basic and there aren't a lot of safeguards. It can run recursively and replace things in files that weren't intended. Use caution when replacing.
It's meant to be used in a directory under source control so you can see
what files have been changed using a diff.

It ignores dotfiles (especially the .git directory) except these
  - .gitignore
  - .pubignore
  - .travis.yml
  - .travis.yaml

If you need to replace in dotfiles other than these, you can submit a PR to this repo to
allow it or work around it by renaming the file, replacing, and renaming it back.

### Installing
`pub global activate replace`

or more advanced install
- clone the project
- `pub get`
- `dart compile exe bin/replace.dart -o replace`
- Place the `replace` executable in your path

### Running / Usage
`replace <regexp> <replacement> <glob_file_or_dir> ...`

This means you can pass as many globs, directory names, or filenames
as the 3rd and after paramter. This works nicely with glob expansion
if your shell supports it.
Example `replace aword replacementword **/*.md`

If you're having problem with your shell interpreting characters as
shell control characters, and or you need spaces in your regex or
replacement, you can use quotes and `noglob`.

Example: `noglob replace "key & peele" "ren || stimpy" **/*.md`

Regexes and globs are Dart style
Glob Syntax: https://pub.dev/packages/glob#syntax

The replacement may contain references to the capture groups in regexp using a backslash followed by the group number. Backslashes not followed by a number return the character immediately following them.

More Examples:

Simple strings and filename
`replace word "lots of words" menu.txt`

Regex and glob (w/ quotes around arguments)
`replace "(war).*(worlds)" "\1 of the monkeys" **`

Match a word at the beginning of a line
`replace "^chowder" soup menu.txt`

Match a word at the end of a line
`replace "dessert$" cookies menu.txt`
