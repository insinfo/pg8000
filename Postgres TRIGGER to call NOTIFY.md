```sql
CREATE OR REPLACE FUNCTION custom_notify() RETURNS trigger AS $trigger$
DECLARE
  rec RECORD;
  dat RECORD;
  payload TEXT;
BEGIN

  -- Set record row depending on operation
  CASE TG_OP
  WHEN 'UPDATE' THEN
     rec := NEW;
     dat := OLD;
  WHEN 'INSERT' THEN
     rec := NEW;
  WHEN 'DELETE' THEN
     rec := OLD;
  ELSE
     RAISE EXCEPTION 'Unknown TG_OP: "%". Should not occur!', TG_OP;
  END CASE;

  -- Build the payload
  payload := json_build_object('timestamp',CURRENT_TIMESTAMP,'action',LOWER(TG_OP),'schema',TG_TABLE_SCHEMA,'identity',TG_TABLE_NAME,'record',row_to_json(rec), 'old',row_to_json(dat));

  -- Notify the channel
  PERFORM pg_notify('db_change_event',payload);

  RETURN rec;
END;
$trigger$ LANGUAGE plpgsql;
```

```sql
DROP TRIGGER change_notify ON location;

-- então registraria os gatilhos
CREATE TRIGGER change_notify AFTER INSERT OR UPDATE OR DELETE ON location
FOR EACH ROW EXECUTE PROCEDURE notify_trigger();

-- ou também pode restringir quais campos realmente acionam a notificação:
CREATE TRIGGER trigger_update_notify
AFTER UPDATE ON cursos FOR EACH ROW
WHEN ( (OLD.nome, OLD.detalhe) IS DISTINCT FROM (NEW.nome, NEW.detalhe) )
EXECUTE PROCEDURE custom_notify(
  'id',
  'nome',
  'detalhe'
);
```