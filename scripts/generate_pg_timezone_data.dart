import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Adapted from dpgsql's pure-Dart IANA generator so the vendored databases
// remain reproducible without package:timezone, zic, or platform FFI.

import 'package:dargres/src/utils/pg_timezone/timezone/location.dart';
import 'package:dargres/src/utils/pg_timezone/timezone/location_database.dart';
import 'package:dargres/src/utils/pg_timezone/timezone/tzdb.dart';

const _defaultTzfDir = 'scripts/data';
const _defaultOutput =
    'lib/src/utils/pg_timezone/timezone/pg_timezone_data_10y.dart';
const _defaultScope = 'latest_10y';
const _defaultTzfDownloadBase =
    'https://raw.githubusercontent.com/srawlins/timezone/master/lib/data';
const _ianaRepositoryUri = 'https://data.iana.org/time-zones';
const _compileStartYear = 1800;
const _compileEndYear = 2050;
const _millisecondsPerSecond = 1000;
const _minMillisecondsSinceEpoch = -8640000000000000;
const _maxMillisecondsSinceEpoch = 8640000000000000;

const _ianaDataFiles = <String>{
  'africa',
  'antarctica',
  'asia',
  'australasia',
  'etcetera',
  'europe',
  'factory',
  'northamerica',
  'southamerica',
  'backward',
};

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _printUsage();
    exit(options.helpRequestedExplicitly ? 0 : 64);
  }

  final locations = await _loadLocations(options);
  final output = File(options.outputPath);

  await output.parent.create(recursive: true);
  await output.writeAsString(
    _renderDatabase(
      locations,
      sourceDescription: options.sourceDescription,
    ),
  );

  stdout.writeln(
    'Generated ${locations.length} timezone locations at ${output.path}',
  );
}

Future<List<Location>> _loadLocations(_Options options) async {
  if (options.useIana) {
    final source = await _resolveIanaSource(options);
    final compiler = _IanaCompiler();
    final db = await compiler.compile(source);
    final filtered = _filterDatabase(db, options.scope);
    return filtered.locations.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  final input = await _resolveTzfInput(options);
  return tzdbDeserialize(await input.readAsBytes()).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

Future<_IanaSource> _resolveIanaSource(_Options options) async {
  if (options.ianaPath != null) {
    final path = options.ianaPath!;
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      return _IanaSource.fromDirectory(Directory(path));
    }
    if (type == FileSystemEntityType.file) {
      return _IanaSource.fromArchive(File(path));
    }
    throw FileSystemException('IANA source not found', path);
  }

  final archive = await _downloadIana(options);
  return _IanaSource.fromArchive(archive);
}

Future<File> _resolveTzfInput(_Options options) async {
  if (options.inputPath != null) {
    final input = File(options.inputPath!);
    if (!await input.exists()) {
      throw FileSystemException(
          'Input timezone database not found', input.path);
    }
    return input;
  }

  if (options.downloadTzf) {
    final url = options.downloadUrl ??
        '$_defaultTzfDownloadBase/${_scopeFilename(options.scope)}';
    final target = File(
      '${options.workDir}${Platform.pathSeparator}${_scopeFilename(options.scope)}',
    );
    await target.parent.create(recursive: true);
    await _download(url, target);
    return target;
  }

  final localInput = File(
    '$_defaultTzfDir${Platform.pathSeparator}${_scopeFilename(options.scope)}',
  );
  if (await localInput.exists()) {
    return localInput;
  }

  throw FileSystemException(
    'Timezone database not found. Pass --input, --download, --iana, '
    'or --download-iana.',
    localInput.path,
  );
}

Future<File> _downloadIana(_Options options) async {
  final version = options.ianaVersion;
  final url = options.ianaUrl ??
      (version == 'latest'
          ? '$_ianaRepositoryUri/tzdata-latest.tar.gz'
          : '$_ianaRepositoryUri/releases/tzdata$version.tar.gz');
  final filename =
      version == 'latest' ? 'tzdata-latest.tar.gz' : 'tzdata$version.tar.gz';
  final target = File('${options.workDir}${Platform.pathSeparator}$filename');
  await target.parent.create(recursive: true);
  await _download(url, target);
  return target;
}

Future<void> _download(String url, File target) async {
  stdout.writeln('Downloading $url');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Download failed with HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final sink = target.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    }
  } finally {
    client.close(force: true);
  }
}

LocationDatabase _filterDatabase(LocationDatabase db, String scope) {
  switch (scope) {
    case 'latest_all':
      return _copyDatabase(db);
    case 'latest':
      return _copyDatabase(db);
    case 'latest_10y':
      final year = DateTime.now().year;
      return _filterTimeZoneData(
        db,
        dateFrom: DateTime.utc(year - 5).millisecondsSinceEpoch,
        dateTo: DateTime.utc(year + 5).millisecondsSinceEpoch,
      ).db;
    default:
      throw ArgumentError.value(
        scope,
        'scope',
        'Use latest_all, latest, or latest_10y.',
      );
  }
}

