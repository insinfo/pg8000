# Plano executivo de refatoração de performance — dargres

> Estado em 2026-07-12: o novo caminho crítico, cache, codecs, pool e APIs diretas estão
> implementados. As suítes funcional/protocolo, o benchmark comparativo JIT/AOT e o soak de
> conexão/memória estão verdes. Lifecycle concorrente, cancelamento e recuperação após restart
> real também foram endurecidos e testados. Os JSONs brutos e os comandos reproduzíveis
> permanecem no projeto para que o resultado seja revalidado em cada hardware de produção.

## 1. Objetivo, escopo e definição de sucesso

O objetivo é substituir o caminho crítico do driver por uma implementação de protocolo
PostgreSQL v3 eficiente, previsível e mensurável. **Breaking changes estão autorizadas**:
compatibilidade de API e de comportamento só será mantida quando não impuser custo relevante,
complexidade estrutural ou ambiguidade ao novo desenho. O resultado deve oferecer:

1. `List<Map<String, dynamic>>`, sem criar `Row` e `StreamController` intermediários;
2. entidades tipadas, sem `Map`, `Row` ou lista nova por linha no caminho rápido;
3. processamento por callback com uma `RowView` reutilizada;
4. uma camada legada opcional para resultados materializados e stream, enquanto for útil;
5. conexão direta, transação e pool.

A prioridade é, nesta ordem: correção do protocolo e tipos, desempenho mensurado, ownership
claro, resiliência e uma API pequena. Métodos antigos podem mudar de assinatura, semântica ou
ser removidos. Toda quebra deliberada deve constar no changelog e no guia de migração; não é
necessário manter adaptadores no hot path.

O alvo comparativo principal é `C:\MyDartProjects\postgres_fork`, no commit registrado na
seção 3. A meta final é obter pelo menos **1,30x o throughput** dele nos cenários quentes de
mapas, entidades e consultas preparadas repetidas, sem sacrificar correção, estabilidade de
memória ou latência fria.

### 1.1 O que “sem alocações” significa neste plano

“Zero alocação” absoluto não é possível para todos os resultados em Dart. O contrato correto
é **sem alocações intermediárias por linha feitas pelo driver**, e somente no caminho rápido
qualificado.

| Caminho | Contrato de alocação por linha |
|---|---|
| `queryEach` + `RowView` reutilizada, colunas escalares binárias | nenhum `Row`, `Map`, `List` ou closure por linha; a `RowView` e seu armazenamento são reutilizados |
| `queryTyped<T>` | igual ao anterior, mais a entidade `T` criada pelo mapper do usuário |
| `queryMaps` | um `Map<String, dynamic>` distinto por linha é obrigatório; não há `Row` nem evento de stream intermediário |
| camada legada `Results`/`Row`, se mantida | mantém objetos próprios e estabilidade após o retorno; seu custo é medido separadamente |

Ainda alocam quando a semântica exige: `String`, `DateTime`, `BigInt`, JSON decodificado,
arrays, `numeric`, `bytea` que escape do callback e a entidade do usuário. Números também
podem sofrer boxing conforme o runtime. Portanto, a prova será feita por perfil de alocação e
por contagem de objetos intermediários, não pela afirmação genérica “zero allocation”.

A `RowView` é válida apenas durante o callback síncrono. O usuário não pode armazená-la para
uso posterior. `getBytesView` será uma visão efêmera; uma API que devolva bytes persistentes
deverá copiar. Callback assíncrono exige snapshot próprio e, portanto, não pertence ao caminho
sem intermediários.

## 2. Baseline reproduzível

- Código-base do dargres antes da refatoração: commit
  `fc7576c9e5f4452308dbbba0bf58d0e457c3c0a3`.
- Baseline funcional observado antes das alterações: **346 testes aprovados** (`+346`).
  Testes de componentes removidos junto com o legado não são preservados artificialmente;
  o gate passa a ser cobertura equivalente do produto ativo, mais protocolo simulado e
  integração real, nunca apenas comparação cega da contagem.
- SDK mínimo elevado explicitamente para Dart `^3.6.0`; breaking changes de linguagem e API
  fazem parte desta revisão.
- Banco-alvo inicial do benchmark: PostgreSQL 17 local. A versão exata do servidor, SO,
  CPU, modo JIT/AOT, charset, timezone, SSL e parâmetros do banco devem acompanhar cada
  resultado.
- O baseline de 346 testes não substitui testes de integração com PostgreSQL real. Testes que
  dependem do banco devem ter configuração e comando próprios, sem serem silenciosamente
  ignorados.

Antes de comparar performance, deve existir um relatório do driver original e do
`postgres_fork` no mesmo ambiente. Otimização sem esse relatório não fecha uma fase.

## 3. Referências fixadas e evidências auditadas

As referências são snapshots somente para estudo. Os commits observados localmente em
2026-07-12 são:

