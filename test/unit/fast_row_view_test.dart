import 'dart:typed_data';

import 'package:dargres/src/fast/row_view.dart';
import 'package:test/test.dart';

void main() {
  group('RowView', () {
    test('provides typed access by index and name', () {
      final timestamp = DateTime.utc(2026, 7, 12);
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final row = RowView(<Object?>[
        7,
        'seven',
        2.5,
        true,
        timestamp,
        bytes,
        null,
      ], <String, int>{
        'id': 0,
        'label': 1,
        'score': 2,
        'enabled': 3,
        'created_at': 4,
        'payload': 5,
        'optional': 6,
      });

      expect(row.length, 7);
      expect(row[0], 7);
      expect(row['label'], 'seven');
      expect(row.getInt(0), 7);
      expect(row.getInt('id'), 7);
      expect(row.getString(1), 'seven');
      expect(row.getStringByName('label'), 'seven');
      expect(row.getDouble('score'), 2.5);
      expect(row.getNumByName('score'), 2.5);
      expect(row.getBool('enabled'), isTrue);
      expect(row.getDateTime('created_at'), same(timestamp));
      expect(row.getBytesByName('payload'), same(bytes));
      expect(row.get<String>(1), 'seven');
      expect(row.byName<int>('id'), 7);
      expect(row.byName<String>('optional'), isNull);
      expect(row.containsColumn('id'), isTrue);
      expect(row.containsColumn('missing'), isFalse);
      expect(row.indexOf('payload'), 5);
    });

    test('reuses the same view and reflects its mutable backing list', () {
      final first = <Object?>[1, 'first'];
      final indexes = <String, int>{'id': 0, 'name': 1};
      final row = RowView(first, indexes);

      first[0] = 2;
      first[1] = 'updated';
      expect(row.getInt('id'), 2);
      expect(row.getString('name'), 'updated');

      final second = <Object?>[3, true];
      final returned = row.reset(second, <String, int>{'id': 0, 'active': 1});
      expect(returned, same(row));
      expect(row.getInt('id'), 3);
      expect(row.getBool('active'), isTrue);
      expect(row.values, same(second));
    });

    test('reports invalid names, keys, indexes, and typed casts', () {
      final row = RowView(<Object?>[1], <String, int>{'id': 0});

      expect(() => row['missing'], throwsArgumentError);
      expect(() => row.indexOf('missing'), throwsArgumentError);
      expect(() => row[Object()], throwsArgumentError);
      expect(() => row[2], throwsRangeError);
      expect(() => row.getString('id'), throwsA(isA<TypeError>()));
    });
  });
}