LocationDatabase _copyDatabase(LocationDatabase db) {
  final result = LocationDatabase();
  for (final location in db.locations.values) {
    result.add(location);
  }
  return result;
}

_FilteredLocationDatabase _filterTimeZoneData(
  LocationDatabase db, {
  int dateFrom = _minMillisecondsSinceEpoch,
  int dateTo = _maxMillisecondsSinceEpoch,
}) {
  final report = _FilterReport();
  final result = LocationDatabase();

  report.originalLocationsCount = db.locations.length;

  for (final location in db.locations.values) {
    final transitionsCount = location.transitionAt.length;
    report.originalTransitionsCount += transitionsCount;

    final transitionAt = <int>[];
    final transitionZone = <int>[];

    if (transitionsCount == 0) {
      result.add(Location(
        location.name,
        transitionAt,
        transitionZone,
        location.zones,
      ));
      continue;
    }

    var i = 0;
    while (i < transitionsCount && dateFrom > location.transitionAt[i]) {
      i++;
    }

    if (i < transitionsCount) {
      transitionAt.add(_minMillisecondsSinceEpoch);
      transitionZone.add(location.transitionZone[i]);
      i++;
      report.newTransitionsCount++;

      while (i < transitionsCount && location.transitionAt[i] <= dateTo) {
        transitionAt.add(location.transitionAt[i]);
        transitionZone.add(location.transitionZone[i]);
        i++;
        report.newTransitionsCount++;
      }
    } else {
      transitionAt.add(_minMillisecondsSinceEpoch);
      transitionZone.add(location.transitionZone[i - 1]);
    }

    result.add(Location(
      location.name,
      transitionAt,
      transitionZone,
      location.zones,
    ));
    report.newLocationsCount++;
  }

  return _FilteredLocationDatabase(result, report);
}

String _renderDatabase(
  List<Location> locations, {
  required String sourceDescription,
}) {
  final buffer = StringBuffer()
    ..writeln('// dart format width=5000')
    ..writeln('// dart format off')
    ..writeln('// Generated by scripts/generate_pg_timezone_data.dart.')
    ..writeln('// Source: $sourceDescription')
    ..writeln('// Do not edit by hand.')
    ..writeln()
    ..writeln("import '../timezone.dart';")
    ..writeln()
    ..writeln('final pgDatabaseMap = <String, Location>{')
    ..writeln('  // Preserve formatting');

  for (final location in locations) {
    buffer
      ..write('  ')
      ..write(_quote(location.name))
      ..writeln(': Location(')
      ..write('    ')
      ..write(_quote(location.name))
      ..writeln(',')
      ..writeln('    ${_intList(location.transitionAt)},')
      ..writeln('    ${_intList(location.transitionZone)},')
      ..writeln('    <TimeZone>[')
      ..writeln('      // Preserve formatting');

    for (final zone in location.zones) {
      buffer
        ..write('      TimeZone(')
        ..write(zone.offset)
        ..write(', isDst: ')
        ..write(zone.isDst)
        ..write(', abbreviation: ')
        ..write(_quote(zone.abbreviation))
        ..writeln('),');
    }

    buffer
      ..writeln('    ],')
      ..writeln('  ),');
  }

  buffer.writeln('};');
  return buffer.toString();
}

String _scopeFilename(String scope) {
  switch (scope) {
    case 'latest':
    case 'latest_all':
    case 'latest_10y':
      return '$scope.tzf';
    default:
      throw ArgumentError.value(
        scope,
        'scope',
        'Use latest_all, latest, or latest_10y.',
      );
  }
}

String _intList(List<int> values) {
  final buffer = StringBuffer()
    ..writeln('<int>[')
    ..writeln('      // Preserve formatting');

  for (var i = 0; i < values.length; i += 4) {
    final end = (i + 4) > values.length ? values.length : i + 4;
    buffer
      ..write('      ')
      ..write(values.sublist(i, end).join(', '));
    if (end < values.length) {
      buffer.write(',');
    }
    buffer.writeln();
  }

  buffer.write('    ]');
  return buffer.toString();
}

String _quote(String value) {
  final escaped = value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  return "'$escaped'";
}

