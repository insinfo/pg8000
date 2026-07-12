import 'dart:convert';
import 'dart:io';

import 'package:dargres/dargres.dart' as dargres;
import 'package:postgres_fork/postgres.dart' as postgres_fork;

const _dargresQuery = r'''
SELECT id, account_id, score, active, label, created_at
FROM dargres_driver_benchmark.driver_rows
WHERE id <= $1
ORDER BY id
''';

const _postgresForkQuery = r'''
SELECT id, account_id, score, active, label, created_at
FROM dargres_driver_benchmark.driver_rows
WHERE id <= @limit:int4
ORDER BY id
''';

int _blackHole = 0;

Future<void> main(List<String> arguments) async {
  try {
    final options = BenchmarkOptions.parse(arguments, Platform.environment);
    if (options.showHelp) {
      stdout.write(BenchmarkOptions.usage);
      return;
    }

    final factories = _selectedDrivers(options);
    if (options.setup || options.setupOnly) {
      await _installSchema(options, factories.first);
      stderr.writeln('Schema deterministico instalado.');
    }
    if (options.setupOnly) return;

    final report = await BenchmarkRunner(options, factories).run();
    final json = const JsonEncoder.withIndent('  ').convert(report);
    if (options.outputPath == null || options.outputPath == '-') {
      stdout.writeln(json);
    } else {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString('$json\n');
      stderr.writeln('Resultado gravado em ${output.absolute.path}');
    }
  } catch (error, stackTrace) {
    stderr
      ..writeln('Benchmark falhou: $error')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}

List<DriverFactory> _selectedDrivers(BenchmarkOptions options) {
  final all = <DriverFactory>[
    DriverFactory('dargres', () => DargresDriver(options.database)),
    DriverFactory(
      'postgres_fork',
      () => PostgresForkDriver(options.database),
    ),
  ];
  if (options.driver == 'both') return all;
  return all.where((driver) => driver.name == options.driver).toList();
}

Future<void> _installSchema(
  BenchmarkOptions options,
  DriverFactory factory,
) async {
  final schemaFile = _findSchemaFile(options.schemaPath);
  final sql = await schemaFile.readAsString();
  final driver = factory.create();
  await driver.open();
  try {
    await driver.execute(sql);
  } finally {
    await driver.close();
  }
}

File _findSchemaFile(String? explicitPath) {
  if (explicitPath != null) {
    final file = File(explicitPath);
    if (!file.existsSync()) {
      throw ArgumentError('Schema nao encontrado: ${file.absolute.path}');
    }
    return file;
  }

  final fromWorkingDirectory = File('schema.sql');
  if (fromWorkingDirectory.existsSync()) return fromWorkingDirectory;

  final nextToPackage = File.fromUri(Platform.script.resolve('../schema.sql'));
  if (nextToPackage.existsSync()) return nextToPackage;
  throw StateError(
    'schema.sql nao encontrado. Execute da raiz deste pacote ou use '
    '--schema=<caminho>.',
  );
}

class BenchmarkRunner {
  BenchmarkRunner(this.options, this.factories);

  final BenchmarkOptions options;
  final List<DriverFactory> factories;
  final CorrectnessGuard correctness = CorrectnessGuard();

  Future<Map<String, Object?>> run() async {
    final results = <Map<String, Object?>>[];
    for (final scenario in scenarios) {
      for (final factory in factories) {
        stderr.writeln(
          '${factory.name}/${scenario.name}/cold '
          '(${options.coldSamples} amostras)',
        );
        results.add(await _measureCold(factory, scenario));
      }
      for (final factory in factories) {
        stderr.writeln(
          '${factory.name}/${scenario.name}/warm '
          '(${options.samples} amostras x ${options.iterations} operacoes)',
        );
        results.add(await _measureWarm(factory, scenario));
      }
    }

    return <String, Object?>{
      'schema_version': 1,
      'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      'runtime': <String, Object?>{
        'dart': Platform.version,
        'operating_system': Platform.operatingSystem,
        'operating_system_version': Platform.operatingSystemVersion,
        'executable': Platform.resolvedExecutable,
      },
      'database': options.database.safeJson,
      'configuration': <String, Object?>{
        'rows_per_operation': options.rows,
        'cold_samples': options.coldSamples,
        'warm_samples': options.samples,
        'warmup_operations': options.warmup,
        'operations_per_warm_sample': options.iterations,
        'drivers': factories.map((driver) => driver.name).toList(),
        'cold_definition':
            'fresh connection and empty client statement cache; connect/close excluded',
        'warm_definition':
            'persistent connection after warmup; client statement reuse enabled',
      },
      'correctness': <String, Object?>{
        'rows': correctness.expected?.rows,
        'checksum': correctness.expected?.checksum,
        'black_hole': _blackHole,
      },
      'results': results,
    };
  }

  Future<Map<String, Object?>> _measureCold(
    DriverFactory factory,
    BenchmarkScenario scenario,
  ) async {
    final samples = <double>[];
    for (var sample = 0; sample < options.coldSamples; sample++) {
      final driver = factory.create();
      await driver.open();
      try {
        final stopwatch = Stopwatch()..start();
        final outcome = await scenario.invoke(driver, options.rows, false);
        stopwatch.stop();
        correctness.accept(
          outcome,
          '${factory.name}/${scenario.name}/cold/$sample',
        );
        _consume(outcome);
        samples.add(stopwatch.elapsedMicroseconds.toDouble());
      } finally {
        await driver.close();
      }
    }
    return _result(
      factory.name,
      scenario.name,
      'cold',
      samples,
      1,
    );
  }

  Future<Map<String, Object?>> _measureWarm(
    DriverFactory factory,
    BenchmarkScenario scenario,
  ) async {
    final driver = factory.create();
    await driver.open();
    try {
      for (var iteration = 0; iteration < options.warmup; iteration++) {
        final outcome = await scenario.invoke(driver, options.rows, true);
        correctness.accept(
          outcome,
          '${factory.name}/${scenario.name}/warmup/$iteration',
        );
        _consume(outcome);
      }

      final samples = <double>[];
      for (var sample = 0; sample < options.samples; sample++) {
        final stopwatch = Stopwatch()..start();
        for (var operation = 0;
            operation < options.iterations;
            operation++) {
          final outcome = await scenario.invoke(driver, options.rows, true);
          correctness.accept(
            outcome,
            '${factory.name}/${scenario.name}/warm/$sample/$operation',
          );
          _consume(outcome);
        }
        stopwatch.stop();
        samples.add(stopwatch.elapsedMicroseconds / options.iterations);
      }
      return _result(
        factory.name,
        scenario.name,
        'warm',
        samples,
        options.iterations,
      );
    } finally {
      await driver.close();
    }
  }

  Map<String, Object?> _result(
    String driver,
    String scenario,
    String temperature,
    List<double> samples,
    int operationsPerSample,
  ) {
    final statistics = SampleStatistics(samples);
    final medianRowsPerSecond =
        options.rows * Duration.microsecondsPerSecond / statistics.median;
    return <String, Object?>{
      'driver': driver,
      'scenario': scenario,
      'temperature': temperature,
      'sample_count': samples.length,
      'operations_per_sample': operationsPerSample,
      'rows_per_operation': options.rows,
      'latency_microseconds': <String, Object?>{
        'median': _rounded(statistics.median),
        'p95': _rounded(statistics.p95),
        'min': _rounded(statistics.min),
        'max': _rounded(statistics.max),
      },
      'median_rows_per_second': _rounded(medianRowsPerSecond),
      'samples_microseconds_per_operation':
          samples.map(_rounded).toList(growable: false),
      'checksum': correctness.expected?.checksum,
    };
  }
}

