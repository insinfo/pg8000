# Comparacao dargres x postgres_fork

Harness isolado para comparar os caminhos de materializacao dos dois drivers
contra a mesma instancia PostgreSQL e o mesmo conjunto deterministico de
100.000 linhas.

Os cenarios medidos sao:

- `flat_map`: `dargres.queryMaps` contra
  `postgres_fork.queryAsMap`. No fork, `allowReuse` e sempre passado
  explicitamente (`false` no cold e `true` no warm).
- `typed_entity`: cria uma `BenchmarkEntity` por linha. O dargres usa
  `queryTyped` e um `RowView` reutilizavel; o fork materializa seu resultado e
  depois cria as entidades.
- `query_each_checksum`: consome e calcula o checksum durante o callback do
  `dargres.queryEach`. O fork nao possui API equivalente e precisa materializar
  `query()` antes de iterar.

O `postgres_fork` pede formato binario para todas as colunas nesses caminhos.
Para comparar o mesmo protocolo, os tres cenarios do dargres usam
`requireBinaryResults: true`. O schema deterministico do harness contem apenas
OIDs com decoder binario coberto. Fora de benchmark, o padrão seguro do dargres
continua `false`; no modo estrito um OID sem suporte encerra a consulta com erro
e a SQL nunca é repetida automaticamente, evitando duplicar efeitos colaterais.

## Dependencias

Este diretorio e um pacote Dart independente. As duas dependencias sao locais:

- `dargres`: `../..`
- `postgres_fork`: `../../../postgres_fork`

O pacote requer Dart 3.6 ou mais recente, igual ao driver em teste.

Resolva as dependencias, preferencialmente sem rede:

```powershell
cd C:\MyDartProjects\pg8000\benchmark\driver_comparison
dart pub get --offline
```

O `pubspec.lock` versiona todas as dependencias transitivas depois dessa
resolucao. Se o cache local ainda nao contiver alguma delas, execute uma vez
`dart pub get` com acesso a rede e volte a usar `--offline` nas medicoes.

## PostgreSQL

O harness usa as variaveis padrao do PostgreSQL. Exemplo em PowerShell:

```powershell
$env:PGHOST = 'localhost'
$env:PGPORT = '5432'
$env:PGDATABASE = 'postgres'
$env:PGUSER = 'dart'
$env:PGPASSWORD = 'dart'
$env:PGSSLMODE = 'disable'
```

`PGSSLMODE` aceita `disable` ou `require`. Tambem sao reconhecidas
`PGCONNECT_TIMEOUT` e `PGQUERY_TIMEOUT`, em segundos. A senha nunca aparece no
JSON produzido.

Instale o conjunto de dados antes da primeira execucao:

```powershell
dart run bin/driver_comparison.dart --setup-only
```

Isso executa [schema.sql](schema.sql), removendo e recriando apenas o schema
`dargres_driver_benchmark`. Como alternativa, use `psql -v ON_ERROR_STOP=1 -f
schema.sql`.

## Executar

Rodada curta para validar ambiente e checksums:

```powershell
dart run bin/driver_comparison.dart --rows=100 --cold-samples=1 --samples=2 --warmup=1 --iterations=1
```

Rodada padrao, com JSON em arquivo:

```powershell
dart run bin/driver_comparison.dart --output=results\comparison.json
```

Para reduzir variacao do JIT, compile e execute o mesmo binario AOT:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
dart compile exe bin/driver_comparison.dart -o build\driver_comparison.exe
.\build\driver_comparison.exe --output=results\comparison-aot.json
```

Use `--driver=dargres` ou `--driver=postgres_fork` para rodadas separadas. Isso
permite alternar a ordem dos processos e reduzir vies de cache do servidor.
`--help` lista todas as opcoes e as variaveis `BENCH_*` equivalentes.

## Semantica e leitura do JSON

`cold` significa conexao nova e cache de statements do cliente vazio em cada
amostra. O tempo de conectar e fechar fica fora do cronometro. No
`postgres_fork`, o custo publico de resolucao inicial de metadata continua
incluido.

`warm` usa uma conexao persistente, executa o aquecimento e mede lotes de
operacoes com reutilizacao de statement. Cada valor em
`samples_microseconds_per_operation` ja esta normalizado por operacao.

O JSON informa mediana, p95 por nearest-rank, minimo, maximo, throughput pela
mediana e amostras brutas. Todos os cenarios e drivers precisam produzir a
mesma quantidade de linhas e o mesmo checksum; qualquer divergencia aborta a
execucao. O benchmark nao tenta esvaziar shared buffers/page cache do
PostgreSQL: `cold` descreve o estado do cliente, nao o cache do servidor ou do
sistema operacional.

Para resultados comparaveis, use a mesma maquina, o mesmo binario, servidor
ocioso, governor de CPU estavel e pelo menos tres processos independentes por
driver. Compare distribuicoes e nao apenas uma unica mediana.

## Resultado versionado de 2026-07-12

Com 10.000 linhas, sete amostras cold e dez amostras warm de tres operacoes,
o dargres venceu os seis pares medidos. Após o hardening de lifecycle, o
speedup mediano foi 2,13x-2,75x no JIT e 2,02x-2,66x no AOT. Os relatórios
completos estão em
[comparison-rows10000-postfix.json](results/comparison-rows10000-postfix.json)
e [comparison-rows10000-aot.json](results/comparison-rows10000-aot.json).