void _printUsage() {
  stdout.writeln('''
Generate a Dart timezone database file for dargres.

Default source:
  latest IANA tzdata downloaded from data.iana.org

Usage:
  dart run scripts/generate_pg_timezone_data.dart [options]

Options:
  --input <file>          Read a local .tzf file.
  --output <file>         Output Dart file.
                          Default: $_defaultOutput
  --scope <name>          latest_all, latest, or latest_10y.
                          Default: $_defaultScope
  --download              Download a precompiled .tzf before generating.
  --download-url <url>    Exact .tzf URL to download.
  --iana <path>           Compile an IANA source directory or tzdata tar.gz
                          archive directly in Dart, without zic.
  --download-iana         Download IANA tzdata and compile it in Dart.
  --iana-version <value>  IANA version, e.g. 2025c or latest.
                          Default: latest
  --iana-url <url>        Exact IANA tzdata tar.gz URL to download.
  --work-dir <dir>        Download/cache directory.
                          Default: scripts/.timezone
  -h, --help              Show this help.

Notes:
  With no source option, the script downloads and compiles the latest IANA
  tzdata directly in pure Dart. The default scope is latest_10y.
  Generate pg_timezone_data_all.dart with --scope latest_all when full
  historical IANA coverage is required. Use
  --download-iana to avoid zic and package:timezone completely: the script
  downloads the IANA text files, decodes Rule/Zone/Link records in Dart, and
  writes the generated Dart database used by dargres at runtime.
''');
}

final class _IanaCompiler {
  final _rules = <String, List<_Rule>>{};
  final _zones = <String, List<_ZoneEra>>{};
  final _links = <String, String>{};

  Future<LocationDatabase> compile(_IanaSource source) async {
    final files = await source.readFiles();
    for (final entry in files.entries) {
      if (_ianaDataFiles.contains(entry.key)) {
        _parseFile(entry.value);
      }
    }

    final db = LocationDatabase();
    final built = <String, Location>{};

    for (final name in _zones.keys.toList()..sort()) {
      final location = _buildLocation(name, _zones[name]!);
      built[name] = location;
      db.add(location);
    }

    for (final entry in _links.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final target = built[entry.value];
      if (target == null) {
        continue;
      }
      final alias = Location(
        entry.key,
        List<int>.from(target.transitionAt),
        List<int>.from(target.transitionZone),
        List<TimeZone>.from(target.zones),
      );
      built[entry.key] = alias;
      db.add(alias);
    }

    return db;
  }