void _consume(WorkloadOutcome outcome) {
  _blackHole = (_blackHole ^ outcome.checksum ^ outcome.rows) & 0x7fffffff;
}

double _rounded(double value) => double.parse(value.toStringAsFixed(3));

class SampleStatistics {
  SampleStatistics(List<double> values)
      : sorted = List<double>.of(values)..sort() {
    if (values.isEmpty) throw ArgumentError('A lista de amostras esta vazia.');
  }

  final List<double> sorted;

  double get min => sorted.first;
  double get max => sorted.last;

  double get median {
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double get p95 {
    final nearestRank = (sorted.length * 0.95).ceil() - 1;
    return sorted[nearestRank.clamp(0, sorted.length - 1)];
  }
}

class CorrectnessGuard {
  WorkloadOutcome? expected;

  void accept(WorkloadOutcome actual, String context) {
    final baseline = expected;
    if (baseline == null) {
      expected = actual;
      return;
    }
    if (actual.rows != baseline.rows || actual.checksum != baseline.checksum) {
      throw StateError(
        'Resultado divergente em $context: '
        'recebido rows=${actual.rows}, checksum=${actual.checksum}; '
        'esperado rows=${baseline.rows}, checksum=${baseline.checksum}.',
      );
    }
  }
}

class WorkloadOutcome {
  const WorkloadOutcome(this.rows, this.checksum);

