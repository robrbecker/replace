# replace
Easy to use cross-platform regex replace command line util.
Can't remember the arguments to the `find` command? or how `xargs` works?
Maybe `sed` is a little different on your Mac than in Linux?

Forget all that stuff and just `replace string newval **/*.dart`

### Installing
`pub global activate replace`

or more advanced install
- clone the project
- `pub get`
- `dart compile exe bin/replace.dart -o replace`
- Place the `replace` executable in your path

### Running
`replace <regexp> <replacement> <glob>`

Regexes and globs are Dart style
Glob Syntax: https://pub.dev/packages/glob#syntax

The replacement may contain references to the capture groups in regexp using a backslash followed by the group number. Backslashes not followed by a number return the character immediately following them.

Examples:

Simple strings and filename
`replace word newword filename`

Regex and glob (w/ quotes around arguments)
`replace "(war).*(worlds)" "\1 of the monkeys" **`

### Developing
This project uses cider to maintain the changelog. 

`cider log <type> <description>`
type is one of: added, changed, deprecated, removed, fixed, security

Examples:
```
cider log changed 'New turbo V6 engine installed'
cider log added 'Support for rocket fuel and kerosene'
cider log fixed 'Wheels falling off sporadically'
```

When ready to release just run

`cider bump <part>` (part is major, minor, patch)
and
`cider release`