  void _parseFile(String content) {
    String? currentZone;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = _stripComment(rawLine);
      if (line.trim().isEmpty) {
        continue;
      }

      final isContinuation = line.startsWith(' ') || line.startsWith('\t');
      final tokens = _tokenize(line);
      if (tokens.isEmpty) {
        continue;
      }

      if (isContinuation && currentZone != null) {
        _zones[currentZone]!.add(_parseZoneEra(tokens, 0));
        continue;
      }

      currentZone = null;
      switch (tokens[0]) {
        case 'Rule':
          final rule = _parseRule(tokens);
          (_rules[rule.name] ??= <_Rule>[]).add(rule);
          break;
        case 'Zone':
          if (tokens.length < 5) {
            throw FormatException('Malformed Zone line: $rawLine');
          }
          currentZone = tokens[1];
          (_zones[currentZone] ??= <_ZoneEra>[]).add(_parseZoneEra(tokens, 2));
          break;
        case 'Link':
          if (tokens.length >= 3) {
            _links[tokens[2]] = tokens[1];
          }
          break;
      }
    }
  }

  _Rule _parseRule(List<String> tokens) {
    if (tokens.length < 10) {
      throw FormatException('Malformed Rule line: ${tokens.join(' ')}');
    }

    final from = _parseYear(tokens[2], defaultMin: _compileStartYear);
    final to = tokens[3] == 'only'
        ? from
        : _parseYear(tokens[3], defaultMax: _compileEndYear);
    final at = _parseTimeSpec(tokens[7]);
    return _Rule(
      name: tokens[1],
      fromYear: from,
      toYear: to,
      month: _parseMonth(tokens[5]),
      day: _parseDaySpec(tokens[6]),
      atSeconds: at.seconds,
      atSuffix: at.suffix,
      saveSeconds: _parseDurationSeconds(tokens[8]),
      letters: tokens[9] == '-' ? '' : tokens[9],
    );
  }

  _ZoneEra _parseZoneEra(List<String> tokens, int start) {
    if (tokens.length < start + 3) {
      throw FormatException('Malformed Zone era: ${tokens.join(' ')}');
    }

    return _ZoneEra(
      gmtoffSeconds: _parseDurationSeconds(tokens[start]),
      ruleNameOrSave: tokens[start + 1],
      format: tokens[start + 2],
      until: _parseUntil(tokens.skip(start + 3).toList()),
    );
  }

  _Until? _parseUntil(List<String> tokens) {
    if (tokens.isEmpty) {
      return null;
    }

    final year = int.parse(tokens[0]);
    final month = tokens.length > 1 ? _parseMonth(tokens[1]) : 1;
    final daySpec =
        tokens.length > 2 ? _parseDaySpec(tokens[2]) : const _DaySpec.fixed(1);
    final time = tokens.length > 3
        ? _parseTimeSpec(tokens[3])
        : const _TimeSpec(0, _TimeSuffix.wall);

    return _Until(
      year: year,
      month: month,
      day: daySpec,
      seconds: time.seconds,
      suffix: time.suffix,
    );
  }

  Location _buildLocation(String name, List<_ZoneEra> eras) {
    final zones = <TimeZone>[];
    final transitions = <int>[];
    final transitionZones = <int>[];

    var eraStart = _minMillisecondsSinceEpoch;
    for (final era in eras) {
      final eraEnd = _computeEraEnd(era, eraStart);
      final builtEra = _buildEra(era, eraStart, eraEnd);

      if (builtEra.events.isEmpty) {
        _addTransition(
          transitions,
          transitionZones,
          zones,
          eraStart,
          builtEra.initialZone,
        );
      } else {
        _addTransition(
          transitions,
          transitionZones,
          zones,
          eraStart,
          builtEra.initialZone,
        );
        for (final event in builtEra.events) {
          _addTransition(
            transitions,
            transitionZones,
            zones,
            event.atMilliseconds,
            event.zone,
          );
        }
      }

      eraStart = eraEnd;
      if (eraStart >= _maxMillisecondsSinceEpoch) {
        break;
      }
    }

    if (transitions.isEmpty) {
      final era = eras.first;
      zones.add(_createZone(
        era,
        _fixedSaveSeconds(era.ruleNameOrSave),
        '',
      ));
    }

    return Location(name, transitions, transitionZones, zones);
  }

  _BuiltEra _buildEra(_ZoneEra era, int eraStart, int eraEnd) {
    if (eraEnd <= eraStart) {
      return _BuiltEra(_createZone(era, 0, ''), const <_EraEvent>[]);
    }

    if (_isFixedRule(era.ruleNameOrSave)) {
      final save = _fixedSaveSeconds(era.ruleNameOrSave);
      return _BuiltEra(
        _createZone(era, save, ''),
        const <_EraEvent>[],
      );
    }

    final rules = _rules[era.ruleNameOrSave] ?? const <_Rule>[];
    if (rules.isEmpty) {
      return _BuiltEra(_createZone(era, 0, ''), const <_EraEvent>[]);
    }

    final candidates = _ruleCandidates(rules, eraStart, eraEnd);
    var currentSave = 0;
    var currentLetters = '';

    for (final candidate in candidates) {
      final utc = _ruleUtc(candidate, era.gmtoffSeconds, currentSave);
      if (utc < eraStart) {
        currentSave = candidate.rule.saveSeconds;
        currentLetters = candidate.rule.letters;
      }
    }

    final initialZone = _createZone(era, currentSave, currentLetters);
    final events = <_EraEvent>[];

    for (final candidate in candidates) {
      final utc = _ruleUtc(candidate, era.gmtoffSeconds, currentSave);
      if (utc >= eraStart && utc < eraEnd) {
        currentSave = candidate.rule.saveSeconds;
        currentLetters = candidate.rule.letters;
        events.add(_EraEvent(
          utc,
          _createZone(era, currentSave, currentLetters),
        ));
      } else if (utc < eraStart) {
        currentSave = candidate.rule.saveSeconds;
        currentLetters = candidate.rule.letters;
      }
    }

    events.sort((a, b) => a.atMilliseconds.compareTo(b.atMilliseconds));
    return _BuiltEra(initialZone, events);
  }

  List<_RuleCandidate> _ruleCandidates(
    List<_Rule> rules,
    int eraStart,
    int eraEnd,
  ) {
    final startYear = eraStart <= _minMillisecondsSinceEpoch
        ? _compileStartYear
        : DateTime.fromMillisecondsSinceEpoch(
              eraStart,
              isUtc: true,
            ).year -
            2;
    final endYear = eraEnd >= _maxMillisecondsSinceEpoch
        ? _compileEndYear
        : DateTime.fromMillisecondsSinceEpoch(
              eraEnd,
              isUtc: true,
            ).year +
            2;

    final candidates = <_RuleCandidate>[];
    for (final rule in rules) {
      final from = rule.fromYear.clamp(startYear, endYear);
      final to = rule.toYear.clamp(startYear, endYear);
      for (var year = from; year <= to; year++) {
        candidates.add(_RuleCandidate(rule, year));
      }
    }
    candidates.sort((a, b) => a.localMilliseconds.compareTo(
          b.localMilliseconds,
        ));
    return candidates;
  }

  int _computeEraEnd(_ZoneEra era, int eraStart) {
    final until = era.until;
    if (until == null) {
      return _maxMillisecondsSinceEpoch;
    }

    final local = until.localMilliseconds;
    switch (until.suffix) {
      case _TimeSuffix.utc:
        return local;
      case _TimeSuffix.standard:
        return local - (era.gmtoffSeconds * _millisecondsPerSecond);
      case _TimeSuffix.wall:
        final save = _activeSaveAtLocal(era, local, eraStart);
        return local - ((era.gmtoffSeconds + save) * _millisecondsPerSecond);
    }
  }

  int _activeSaveAtLocal(_ZoneEra era, int local, int eraStart) {
    if (_isFixedRule(era.ruleNameOrSave)) {
      return _fixedSaveSeconds(era.ruleNameOrSave);
    }

    final rules = _rules[era.ruleNameOrSave] ?? const <_Rule>[];
    if (rules.isEmpty) {
      return 0;
    }

    var save = 0;
    final year = DateTime.fromMillisecondsSinceEpoch(local, isUtc: true).year;
    final candidates = <_RuleCandidate>[];
    for (final rule in rules) {
      final from = rule.fromYear.clamp(_compileStartYear, year + 1);
      final to = rule.toYear.clamp(_compileStartYear, year + 1);
      for (var candidateYear = from; candidateYear <= to; candidateYear++) {
        candidates.add(_RuleCandidate(rule, candidateYear));
      }
    }
    candidates.sort((a, b) => a.localMilliseconds.compareTo(
          b.localMilliseconds,
        ));

    for (final candidate in candidates) {
      final utc = _ruleUtc(candidate, era.gmtoffSeconds, save);
      if (candidate.localMilliseconds >= local || utc < eraStart) {
        continue;
      }
      save = candidate.rule.saveSeconds;
    }
    return save;
  }

  int _ruleUtc(
    _RuleCandidate candidate,
    int gmtoffSeconds,
    int currentSaveSeconds,
  ) {
    final local = candidate.localMilliseconds;
    switch (candidate.rule.atSuffix) {
      case _TimeSuffix.utc:
        return local;
      case _TimeSuffix.standard:
        return local - (gmtoffSeconds * _millisecondsPerSecond);
      case _TimeSuffix.wall:
        return local -
            ((gmtoffSeconds + currentSaveSeconds) * _millisecondsPerSecond);
    }
  }

  TimeZone _createZone(_ZoneEra era, int saveSeconds, String letters) {
    final offsetSeconds = era.gmtoffSeconds + saveSeconds;
    return TimeZone(
      offsetSeconds * _millisecondsPerSecond,
      isDst: saveSeconds != 0,
      abbreviation:
          _formatAbbreviation(era.format, saveSeconds, letters, offsetSeconds),
    );
  }

  String _formatAbbreviation(
    String format,
    int saveSeconds,
    String letters,
    int offsetSeconds,
  ) {
    if (format.contains('/')) {
      final parts = format.split('/');
      return saveSeconds == 0 ? parts.first : parts.last;
    }
    if (format.contains('%s')) {
      return format.replaceAll('%s', letters);
    }
    if (format.contains('%z')) {
      return format.replaceAll('%z', _formatOffset(offsetSeconds));
    }
    return format;
  }

  String _formatOffset(int offsetSeconds) {
    final sign = offsetSeconds < 0 ? '-' : '+';
    var value = offsetSeconds.abs();
    final hours = value ~/ 3600;
    value %= 3600;
    final minutes = value ~/ 60;
    final seconds = value % 60;
    final buffer = StringBuffer(sign)..write(hours.toString().padLeft(2, '0'));
    if (minutes != 0 || seconds != 0) {
      buffer.write(minutes.toString().padLeft(2, '0'));
    }
    if (seconds != 0) {
      buffer.write(seconds.toString().padLeft(2, '0'));
    }
    return buffer.toString();
  }

  void _addTransition(
    List<int> transitions,
    List<int> transitionZones,
    List<TimeZone> zones,
    int at,
    TimeZone zone,
  ) {
    if (transitions.isNotEmpty && transitions.last == at) {
      transitionZones.last = _zoneIndex(zones, zone);
      return;
    }
    if (transitions.isNotEmpty &&
        transitionZones.isNotEmpty &&
        zones[transitionZones.last] == zone) {
      return;
    }
    transitions.add(at);
    transitionZones.add(_zoneIndex(zones, zone));
  }

  int _zoneIndex(List<TimeZone> zones, TimeZone zone) {
    for (var i = 0; i < zones.length; i++) {
      if (zones[i] == zone) {
        return i;
      }
    }
    zones.add(zone);
    return zones.length - 1;
  }
}

