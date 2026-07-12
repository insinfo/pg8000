# Regeneração do banco IANA

O gerador é puro Dart e não adiciona dependências ao driver. Sem argumentos,
ele baixa o `tzdata` IANA mais recente e regenera o recorte compacto de dez
anos:

```powershell
dart run scripts/generate_pg_timezone_data.dart
```

Para regenerar o histórico completo:

```powershell
dart run scripts/generate_pg_timezone_data.dart `
  --scope latest_all `
  --output lib/src/utils/pg_timezone/timezone/pg_timezone_data_all.dart
```

Para gerar ambos a partir de um arquivo ou diretório IANA previamente baixado,
use `--iana <caminho>`. Isso permite builds reproduzíveis sem novo download. O
gerador aceita também `--iana-version 2025c` para fixar uma versão publicada.

Depois da geração, execute:

```powershell
dart test test/unit/timezone_test.dart test/integration/timezone_test.dart
dart analyze --fatal-infos
```

Os arquivos `pg_timezone_data_10y.dart` e `pg_timezone_data_all.dart` são
gerados e devem continuar versionados; não os edite manualmente.