  final int rows;
  final int checksum;
}

class BenchmarkEntity {
  const BenchmarkEntity(
    this.id,
    this.accountId,
    this.score,
    this.active,
    this.label,
    this.createdAt,
  );

  factory BenchmarkEntity.fromDargres(dargres.RowView row) => BenchmarkEntity(
        row.getInt(0)!,
        row.getInt(1)!,
        row.getDouble(2)!,
        row.getBool(3)!,
        row.getString(4)!,
        row.getDateTime(5)!,
      );

  factory BenchmarkEntity.fromPostgresFork(List<dynamic> row) =>
      BenchmarkEntity(
        row[0] as int,
        row[1] as int,
        row[2] as double,
        row[3] as bool,
        row[4] as String,
        row[5] as DateTime,
      );

  final int id;
  final int accountId;
  final double score;
  final bool active;
  final String label;
  final DateTime createdAt;

  int get checksum => _rowChecksum(
        id,
        accountId,
        score,
        active,
        label,
        createdAt,
      );
}

int _rowChecksum(
  int id,
  int accountId,
  double score,
  bool active,
  String label,
  DateTime createdAt,
) =>
    id * 31 +
    accountId * 17 +
    (score * 100).round() * 7 +
    (active ? 13 : 0) +
    label.length * 19 +
    createdAt.toUtc().millisecondsSinceEpoch.remainder(997);

WorkloadOutcome _mapsOutcome(List<Map<String, dynamic>> rows) {
  var checksum = 0;
  for (final row in rows) {
    checksum += _rowChecksum(
      row['id'] as int,
      row['account_id'] as int,
      row['score'] as double,
      row['active'] as bool,
      row['label'] as String,
      row['created_at'] as DateTime,
    );
  }
  return WorkloadOutcome(rows.length, checksum);
}

WorkloadOutcome _entitiesOutcome(List<BenchmarkEntity> rows) {
  var checksum = 0;
  for (final row in rows) {
    checksum += row.checksum;
  }
  return WorkloadOutcome(rows.length, checksum);
}

abstract class BenchmarkDriver {
  String get name;

  Future<void> open();
  Future<void> close();
  Future<void> execute(String sql);

  Future<WorkloadOutcome> flatMaps(int limit, bool allowReuse);
  Future<WorkloadOutcome> typedEntities(int limit, bool allowReuse);
  Future<WorkloadOutcome> queryEachChecksum(int limit, bool allowReuse);
}

class DargresDriver implements BenchmarkDriver {
  DargresDriver(this.config);

  final DatabaseConfig config;
  dargres.CoreConnection? _connection;

  dargres.CoreConnection get connection => _connection!;

  @override
  String get name => 'dargres';