final class _IanaSource {
  _IanaSource._(this._directory, this._archive);

  final Directory? _directory;
  final File? _archive;

  factory _IanaSource.fromDirectory(Directory directory) =>
      _IanaSource._(directory, null);

  factory _IanaSource.fromArchive(File archive) => _IanaSource._(null, archive);

  Future<Map<String, String>> readFiles() async {
    final directory = _directory;
    if (directory != null) {
      final result = <String, String>{};
      for (final name in _ianaDataFiles) {
        final file = File('${directory.path}${Platform.pathSeparator}$name');
        if (await file.exists()) {
          result[name] = await file.readAsString();
        }
      }
      return result;
    }

    final archive = _archive!;
    final bytes = await archive.readAsBytes();
    final decompressed = archive.path.endsWith('.gz')
        ? Uint8List.fromList(gzip.decode(bytes))
        : bytes;
    return _readTarTextFiles(decompressed, _ianaDataFiles);
  }
}

Map<String, String> _readTarTextFiles(Uint8List bytes, Set<String> names) {
  final result = <String, String>{};
  var offset = 0;
  while (offset + 512 <= bytes.length) {
    final header = bytes.sublist(offset, offset + 512);
    if (header.every((byte) => byte == 0)) {
      break;
    }

    final name = _readTarString(header, 0, 100);
    final prefix = _readTarString(header, 345, 155);
    final fullName = prefix.isEmpty ? name : '$prefix/$name';
    final baseName = fullName.split('/').last;
    final size = _readTarOctal(header, 124, 12);
    final type = header[156];

    offset += 512;
    if ((type == 0 || type == 48) && names.contains(baseName)) {
      result[baseName] = utf8.decode(bytes.sublist(offset, offset + size));
    }

    offset += ((size + 511) ~/ 512) * 512;
  }
  return result;
}