| Referência | Caminho/remote | Commit observado | Uso no projeto |
|---|---|---|---|
| dargres original | raiz deste repositório | `fc7576c9e5f4452308dbbba0bf58d0e457c3c0a3` | baseline funcional e de performance |
| postgresql-dart | `referencias/postgresql-dart` — `https://github.com/isoos/postgresql-dart.git` | `ffcd055bed417513579bdcc2562b2d30c65299d2` | framing, `message_window.dart`, buffer, codecs e testes de protocolo |
| postgres.js | `referencias/postgres-js` — `https://github.com/porsager/postgres.git` | `e7dfa14519f363229ccc3ead7b1b2f2051937efb` | hot paths, cache por SQL, escrita compacta e filas |
| pg8000 Python | `referencias/pg8000-python` — `https://github.com/mfenniak/pg8000` | `412eace074514ada824e7a102765e37e2cda8eaa` | origem conceitual dos conversores por OID; snapshot antigo, não padrão atual |
| postgres_fork | `C:\MyDartProjects\postgres_fork` — `https://github.com/insinfo/postgres_fork` | `4b8312671d06e17cc57d160488362ff95194759e` | concorrente de referência e contrato do benchmark |

Qualquer atualização de uma referência exige registrar o novo commit no relatório de
benchmark. Código não deve ser copiado sem conferir licença e atribuição; a preferência é
reimplementar os princípios compatíveis com a arquitetura do dargres.

### 3.1 Escopo do analisador

`referencias/**` contém pacotes independentes, com SDKs, dependências e regras próprias.
Esses diretórios não fazem parte do produto dargres e devem ser excluídos pelo
`analysis_options.yaml` da raiz. O gate é `dart analyze` sobre o pacote dargres, incluindo
`lib`, `test`, `benchmark` e `example`, mas não os clones.

As referências só são analisadas separadamente quando uma investigação exigir isso, dentro
do respectivo diretório e no commit fixado. Não se deve formatar, corrigir ou contabilizar
alertas dos clones como dívida do dargres. Antes de fechar uma fase, `git -C` em cada clone
deve confirmar que o snapshot de referência não foi alterado.

## 4. Diagnóstico do caminho original

O caminho crítico atual é:

```text
Socket -> CoreConnection._readData -> Buffer -> _readMessage
       -> _handle_DATA_ROW -> TypeConverter -> Query.addRow
       -> StreamController<Row> -> Results -> Row.toColumnMap
```

Problemas confirmados por inspeção:

1. `utils/buffer.dart` mantém uma fila de `List<int>`, mas `bytesAvailable` percorre todos os
   chunks com `fold` a cada consulta. `readBytes` percorre byte a byte e cresce uma lista.
2. O corpo inteiro de cada mensagem é materializado antes do handler. Em `DATA_ROW`, cada
   comprimento usa helpers que voltam a criar `Uint8List`, e cada célula usa `sublist`.
3. A linha nasce como lista dinâmica e cresce com `add`. Depois nasce um `Row`, um evento de
   stream e, frequentemente, uma segunda coleção em `toResults`.
4. Toda célula em texto passa por seleção de charset, criação de `String` e um switch por OID,
   mesmo quando o decoder poderia ter sido resolvido uma vez em `RowDescription`.
5. `Row.toColumnMap()` reconstrói a iteração de nomes para cada linha.
6. O protocolo estendido atual envia resultados em texto. Inteiros, floats e datas são
   convertidos de bytes para texto e depois para o tipo final.
7. A escrita usa spreads e vários `Socket.add`: `_send_message` separa código, tamanho e corpo;
   Parse, Describe, Bind, Execute, Flush e Sync também são enviados em partes.
8. `Query` mistura duas responsabilidades: definição de statement e estado mutável de uma
   execução. Controller, erro, contador, parâmetros, colunas e estado são reinicializados no
   mesmo objeto, o que torna cache e chamadas concorrentes inseguros.
9. O cache não pode ser um cache de objetos `Query`: prepared statement pertence a uma
   conexão física, enquanto parâmetros, resultado, erro e sink pertencem a uma execução.
10. `PostgreSqlPool`, `TransactionContext` e os wrappers precisam encaminhar toda API nova e
    preservar a conexão até o consumo terminar. Um statement preparado não pode escapar de
    uma conexão emprestada e ser executado em outra.
11. `lib/src/pool/postgres_pool.dart` estava integralmente comentado e não era exportado; ele
    foi removido. O pool público é `PostgreSqlPool` em `postgresql_pool.dart`.

## 5. Arquitetura alvo

```text
lib/src/fast/
  pg_read_buffer.dart   # acumulador híbrido de chunks e mensagens contíguas
  pg_write_buffer.dart  # writer tipado com patch de tamanho e lote por operação
  result_schema.dart    # metadados imutáveis e decoders resolvidos por coluna
  row_view.dart         # visão efêmera e reutilizável para mapas/callbacks/entidades
```

Os codecs podem começar em `result_schema.dart` e nos conversores existentes. Só devem virar
arquivos adicionais quando a separação melhorar teste e manutenção; criar abstrações sem
medição não é objetivo.

### 5.1 Buffer de leitura híbrido

Um único buffer contíguo que compacta todo o restante em cada fragmentação também pode gerar
cópias grandes. O desenho alvo combina os dois casos:

- fila/deque de `Uint8List` recebidos do socket, `headOffset` e contador total O(1);
- leitura direta e `Uint8List.sublistView` quando cabe no chunk da cabeça;
- leitura de inteiros que atravessam fronteira por um scratch fixo pequeno ou composição dos
  bytes, sem copiar toda a mensagem;
