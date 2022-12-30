import 'package:dargres/src/to_statement.dart';
import 'package:test/test.dart';

void main() {
  // var con = CoreConnection('postgres',
  //     database: 'sistemas',
  //     host: 'localhost',
  //     port: 5432,
  //     password: 's1sadm1n',
  //     textCharset: 'utf8');

  // setUp(() async {
  //   await con.connect();
  // });

  test('toStatement SELECT with :', () async {
    var newQuery = toStatement(
        'SELECT * FROM book WHERE title = :title AND code = :code',
        {'title': 'ad', 'code': 1});
    var expected = r"SELECT * FROM book WHERE title = $1 AND code = $2";
    expect(newQuery[0], expected);
  });

  test('toStatement SELECT 2 with :', () async {
    var newQuery = toStatement(
        'SELECT * FROM book WHERE title = :code AND code = :code',
        {'title': 'ad', 'code': 1});
    var expected = r"SELECT * FROM book WHERE title = $1 AND code = $1";
    expect(newQuery[0], expected);
  });

  test('toStatement INSERT with :', () async {
    var newQuery = toStatement(
        'INSERT INTO tablex (title,code) VALUES (:title, :code)',
        {'title': 'ad', 'code': 1});
    var expected = r"INSERT INTO tablex (title,code) VALUES ($1, $2)";
    expect(newQuery[0], expected);
  });

  test('toStatement UPDATE with :', () async {
    var newQuery = toStatement(
        'UPDATE myTable SET name = :name WHERE id := :id',
        {'name': 'ad', 'id': 1});
    var expected = r"UPDATE myTable SET name = $1 WHERE id := $2";
    expect(newQuery[0], expected);
  });

  test('toStatement SELECT with @', () async {
    var newQuery = toStatement(
        'SELECT * FROM book WHERE title = @title AND code = @code',
        {'title': 'ad', 'code': 1},
        placeholderIdentifier: '@');
    var expected = r"SELECT * FROM book WHERE title = $1 AND code = $2";
    expect(newQuery[0], expected);
  });

  test('toStatement SELECT with #', () async {
    var newQuery = toStatement(
        'SELECT * FROM book WHERE title = #title AND code = #code',
        {'title': 'ad', 'code': 1},
        placeholderIdentifier: '#');
    var expected = r"SELECT * FROM book WHERE title = $1 AND code = $2";
    expect(newQuery[0], expected);
  });

  test('toStatement2', () async {
    var newQuery =
        toStatement2('SELECT * FROM book WHERE title = ? AND code = ?');
    var expected = r"SELECT * FROM book WHERE title = $1 AND code = $2";
    expect(newQuery, expected);
  });

  test('toStatement2 Question mark ? INSERT', () async {
    var newQuery = toStatement2(
        'INSERT INTO test_arrays (name,varchar_array_type,int8_array_type, int2_array_type, names_array_type) VALUES (?, ?, ?, ?, ?)');
    var expected =
        r"INSERT INTO test_arrays (name,varchar_array_type,int8_array_type, int2_array_type, names_array_type) VALUES ($1, $2, $3, $4, $5)";
    expect(newQuery, expected);
  });
}