String _readTarString(Uint8List bytes, int offset, int length) {
  var end = offset;
  final max = offset + length;
  while (end < max && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(offset, end));
}

int _readTarOctal(Uint8List bytes, int offset, int length) {
  final text = _readTarString(bytes, offset, length).trim();
  if (text.isEmpty) {
    return 0;
  }
  return int.parse(text, radix: 8);
}

String _stripComment(String line) {
  final index = line.indexOf('#');
  return index == -1 ? line : line.substring(0, index);
}

List<String> _tokenize(String line) {
  return line
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
    if (part.length >= 2 && part.startsWith('"') && part.endsWith('"')) {
      return part.substring(1, part.length - 1);
    }
    return part;
  }).toList(growable: false);
}

int _parseYear(
  String value, {
  int defaultMin = _compileStartYear,
  int defaultMax = _compileEndYear,
}) {
  switch (value.toLowerCase()) {
    case 'min':
    case 'minimum':
      return defaultMin;
    case 'max':
    case 'maximum':
      return defaultMax;
    default:
      return int.parse(value);
  }
}

int _parseMonth(String value) {
  const months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final month = months[value.substring(0, 3).toLowerCase()];
  if (month == null) {
    throw FormatException('Invalid month: $value');
  }
  return month;
}

_DaySpec _parseDaySpec(String value) {
  final fixed = int.tryParse(value);
  if (fixed != null) {
    return _DaySpec.fixed(fixed);
  }

  if (value.startsWith('last')) {
    return _DaySpec.last(_parseWeekday(value.substring(4)));
  }

  final greaterOrEqual = RegExp(r'^([A-Za-z]+)>=(\d+)$').firstMatch(value);
  if (greaterOrEqual != null) {
    return _DaySpec.onOrAfter(
      _parseWeekday(greaterOrEqual.group(1)!),
      int.parse(greaterOrEqual.group(2)!),
    );
  }

  final lessOrEqual = RegExp(r'^([A-Za-z]+)<=(\d+)$').firstMatch(value);
  if (lessOrEqual != null) {
    return _DaySpec.onOrBefore(
      _parseWeekday(lessOrEqual.group(1)!),
      int.parse(lessOrEqual.group(2)!),
    );
  }

  throw FormatException('Invalid day rule: $value');
}

int _parseWeekday(String value) {
  const weekdays = <String, int>{
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };
  final weekday = weekdays[value.substring(0, 3).toLowerCase()];
  if (weekday == null) {
    throw FormatException('Invalid weekday: $value');
  }
  return weekday;
}