- quando um corpo cruza chunks, uma única cópia para armazenamento contíguo crescente e
  reutilizável; nunca uma cópia por byte ou por célula;
- views só vivem durante o handler síncrono. Objetos que escapam, especialmente `bytea`, têm
  ownership próprio;
- limite configurável de mensagem, validação de comprimento negativo/overflow e liberação ou
  redução de buffers anormalmente grandes para evitar retenção permanente.

Testes devem fragmentar cabeçalho e corpo em todas as posições, inclusive um byte por chunk,
várias mensagens no mesmo chunk, mensagem vazia, NULL, inteiros signed e corpos grandes.

### 5.2 Buffer de escrita e batching

`PgWriteBuffer` escreve em `Uint8List`/`ByteData`, cresce por capacidade e mantém apenas as
operações usadas pelo protocolo: `writeUint8`, `writeUint16`, `writeUint32`, `writeInt32`,
`writeBytes`, `startMessage` e `endMessage`. `endMessage` corrige o comprimento reservado.

Uma operação de protocolo deve gerar um buffer de saída e, normalmente, um `Socket.add`:

- startup e SSL request respeitam o framing especial;
- consulta simples: `Query` em um lote;
- cache miss frio: Parse + Bind + Describe Portal + Execute + Sync em um lote;
- cache hit: Bind + Execute + Sync em um lote;
- prepare explícito: Parse + Describe Statement + Sync em um lote;
- `Flush` só é emitido quando a máquina de estados realmente precisa receber resposta sem
  encerrar o ciclo com `Sync`.

Isso é **batching/coalescência de writes**, não pipeline. Reduz alocações e chamadas ao socket;
não significa que duas consultas estejam simultaneamente em voo.

Pipeline verdadeiro envia vários grupos antes do `ReadyForQuery` anterior e exige correlação
de respostas, backpressure, cancelamento e recuperação de erro por fronteira de `Sync`. Ele
fica fora do primeiro hot path e só será implementado como API opt-in em fase própria, se o
perfil demonstrar benefício. O benchmark não pode chamar batching de pipeline.

### 5.3 `ResultSchema` e decodificação de `DataRow`

`RowDescription` cria uma estrutura imutável compartilhada por todas as linhas:

- nomes, OIDs, tamanhos, modificadores e códigos de formato;
- decoder de texto ou binário resolvido uma vez por coluna;
- mapa nome -> índice criado uma vez;
- política documentada para nomes duplicados, preservando o comportamento atual de mapa
  (a última coluna com o mesmo nome vence);
- metadados necessários pela API pública `ColumnDescription`.

O cache guarda o schema lógico (nomes/OIDs). Como o primeiro resultado pode chegar em texto e
o seguinte em formatos seletivos, cada `Bind` deriva um plano de decodificação imutável para
os format codes daquela execução. Não se reutiliza o vetor de decoders de texto para bytes
binários apenas porque a SQL é a mesma.

O handler de `DataRow` lê a contagem e comprimentos com `ByteData`, preenche armazenamento
pré-dimensionado e chama um sink. Ele não usa `sublist` por célula. O caminho tradicional cria
`Row`; o caminho de mapa cria o mapa final; o caminho tipado/callback reutiliza a mesma
`RowView` e o mesmo armazenamento.

Texto UTF-8 usa conversão por faixa. Charsets alternativos usam o conversor compatível. Parser
manual de número só será adotado depois de testes diferenciais cobrirem sinais, overflow,
NaN, infinito e expoentes; para tipos suportados, binário é o atalho preferido.

### 5.4 Binário seletivo versus primeira execução em 1 RTT

O formato de resultado é escolhido no `Bind`, mas os OIDs das colunas só são conhecidos após
`Describe`. Logo, com suporte binário apenas parcial, não é possível simultaneamente escolher
binário por coluna e executar uma SQL desconhecida em um único round trip.

A política será explícita:

| Situação | Fluxo | Formato de resultado | RTT de protocolo |
|---|---|---|---|
| one-shot/cache desativado | Parse unnamed + Bind + Describe Portal + Execute + Sync no mesmo lote | texto | 1 |
| primeiro uso com cache | Parse named + Bind + Describe Portal + Execute + Sync no mesmo lote; guarda schema após sucesso | texto | 1 |
| cache hit | Bind com formatos por coluna + Execute + Sync | binário para OIDs suportados, texto para os demais | 1 |
| `prepareStatement` explícito | Parse + Describe em um RTT; cada execução faz Bind seletivo + Execute + Sync | seletivo | 1 para preparar + 1 por execução |
| opção futura “binário no primeiro uso” | Parse + Describe, aguarda schema, depois Bind + Execute | seletivo | 2 |

A primeira execução em texto não pode ser escondida no benchmark quente: o aquecimento ocorre
fora da janela medida. O benchmark frio usa 1 RTT em ambos os drivers. A variante binária de
2 RTT, se existir, é reportada separadamente.

`querySimple` continua sendo Simple Query Protocol e, portanto, recebe texto; ainda se
beneficia do framing, schema e decodificação otimizados.