  @override
  Future<void> open() async {
    final connection = dargres.CoreConnection(
      config.user,
      host: config.host,
      port: config.port,
      database: config.database,
      password: config.password,
      connectionTimeout: Duration(seconds: config.connectTimeoutSeconds),
      applicationName: 'dargres-driver-comparison',
      sslContext: config.useSsl
          ? dargres.SslContext.createDefaultContext()
          : null,
      statementCacheCapacity: 64,
      timeZone: dargres.TimeZoneSettings('UTC'),
    );
    _connection = connection;
    await connection.connect();
  }

  @override
  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) await connection.close();
  }

  @override
  Future<void> execute(String sql) async {
    await connection.execute(sql);
  }

  @override
  Future<WorkloadOutcome> flatMaps(int limit, bool allowReuse) async {
    // dargres controls reuse through its per-connection statement cache.
    final rows = await connection.queryMaps(
      _dargresQuery,
      params: <Object?>[limit],
      requireBinaryResults: true,
    );
    return _mapsOutcome(rows);
  }

  @override
  Future<WorkloadOutcome> typedEntities(int limit, bool allowReuse) async {
    final rows = await connection.queryTyped<BenchmarkEntity>(
      _dargresQuery,
      BenchmarkEntity.fromDargres,
      params: <Object?>[limit],
      requireBinaryResults: true,
    );
    return _entitiesOutcome(rows);
  }

  @override
  Future<WorkloadOutcome> queryEachChecksum(
    int limit,
    bool allowReuse,
  ) async {
    var checksum = 0;
    var count = 0;
    await connection.queryEach(
      _dargresQuery,
      (row) {
        checksum += _rowChecksum(
          row.getInt(0)!,
          row.getInt(1)!,
          row.getDouble(2)!,
          row.getBool(3)!,
          row.getString(4)!,
          row.getDateTime(5)!,
        );
        count++;
      },
      params: <Object?>[limit],
      requireBinaryResults: true,
    );
    return WorkloadOutcome(count, checksum);
  }
}

class PostgresForkDriver implements BenchmarkDriver {
  PostgresForkDriver(this.config);

  final DatabaseConfig config;
  postgres_fork.PostgreSQLConnection? _connection;

  postgres_fork.PostgreSQLConnection get connection => _connection!;

  @override
  String get name => 'postgres_fork';

  @override
  Future<void> open() async {
    final connection = postgres_fork.PostgreSQLConnection(
      config.host,
      config.port,
      config.database,
      username: config.user,
      password: config.password,
      timeoutInSeconds: config.connectTimeoutSeconds,
      queryTimeoutInSeconds: config.queryTimeoutSeconds,
      useSSL: config.useSsl,
      timeZone: 'UTC',
    );
    _connection = connection;
    await connection.open();
  }

  @override
  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    if (connection != null) await connection.close();
  }

  @override
  Future<void> execute(String sql) async {
    await connection.execute(sql);
  }

  @override
  Future<WorkloadOutcome> flatMaps(int limit, bool allowReuse) async {
    final rows = await connection.queryAsMap(
      _postgresForkQuery,
      substitutionValues: <String, dynamic>{'limit': limit},
      allowReuse: allowReuse,
    );
    return _mapsOutcome(rows);
  }

  @override
  Future<WorkloadOutcome> typedEntities(int limit, bool allowReuse) async {
    final result = await connection.query(
      _postgresForkQuery,
      substitutionValues: <String, dynamic>{'limit': limit},
      allowReuse: allowReuse,
    );
    final entities = List<BenchmarkEntity>.generate(
      result.length,
      (index) => BenchmarkEntity.fromPostgresFork(result[index]),
      growable: false,
    );
    return _entitiesOutcome(entities);
  }

  @override
  Future<WorkloadOutcome> queryEachChecksum(
    int limit,
    bool allowReuse,
  ) async {
    // postgres_fork has no callback API: query() materializes its result first.
    final result = await connection.query(
      _postgresForkQuery,
      substitutionValues: <String, dynamic>{'limit': limit},
      allowReuse: allowReuse,
    );
    var checksum = 0;
    for (final row in result) {
      checksum += _rowChecksum(
        row[0] as int,
        row[1] as int,
        row[2] as double,
        row[3] as bool,
        row[4] as String,
        row[5] as DateTime,
      );
    }
    return WorkloadOutcome(result.length, checksum);
  }
}