_TimeSpec _parseTimeSpec(String value) {
  if (value == '-') {
    return const _TimeSpec(0, _TimeSuffix.wall);
  }

  var suffix = _TimeSuffix.wall;
  var text = value;
  final last = text.codeUnitAt(text.length - 1);
  final lower = String.fromCharCode(last).toLowerCase();
  if (lower == 's' ||
      lower == 'u' ||
      lower == 'g' ||
      lower == 'z' ||
      lower == 'w') {
    text = text.substring(0, text.length - 1);
    suffix = switch (lower) {
      's' => _TimeSuffix.standard,
      'u' || 'g' || 'z' => _TimeSuffix.utc,
      _ => _TimeSuffix.wall,
    };
  }

  return _TimeSpec(_parseDurationSeconds(text), suffix);
}

int _parseDurationSeconds(String value) {
  if (value == '-' || value.isEmpty) {
    return 0;
  }

  var text = value;
  var sign = 1;
  if (text.startsWith('-')) {
    sign = -1;
    text = text.substring(1);
  } else if (text.startsWith('+')) {
    text = text.substring(1);
  }

  final parts = text.split(':').map(int.parse).toList();
  final hours = parts.isNotEmpty ? parts[0] : 0;
  final minutes = parts.length > 1 ? parts[1] : 0;
  final seconds = parts.length > 2 ? parts[2] : 0;
  return sign * ((hours * 3600) + (minutes * 60) + seconds);
}

bool _isFixedRule(String value) =>
    value == '-' || value == '0' || RegExp(r'^[+-]?\d').hasMatch(value);

int _fixedSaveSeconds(String value) =>
    value == '-' ? 0 : _parseDurationSeconds(value);

final class _Rule {
  _Rule({
    required this.name,
    required this.fromYear,
    required this.toYear,
    required this.month,
    required this.day,
    required this.atSeconds,
    required this.atSuffix,
    required this.saveSeconds,
    required this.letters,
  });

  final String name;
  final int fromYear;
  final int toYear;
  final int month;
  final _DaySpec day;
  final int atSeconds;
  final _TimeSuffix atSuffix;
  final int saveSeconds;
  final String letters;

  int localMillisecondsForYear(int year) =>
      day.localMilliseconds(year, month) + (atSeconds * _millisecondsPerSecond);
}

final class _RuleCandidate {
  _RuleCandidate(this.rule, this.year);

  final _Rule rule;
  final int year;

  int get localMilliseconds => rule.localMillisecondsForYear(year);
}

final class _ZoneEra {
  _ZoneEra({
    required this.gmtoffSeconds,
    required this.ruleNameOrSave,
    required this.format,
    required this.until,
  });

  final int gmtoffSeconds;
  final String ruleNameOrSave;
  final String format;
  final _Until? until;
}

final class _Until {
  _Until({
    required this.year,
    required this.month,
    required this.day,
    required this.seconds,
    required this.suffix,
  });

  final int year;
  final int month;
  final _DaySpec day;
  final int seconds;
  final _TimeSuffix suffix;

  int get localMilliseconds =>
      day.localMilliseconds(year, month) + (seconds * _millisecondsPerSecond);
}

final class _DaySpec {
  const _DaySpec.fixed(this.day)
      : kind = _DaySpecKind.fixed,
        weekday = 0;

  const _DaySpec.last(this.weekday)
      : kind = _DaySpecKind.last,
        day = 0;

  const _DaySpec.onOrAfter(this.weekday, this.day)
      : kind = _DaySpecKind.onOrAfter;

  const _DaySpec.onOrBefore(this.weekday, this.day)
      : kind = _DaySpecKind.onOrBefore;

  final _DaySpecKind kind;
  final int weekday;
  final int day;

  int localMilliseconds(int year, int month) {
    final resolvedDay = switch (kind) {
      _DaySpecKind.fixed => day,
      _DaySpecKind.last => _lastWeekday(year, month, weekday),
      _DaySpecKind.onOrAfter => _weekdayOnOrAfter(
          year,
          month,
          day,
          weekday,
        ),
      _DaySpecKind.onOrBefore => _weekdayOnOrBefore(
          year,
          month,
          day,
          weekday,
        ),
    };
    return DateTime.utc(year, month, resolvedDay).millisecondsSinceEpoch;
  }
}

int _lastWeekday(int year, int month, int weekday) {
  var day = DateTime.utc(year, month + 1, 0).day;
  while (DateTime.utc(year, month, day).weekday != weekday) {
    day--;
  }
  return day;
}

int _weekdayOnOrAfter(int year, int month, int day, int weekday) {
  while (DateTime.utc(year, month, day).weekday != weekday) {
    day++;
  }
  return day;
}

int _weekdayOnOrBefore(int year, int month, int day, int weekday) {
  while (DateTime.utc(year, month, day).weekday != weekday) {
    day--;
  }
  return day;
}