Codecs iniciais de resultado: `bool`, `int2`, `int4`, `int8`, `float4`, `float8`, `char`,
`name`, `text`, `bpchar`, `varchar`, `bytea`, `oid`, `xid`, `uuid`, `date`, `timestamp`,
`timestamptz`, `json` e `jsonb`. `numeric`, money, time, interval, ranges, arrays, tipos
geométricos/de rede e extensões permanecem em texto até terem testes de paridade. Formato
binário nunca deve ser solicitado para um OID sem decoder binário seguro.

Parâmetros permanecem inicialmente em texto. Encoding binário de parâmetros é uma otimização
posterior e seletiva, condicionada a OID conhecido e teste de ida e volta.

### 5.5 Resultados diretos e camada legada

As assinaturas finais devem ser consistentes em `ExecutionContext`, `CoreConnection`,
`TransactionContext` e pool. A forma conceitual é:

```dart
Future<List<Map<String, dynamic>>> queryMaps(
  String sql, {
  dynamic params,
  PlaceholderIdentifier placeholderIdentifier = PlaceholderIdentifier.pgDefault,
  bool requireBinaryResults = false,
});
Future<List<T>> queryTyped<T>(
  String sql,
  T Function(RowView row) mapper, {
  dynamic params,
  PlaceholderIdentifier placeholderIdentifier = PlaceholderIdentifier.pgDefault,
  bool requireBinaryResults = false,
});
Future<void> queryEach(
  String sql,
  void Function(RowView row) onRow, {
  dynamic params,
  PlaceholderIdentifier placeholderIdentifier = PlaceholderIdentifier.pgDefault,
  bool requireBinaryResults = false,
});
Future<Results> queryCached(
  String sql, {
  dynamic params,
  PlaceholderIdentifier placeholderIdentifier = PlaceholderIdentifier.pgDefault,
  bool requireBinaryResults = false,
});
```

Detalhes obrigatórios:

- `queryMaps` devolve mapas independentes e estáveis; não há `allowReuse` de um mesmo mapa
  dentro da lista;
- `params` e `placeholderIdentifier` são nomeados nas quatro APIs diretas;
  `$n`/`?` exigem `List`, `:`/`@` exigem `Map`, e o modo `?` é explícito para
  não confundir autodetecção com operadores JSON PostgreSQL;
- `requireBinaryResults` é `false` por padrão; quando `true`, exige decoder
  binário para todos os OIDs retornados, falha no primeiro tipo sem suporte e
  nunca repete automaticamente a SQL, evitando duplicar efeitos colaterais;
- `queryTyped` chama um mapper síncrono e não cria `Map`/`Row` intermediário;
- `queryEach` documenta a validade efêmera da visão e propaga exceção do callback, mantendo o
  protocolo sincronizado até `ReadyForQuery` ou encerrando a conexão com segurança;
- `Row`, `Results`, `toMaps` e streams podem ser redesenhados ou removidos se prejudicarem o
  contrato principal; quando mantidos, devem ter semântica explícita e testes de migração;
- streams precisam de backpressure/cancelamento documentados. O pool só libera a conexão em
  `done`, erro ou cancelamento, nunca imediatamente após devolver o stream.

### 5.6 Separação entre statement, cache e execução

O estado deve ser dividido em:

1. **plano/statement imutável**: SQL já normalizada, nome no servidor, assinatura de OIDs dos
   parâmetros, `ResultSchema`, conexão proprietária e estado de preparação;
2. **execução descartável**: parâmetros, sink/controller, contadores, erro, stack trace,
   rowsAffected e completion.

`Query` pode permanecer temporariamente como fachada pública, mas cada chamada deve criar
um snapshot de execução. `addPreparedParams` não pode alterar uma execução em voo. Duas
execuções enfileiradas do mesmo prepared statement não compartilham controller, erro,
contador ou armazenamento de linha.

O cache LRU é por conexão física e limitado (padrão implementado: 64). Como
os parâmetros ainda são enviados em texto, a chave atual é a SQL final exata
após a conversão dos placeholders. Quando encoding binário de parâmetros ou
outra configuração capaz de mudar o plano for adicionada, a chave deverá
incluir a assinatura de OIDs/configuração correspondente. Não se compartilha
statement nomeado entre conexões do pool.

Regras de ciclo de vida:

- cache miss simultâneo é coalescido ou serializado sem publicar plano incompleto;
- eviction envia `Close Statement` em fronteira segura e não fecha item em uso;
- `DEALLOCATE`, reconnect, close e falhas de sessão invalidam os itens correspondentes;
- mudança de schema/erro de plano invalida o cache; não há retry automático cego de comandos
  potencialmente não idempotentes;
- nomes de statement são calculados uma vez, sem `padLeft` por execução;
- métricas de hit, miss e eviction ficam disponíveis ao benchmark/debug, sem custo por linha.

### 5.7 Cobertura de conexão, transação e pools

| Superfície | Trabalho obrigatório |
|---|---|
| `CoreConnection` | framing, batching, schemas, cache, APIs diretas e compatíveis, notices/notifications e lifecycle |
| `ExecutionContext` | declarar um contrato comum enxuto; métodos antigos podem virar adaptadores ou ser removidos |
| `TransactionContext` | usar a mesma conexão/cache, manter ordem, estado failed transaction, commit/rollback e não liberar visão prematuramente |
| `ConnectionInterface` | redefinir connect/close e transações com ownership inequívoco |
| `PostgreSqlPool` exportado | conceder uma conexão física exclusiva por operação, manter lease durante callback/transação, substituir conexão fechada e aplicar timeout |
| `postgres_pool.dart` legado | removido; era um arquivo de aproximadamente 900 linhas integralmente comentado |