class DriverFactory {
  const DriverFactory(this.name, this.create);

  final String name;
  final BenchmarkDriver Function() create;
}

class BenchmarkScenario {
  const BenchmarkScenario(this.name, this.invoke);

  final String name;
  final Future<WorkloadOutcome> Function(
    BenchmarkDriver driver,
    int limit,
    bool allowReuse,
  ) invoke;
}

final scenarios = <BenchmarkScenario>[
  BenchmarkScenario(
    'flat_map',
    (driver, limit, allowReuse) => driver.flatMaps(limit, allowReuse),
  ),
  BenchmarkScenario(
    'typed_entity',
    (driver, limit, allowReuse) => driver.typedEntities(limit, allowReuse),
  ),
  BenchmarkScenario(
    'query_each_checksum',
    (driver, limit, allowReuse) =>
        driver.queryEachChecksum(limit, allowReuse),
  ),
];

class DatabaseConfig {
  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
    required this.useSsl,
    required this.connectTimeoutSeconds,
    required this.queryTimeoutSeconds,
  });

  factory DatabaseConfig.fromEnvironment(Map<String, String> environment) {
    final sslMode = (environment['PGSSLMODE'] ?? 'disable').toLowerCase();
    if (sslMode != 'disable' && sslMode != 'require') {
      throw ArgumentError(
        'PGSSLMODE deve ser disable ou require neste harness; recebido '
        '$sslMode.',
      );
    }
    return DatabaseConfig(
      host: environment['PGHOST'] ?? '127.0.0.1',
      port: _environmentInt(environment, 'PGPORT', 5432),
      database: environment['PGDATABASE'] ?? 'postgres',
      user: environment['PGUSER'] ?? 'postgres',
      password: environment['PGPASSWORD'],
      useSsl: sslMode == 'require',
      connectTimeoutSeconds:
          _environmentInt(environment, 'PGCONNECT_TIMEOUT', 30),
      queryTimeoutSeconds:
          _environmentInt(environment, 'PGQUERY_TIMEOUT', 120),
    );
  }

  final String host;
  final int port;
  final String database;
  final String user;
  final String? password;
  final bool useSsl;
  final int connectTimeoutSeconds;
  final int queryTimeoutSeconds;

  Map<String, Object?> get safeJson => <String, Object?>{
        'host': host,
        'port': port,
        'database': database,
        'user': user,
        'ssl': useSsl,
        'connect_timeout_seconds': connectTimeoutSeconds,
        'query_timeout_seconds': queryTimeoutSeconds,
      };
}

class BenchmarkOptions {
  const BenchmarkOptions({
    required this.database,
    required this.rows,
    required this.samples,
    required this.coldSamples,
    required this.warmup,
    required this.iterations,
    required this.driver,
    required this.outputPath,
    required this.schemaPath,
    required this.setup,
    required this.setupOnly,
    required this.showHelp,
  });