enum _DaySpecKind { fixed, last, onOrAfter, onOrBefore }

enum _TimeSuffix { wall, standard, utc }

final class _TimeSpec {
  const _TimeSpec(this.seconds, this.suffix);

  final int seconds;
  final _TimeSuffix suffix;
}

final class _BuiltEra {
  _BuiltEra(this.initialZone, this.events);

  final TimeZone initialZone;
  final List<_EraEvent> events;
}

final class _EraEvent {
  _EraEvent(this.atMilliseconds, this.zone);

  final int atMilliseconds;
  final TimeZone zone;
}

final class _FilterReport {
  int originalLocationsCount = 0;
  int originalTransitionsCount = 0;
  int newLocationsCount = 0;
  int newTransitionsCount = 0;
}

final class _FilteredLocationDatabase {
  _FilteredLocationDatabase(this.db, this.report);

  final LocationDatabase db;
  final _FilterReport report;
}

final class _Options {
  _Options({
    required this.inputPath,
    required this.outputPath,
    required this.scope,
    required this.downloadTzf,
    required this.downloadUrl,
    required this.ianaPath,
    required this.downloadIana,
    required this.ianaVersion,
    required this.ianaUrl,
    required this.workDir,
    required this.showHelp,
    required this.helpRequestedExplicitly,
  });

  final String? inputPath;
  final String outputPath;
  final String scope;
  final bool downloadTzf;
  final String? downloadUrl;
  final String? ianaPath;
  final bool downloadIana;
  final String ianaVersion;
  final String? ianaUrl;
  final String workDir;
  final bool showHelp;
  final bool helpRequestedExplicitly;

  bool get useIana => ianaPath != null || downloadIana || ianaUrl != null;

  String get sourceDescription {
    if (useIana) {
      if (ianaPath != null) {
        return 'IANA source $ianaPath compiled by Dart';
      }
      return '${ianaUrl ?? 'IANA tzdata $ianaVersion'} compiled by Dart';
    }
    if (inputPath != null) {
      return 'local input $inputPath';
    }
    if (downloadTzf) {
      return downloadUrl ?? '$_defaultTzfDownloadBase/${_scopeFilename(scope)}';
    }
    return 'reference $_defaultTzfDir/${_scopeFilename(scope)}';
  }

  factory _Options.parse(List<String> args) {
    String? inputPath;
    var outputPath = _defaultOutput;
    var scope = _defaultScope;
    var downloadTzf = false;
    String? downloadUrl;
    String? ianaPath;
    var downloadIana = false;
    var ianaVersion = 'latest';
    String? ianaUrl;
    var workDir = 'scripts/.timezone';
    var help = false;
    var explicitHelp = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '-h':
        case '--help':
          help = true;
          explicitHelp = true;
          break;
        case '--input':
          inputPath = _readValue(args, ++i, arg);
          break;
        case '--output':
          outputPath = _readValue(args, ++i, arg);
          break;
        case '--scope':
          scope = _readValue(args, ++i, arg);
          break;
        case '--download':
          downloadTzf = true;
          break;
        case '--download-url':
          downloadUrl = _readValue(args, ++i, arg);
          downloadTzf = true;
          break;
        case '--iana':
          ianaPath = _readValue(args, ++i, arg);
          break;
        case '--download-iana':
          downloadIana = true;
          break;
        case '--iana-version':
          ianaVersion = _readValue(args, ++i, arg);
          downloadIana = true;
          break;
        case '--iana-url':
          ianaUrl = _readValue(args, ++i, arg);
          downloadIana = true;
          break;
        case '--work-dir':
          workDir = _readValue(args, ++i, arg);
          break;
        default:
          if (arg.startsWith('-')) {
            stderr.writeln('Unknown option: $arg');
            help = true;
          } else if (inputPath == null) {
            inputPath = arg;
          } else {
            stderr.writeln('Unexpected argument: $arg');
            help = true;
          }
      }
    }

    if (!help &&
        inputPath == null &&
        !downloadTzf &&
        ianaPath == null &&
        !downloadIana &&
        ianaUrl == null) {
      downloadIana = true;
    }

    return _Options(
      inputPath: inputPath,
      outputPath: outputPath,
      scope: scope,
      downloadTzf: downloadTzf,
      downloadUrl: downloadUrl,
      ianaPath: ianaPath,
      downloadIana: downloadIana,
      ianaVersion: ianaVersion,
      ianaUrl: ianaUrl,
      workDir: workDir,
      showHelp: help,
      helpRequestedExplicitly: explicitHelp,
    );
  }

  static String _readValue(List<String> args, int index, String option) {
    if (index >= args.length) {
      throw ArgumentError('Missing value for $option');
    }
    return args[index];
  }
}