`prepareStatement` através do pool exige uma solução explícita: handle preso a uma conexão
durante seu uso, ou plano lógico preparado/cacheado separadamente em cada conexão. Devolver um
`Query` ligado a uma conexão já devolvida ao pool é incorreto.

## 6. Fases e matriz de status

| Fase | Entrega | Estado atual |
|---|---|---|
| 0 | baseline, referências, escopo do analyzer e harness inicial | Concluído; relatórios JIT/AOT versionados |
| 1 | `PgReadBuffer` híbrido e `PgWriteBuffer` | Implementado e testado |
| 2 | `ResultSchema`, `RowView`, resultados compatíveis e execução isolada | Implementado e testado |
| 3 | integração no `core.dart`: framing, `DataRow` e batching | Implementado e testado |
| 4 | APIs diretas em conexão, transação e pool | Implementado e testado |
| 5 | cache LRU e política cold/warm de 1 RTT | Implementado e testado por backend simulado |
| 6 | codecs binários seletivos e fallback texto | Implementado para a lista inicial |
| 7 | paridade funcional, resiliência e matriz de testes | Concluído; suíte, churn, cancelamento, restart e soak verdes |
| 8 | benchmark justo e otimização guiada por perfil | Concluído para mapas, entidade e callback cold/warm |
| 9 | remoção do legado, documentação e release gate | Concluído |
| 10 | pipeline verdadeiro opt-in, somente se justificado | Condicional; não iniciado |

### 6.1 Evidências já obtidas nesta implementação

- zero dependências runtime no `pubspec.yaml`; MD5, SHA-1, SHA-256, HMAC,
  PBKDF2, hexadecimal, Windows-1252 e pool foram implementados internamente;
- testes separados fisicamente em `test/unit` e `test/integration`;
- CI com PostgreSQL 17 em `localhost:5432`, banco `postgres`, usuário/senha
  `dart`/`dart`, seguido de análise e das duas suítes;
- backend PostgreSQL simulado cobre fragmentação, cold/warm, formato binário
  seletivo, erro de callback, cache, eviction, `Close` adiado, recuperação de
  erro de manutenção, unnamed sem cache e transações concorrentes;
- integração PostgreSQL real cobre conexão, autenticação inválida, tipos,
  placeholders, prepared statements, transação e leases/timeouts do pool;
- `dart analyze` do produto e do pacote de benchmark retorna zero diagnósticos;
- 326 testes unitários e 71 testes de integração real passam; o churn SCRAM
  abre 40 conexões em lotes concorrentes e uma conexão longa processa 250
  operações enfileiradas no teste de regressão do socket;
- `connect()`/reconnect/`close()` são coalescidos e protegidos por geração de
  lifecycle; há backoff exponencial com jitter, `ping()` e `checkHealth()`;
- timeout direto usa `CancelRequest` real e preserva a conexão após
  `ReadyForQuery`; cancelamento manual e invalidação de timezone após
  `SET TIME ZONE` têm integração dedicada;
- o pool possui fila finita, rejeição determinística, métricas e quarentena de
  lease em timeout; nunca reutiliza um socket enquanto o Future anterior vive;
- fault injection reiniciou `postgresql-x64-17` via `gsudo`, manteve o serviço
  parado por três segundos, iniciou reconnect durante a queda, confirmou novos
  PIDs para conexão direta e dois slots do pool e concluiu 320 operações após a
  recuperação;
- o soak pós-hardening executou 1.346.073 operações em 60 segundos, com zero
  erro, rejeição, timeout ou substituição, quatro conexões físicas para 16
  workers e RSS sem crescimento linear (353,3 MiB nos relatórios intermediários
  e 338,3 MiB ao terminar);
- foi removida a corrida causada por `Socket.flush()` não aguardado durante
  startup/SCRAM/queries; `Socket.add()` permanece serializado e o único flush
  restante é aguardado no encerramento;
- removidos buffers Terrier/ISOOS, pack/unpack alternativos, experimentos,
  executor/retry/stack trace não utilizados, pool comentado, helpers duplicados
  e APIs internas que só lançavam `UnimplementedError`;
- suporte nomeado IANA é opt-in; UTC continua o hot path padrão. As bases
  `latest_all` e `latest_10y` permitem escolher correção histórica completa ou
  menor footprint; o gerador puro Dart foi incluído em `scripts/` e executado
  com sucesso contra o `tzdata` IANA mais recente.

### Fase 0 — baseline e governança

Entregas:

- registrar commits, ambiente e resultado do baseline funcional;
- excluir `referencias/**` do analyzer da raiz;
- criar harness que rode dargres original, dargres novo e `postgres_fork`;
- capturar throughput, latência, alocação, GC, pico de memória e número de writes do original;
- manter os clones limpos e somente para leitura.

Critério de saída: baseline bruto versionado, `dart analyze` do produto sem erros e comando
reproduzível do banco. Nenhum número obtido durante warmup conta como amostra.

### Fase 1 — buffers

Entregas:

- implementar os dois buffers tipados;
- testar todas as divisões possíveis de cabeçalho/corpo e crescimento/reuso;
- adicionar limites de segurança e ownership de views;
- microbenchmark contra `utils/buffer.dart` e a escrita atual.

Critério de saída: `bytesAvailable` O(1); mensagem contígua sem cópia de corpo; mensagem
fragmentada com no máximo uma cópia proporcional ao corpo; nenhum loop byte a byte para
coalescência proporcional ao corpo; um buffer/socket write por lote; testes de fragmentação e limites verdes. O
microbenchmark deve mostrar melhoria e não apenas equivalência.

### Fase 2 — schema, visão e estado de execução

Entregas:

- resolver decoders uma vez por coluna;
- construir `nameToIndex` uma vez por resultado;
- prealocar armazenamento da linha e reutilizá-lo nas APIs qualificadas;
- separar metadata de prepared statement do estado de execução;
- preservar `Row`/`Results` e nomes duplicados.

Critério de saída: testes demonstram que duas execuções do mesmo statement não compartilham
controller/erro/contador; `queryEach` não cria `Row`, `Map` ou lista por linha; mapa retornado é
estável e distinto; acesso a `RowView` expirada falha em debug ou é explicitamente
documentado; conversão atual permanece equivalente.

### Fase 3 — integração no protocolo

Entregas:

- trocar `_readData`, `_readMessage`, `RowDescription` e `DataRow` pelo caminho tipado;
- migrar todas as mensagens de frontend para `PgWriteBuffer`;
- remover `Flush` redundante;
- manter temporariamente o caminho antigo como comparação interna até a paridade;
- preservar autenticação, erro, notice, notification, ReadyForQuery e mensagens grandes.

Critério de saída: transcrições de protocolo e integração real passam com qualquer
fragmentação; nenhum `sublist` por célula no hot path; uma operação estendida agrupada usa um
`Socket.add`; erro de callback ou decoder não deixa a conexão falsamente idle; o caminho novo
passa os testes existentes antes de remover o antigo.

### Fase 4 — APIs e contextos

Entregas:

- implementar `queryMaps`, `queryTyped` e `queryEach` em `CoreConnection`;
- encaminhar em `ExecutionContext`, `TransactionContext` e `PostgreSqlPool`;
- cobrir timeouts, cancelamento, rowsAffected, erros e streams;
- resolver afinidade de prepared statement no pool;
- decidir formalmente o destino do pool legado comentado.

Critério de saída: a mesma suíte contratual roda contra conexão direta, dentro de
`runInTransaction` e através do pool; commit/rollback e failed transaction funcionam; o pool
não reutiliza conexão enquanto callback/transação está ativo. Métodos legados quebrados ou
sem ownership correto podem ser removidos, pois esta revisão autoriza breaking changes.

### Fase 5 — cache e execução cold/warm

Entregas:

- LRU por conexão com chave e lifecycle definidos na seção 5.6;
- primeiro uso em texto e 1 RTT; hit em binário seletivo e 1 RTT;
- prepare explícito e invalidation por reconnect/DEALLOCATE/eviction;
- métricas de cache e teste de concorrência.

Critério de saída: contagem de mensagens prova os fluxos da tabela 5.4; cache hit não envia
Parse/Describe; cache miss não usa duas viagens por acidente; eviction não fecha statement em
uso; não há reutilização entre conexões; falha de plano não causa retry inseguro.

### Fase 6 — binário seletivo

Entregas:

- implementar a lista inicial de codecs;
- comparar texto versus binário para NULL, extremos, timezone, datas antes/depois de 2000,
  NaN/infinito, JSONB version byte, UUID e bytea;
- fallback por coluna para tipos sem codec;
- perfilar depois cada codec adicional, incluindo arrays e `numeric`.

Critério de saída: nenhum OID desconhecido recebe formato 1; testes diferenciais preservam os
tipos/valores atuais; `TimeZoneSettings` tem a mesma semântica; schema misto texto/binário
funciona; desempenho dos tipos escalares melhora sem regressão do caminho texto.

### Fase 7 — correção e resiliência

Entregas:

- executar a cobertura ativa unitária, o protocolo simulado e os testes novos de integração;
- testes de integração para Simple e Extended Protocol, conexão direta, transação e pool;
- fragmentação, mensagens concatenadas, erro no meio do resultado, cancelamento, reconnect,
  cache inválido, charset não UTF-8 e resultados grandes;
- teste de memória longa para detectar crescimento de buffer/cache;
- analisar todos os arquivos do produto sem erro ou warning.

Critério de saída: zero regressões, zero erro de analyzer, nenhuma conexão reutilizada em
estado incorreto, memória estabiliza após warmup e cache respeita o limite. Teste ignorado por
falta de banco não pode ser usado para declarar esta fase pronta.

### Fase 8 — benchmark e ciclo de otimização

Entregas e metodologia estão na seção 7. Se a meta falhar, usar CPU profile e allocation
profile para escolher o próximo gargalo; não fazer mudanças especulativas.

Critério de saída: metas quantitativas da seção 7 atingidas em execuções reproduzíveis, com
dados brutos e metadados publicados. Não vale escolher somente a melhor execução.

### Fase 9 — consolidação

Entregas:

- remover o caminho antigo apenas após todos os gates;
- documentar APIs, validade da `RowView`, cache, formatos e migração;
- atualizar README, changelog e exemplos;
- revisar compatibilidade de SDK e versionamento semântico;
- rodar o release gate completo em árvore limpa.

Critério de saída: nenhuma implementação duplicada no hot path, documentação executável,
árvore limpa, referências intactas e definição de pronto atendida.

### Fase 10 — pipeline verdadeiro opcional

Só iniciar se o perfil mostrar que a latência de múltiplas consultas independentes é o
gargalo. A API deve ser opt-in, com grupos e fronteiras de `Sync`, limite de itens/bytes,
backpressure, correlação de respostas e semântica de erro/transaction documentada.

Critério de saída: testes com múltiplas operações em voo, erro no primeiro/meio/último grupo,
cancelamento, transação e recuperação até `ReadyForQuery`; benchmark separado do batching.

## 7. Benchmark comparativo justo

### 7.1 Regras do ambiente

- mesma máquina, Dart SDK, PostgreSQL, configuração, charset, timezone e SSL;
- conexões persistentes abertas antes da medição; tempo de connect é cenário separado;
- JIT com warmup e AOT compilado reportados separadamente;
- ordem dos drivers alternada ou randomizada para reduzir viés térmico/cache;
- dataset recriado com seed fixa e `ANALYZE` executado;
- pelo menos 5 processos/amostras independentes; reportar mediana, p95, desvio/CV, linhas/s,
  bytes alocados/linha, GCs, pico de RSS e writes/operação;
- duração suficiente por amostra, sem medir setup, impressão ou validação de resultado;
- validar checksum/contagem e tipos retornados fora da janela cronometrada;
- salvar CSV/JSON bruto com commits dos dois drivers e `SELECT version()`.

Dataset principal: 5.000 linhas com `int4`, `int8`, `text`, `varchar`, `float8`, `bool`,
`timestamp`, além de cenários de 1, 100 e 100.000 linhas para separar latência, throughput e
memória. Acrescentar dataset misto com NULL e tipos que forçam fallback texto.

### 7.2 Matriz obrigatória

| Cenário | dargres | postgres_fork | Regra de justiça |
|---|---|---|---|
| mapa frio | `queryMaps(requireBinaryResults: true)`, cache desativado | `queryAsMap(..., allowReuse: false)` | binário integral, uma execução/SQL única; 1 RTT nos dois |
| mapa quente | `queryMaps(requireBinaryResults: true)`, cache ativado e previamente aquecido | `queryAsMap(..., allowReuse: true)` previamente aquecido | binário integral; warmup fora da medição; mesmo resultado final |
| entidade quente | `queryTyped(requireBinaryResults: true)` + construtor da entidade | `query(..., allowReuse: true)` + o mesmo construtor lendo colunas | binário integral; nenhum lado cria Map intermediário |
| API compatível | `Results`/`Row` | resultado posicional equivalente | mede custo da compatibilidade separadamente |
| preparada com parâmetro | cache hit ou prepared explícito | reuse ativado | mesma SQL, OIDs e valores |
| insert/update | protocolo estendido dentro da mesma política de transação | equivalente | mesma política de commit/fsync |
| fallback misto | binário + texto por coluna | formato usado pelo concorrente | registrar formatos efetivos |
| stream/callback | somente se houver saída e backpressure equivalentes | API equivalente | não comparar materialização com descarte |

O `queryAsMap` do `postgres_fork` usa `allowReuse: false` por padrão. Compará-lo assim contra
um cache quente do dargres seria inválido. Por isso o argumento é sempre explícito. Também não
se usa `mappedResultsQuery` no cenário de mapa simples, pois ele produz mapas aninhados e pode
resolver nomes de tabelas. Caches auxiliares de OID/nome de tabela devem ser aquecidos fora da
janela nos dois lados; no cenário frio desativa-se apenas o reuse do statement. Uma medição
separada registra a primeira chamada absoluta, incluindo descoberta de metadados.

### 7.3 Metas quantitativas

Metas obrigatórias, medidas em AOT e confirmadas em JIT estabilizado:

1. mapas quentes, entidade quente e prepared select de 5.000 linhas: throughput mediano do
   dargres **>= 1,30x** o `postgres_fork`;
2. p95 desses cenários sem regressão desproporcional e coerente com a meta de throughput;
3. cenário frio de 1 linha, 1 RTT: latência mediana não pior que o concorrente em mais de 10%;
4. caminho tipado/callback escalar: zero `Row`, `Map` e lista por linha criados pelo driver;
5. caminho de mapas: pelo menos 50% menos bytes intermediários/linha que o dargres original,
   além do mapa final inevitável;
6. consulta estendida agrupada: um `Socket.add` por operação normal;
7. memória de teste longo estabilizada e cache limitado; sem crescimento linear após consumo;
8. nenhum ganho de performance vale se mudar valor, tipo, ordem, rowsAffected ou erro público.

### 7.4 Resultado local fechado em 2026-07-12

Ambiente: Dart 3.6.2 AOT/JIT, PostgreSQL 17 local, Windows x64, 10.000 linhas
por operação, sete amostras cold e dez amostras warm com três operações por
amostra. Os dois drivers pedem binário integral nestes cenários; no dargres
isso é explícito por `requireBinaryResults: true`. Todos produziram 10.000
linhas e checksum `2756986225`.