  factory BenchmarkOptions.parse(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    var rows = _environmentInt(environment, 'BENCH_ROWS', 10000);
    var samples = _environmentInt(environment, 'BENCH_SAMPLES', 15);
    var coldSamples =
        _environmentInt(environment, 'BENCH_COLD_SAMPLES', 5);
    var warmup = _environmentInt(environment, 'BENCH_WARMUP', 3);
    var iterations = _environmentInt(environment, 'BENCH_ITERATIONS', 3);
    var driver = environment['BENCH_DRIVER'] ?? 'both';
    String? outputPath = environment['BENCH_OUTPUT'];
    String? schemaPath;
    var setup = false;
    var setupOnly = false;
    var showHelp = false;

    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        showHelp = true;
      } else if (argument == '--setup') {
        setup = true;
      } else if (argument == '--setup-only') {
        setupOnly = true;
      } else if (argument.startsWith('--rows=')) {
        rows = _argumentInt(argument, '--rows');
      } else if (argument.startsWith('--samples=')) {
        samples = _argumentInt(argument, '--samples');
      } else if (argument.startsWith('--cold-samples=')) {
        coldSamples = _argumentInt(argument, '--cold-samples');
      } else if (argument.startsWith('--warmup=')) {
        warmup = _argumentInt(argument, '--warmup');
      } else if (argument.startsWith('--iterations=')) {
        iterations = _argumentInt(argument, '--iterations');
      } else if (argument.startsWith('--driver=')) {
        driver = argument.substring('--driver='.length);
      } else if (argument.startsWith('--output=')) {
        outputPath = argument.substring('--output='.length);
      } else if (argument.startsWith('--schema=')) {
        schemaPath = argument.substring('--schema='.length);
      } else {
        throw ArgumentError('Argumento desconhecido: $argument');
      }
    }

    if (rows < 1 || rows > 100000) {
      throw ArgumentError('--rows deve estar entre 1 e 100000.');
    }
    for (final entry in <String, int>{
      '--samples': samples,
      '--cold-samples': coldSamples,
      '--warmup': warmup,
      '--iterations': iterations,
    }.entries) {
      if (entry.value < 1) {
        throw ArgumentError('${entry.key} deve ser maior que zero.');
      }
    }
    if (!const <String>{'both', 'dargres', 'postgres_fork'}
        .contains(driver)) {
      throw ArgumentError(
        '--driver deve ser both, dargres ou postgres_fork.',
      );
    }

    return BenchmarkOptions(
      database: DatabaseConfig.fromEnvironment(environment),
      rows: rows,
      samples: samples,
      coldSamples: coldSamples,
      warmup: warmup,
      iterations: iterations,
      driver: driver,
      outputPath: outputPath,
      schemaPath: schemaPath,
      setup: setup,
      setupOnly: setupOnly,
      showHelp: showHelp,
    );
  }

  final DatabaseConfig database;
  final int rows;
  final int samples;
  final int coldSamples;
  final int warmup;
  final int iterations;
  final String driver;
  final String? outputPath;
  final String? schemaPath;
  final bool setup;
  final bool setupOnly;
  final bool showHelp;

  static const usage = '''
Uso:
  dart run bin/driver_comparison.dart [opcoes]

Opcoes:
  --setup                 Recria o schema e executa os benchmarks.
  --setup-only            Recria o schema e encerra.
  --schema=PATH           Caminho alternativo para schema.sql.
  --driver=NAME           both (padrao), dargres ou postgres_fork.
  --rows=N                Linhas por consulta (padrao: 10000; maximo: 100000).
  --cold-samples=N        Amostras com cache cliente frio (padrao: 5).
  --samples=N             Amostras aquecidas (padrao: 15).
  --warmup=N              Operacoes de aquecimento (padrao: 3).
  --iterations=N          Operacoes por amostra aquecida (padrao: 3).
  --output=PATH           Grava JSON no arquivo; '-' usa stdout.
  --help, -h              Exibe esta ajuda.

Conexao (variaveis de ambiente):
  PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD,
  PGSSLMODE=disable|require, PGCONNECT_TIMEOUT, PGQUERY_TIMEOUT.

As opcoes numericas tambem aceitam BENCH_ROWS, BENCH_COLD_SAMPLES,
BENCH_SAMPLES, BENCH_WARMUP e BENCH_ITERATIONS.
''';
}

int _argumentInt(String argument, String name) {
  final value = argument.substring(name.length + 1);
  final parsed = int.tryParse(value);
  if (parsed == null) throw ArgumentError('$name exige um inteiro: $value');
  return parsed;
}

int _environmentInt(
  Map<String, String> environment,
  String name,
  int defaultValue,
) {
  final value = environment[name];
  if (value == null || value.isEmpty) return defaultValue;
  final parsed = int.tryParse(value);
  if (parsed == null) {
    throw ArgumentError('$name exige um inteiro: $value');
  }
  return parsed;
}