| Cenário | Speedup JIT `postgres_fork/dargres` | Speedup AOT `postgres_fork/dargres` |
|---|---:|---:|
| `flat_map` cold | 2,26x | 2,22x |
| `flat_map` warm | 2,13x | 2,02x |
| `typed_entity` cold | 2,50x | 2,59x |
| `typed_entity` warm | 2,27x | 2,25x |
| `query_each_checksum` cold | 2,75x | 2,61x |
| `query_each_checksum` warm | 2,44x | 2,66x |

Valores acima de 1 significam dargres mais rápido. Amostras, medianas, p95 e
throughput completos estão em
`benchmark/driver_comparison/results/comparison-rows10000-postfix.json` e
`benchmark/driver_comparison/results/comparison-rows10000-aot.json`.

Se uma meta não for alcançada, o relatório deve apontar o perfil dominante e abrir uma nova
ação concreta, por exemplo codecs de arrays/numeric, parâmetros binários, parser textual ou
pipeline. Não se reduz a meta nem se declara sucesso parcial sem registrar a decisão.

## 8. Matriz mínima de testes

| Área | Casos obrigatórios |
|---|---|
| buffers | todas as fragmentações, limites, endianness, signed, múltiplas mensagens, corpo grande |
| schema | zero/uma/muitas colunas, nomes duplicados, OID desconhecido, formato misto |
| tipos | NULL, extremos numéricos, NaN/infinito, timezone/DST, JSON/JSONB, UUID, bytea, charset alternativo |
| resultados | Row/Results/toMaps, mapa direto, entidade, callback, exceção do mapper, visão expirada |
| query | simples, unnamed, named, prepare/execute/deallocate, reutilização e concorrência enfileirada |
| cache | hit/miss/eviction, DDL invalidante, reconnect, close, conexão diferente, item em uso |
| transação | begin/commit/rollback, nested policy atual, failed transaction, callback com erro |
| pool | lease, fila cheia, timeout/quarentena, prepared affinity, reconnect, fechamento |
| protocolo | auth, cancel request, error/notice/notification, ReadyForQuery, mensagens parciais/concatenadas |
| longevidade | milhões de linhas/iterações, restart real, RSS, GC, cache e buffers estabilizados |

Gate sugerido de cada entrega:

```powershell
dart analyze --fatal-infos
dart test test/unit
dart test test/integration --concurrency=1
cd benchmark/driver_comparison; dart analyze --fatal-infos
# Windows/local e destrutivo:
dart run tool/postgres_restart_fault_test.dart
```

O comando de integração com PostgreSQL e o comando de benchmark devem ser adicionados ao
repositório com variáveis de ambiente documentadas. `referencias/**` não entra nos comandos de
qualidade do produto.

## 9. Riscos e decisões de segurança

- **View após reuso:** validade síncrona, API de cópia explícita para dados persistentes e
  checagem de geração em debug.
- **Mensagem fragmentada:** buffer híbrido copia uma vez; não presume chunk contíguo.
- **Retenção de memória:** limites de mensagem/cache e descarte de buffers gigantes.
- **Timezone e datas especiais:** paridade diferencial texto/binário antes de ativar codec.
- **OID sem codec:** fallback texto; nunca interpretar layout desconhecido.
- **Cache e DDL:** invalidar, reportar erro e evitar retry automático de mutação.
- **Query mutável:** snapshot por execução; nenhum controller/sink compartilhado.
- **Pool:** statement pertence à conexão física e lease acompanha todo o consumo.
- **Overload:** fila do pool é finita; excesso falha antes de executar e expõe métricas.
- **Timeout:** `CancelRequest` drena até `ReadyForQuery`; ausência de confirmação destrói o socket.
- **Reconnect:** limite, backoff e jitter são explícitos; `close()` terminal não permite ressurreição.
- **Erro no callback:** drenar de forma segura até `ReadyForQuery` ou destruir a conexão; não
  devolvê-la ao pool como saudável.
- **Backpressure:** streams não podem permitir crescimento ilimitado sem pausa/cancelamento.
- **Otimização sem benefício:** toda mudança no hot path precisa de benchmark e perfil antes e
  depois.

## 10. Definição final de pronto

A refatoração só está pronta quando, simultaneamente:

- toda a cobertura ainda aplicável do baseline, o protocolo simulado e os testes novos passam;
- `dart analyze` passa sobre o produto, com referências intactas;
- todas as breaking changes estão cobertas por changelog, exemplos e guia de migração;
- APIs de mapa, entidade e callback cumprem seus contratos de ownership/alocação;
- cold path continua em 1 RTT por padrão e warm path usa binário seletivo com cache seguro;
- batching está provado por contagem de writes e não é anunciado como pipeline;
- metas de throughput, latência, alocação e memória foram atingidas contra o commit fixado do
  `postgres_fork`;
- resultados brutos, ambiente, commits e comandos são reproduzíveis;
- o caminho antigo foi removido somente depois de todos esses gates.

Os gates comparativos e de soak desta matriz estão fechados no ambiente acima:
o dargres superou o commit fixado do `postgres_fork` em todos os seis cenários.
Isso não substitui repetir o harness no hardware, rede, schema e carga reais de
cada implantação antes de definir seus limites operacionais.
