
import 'package:example_dargres/src/example.dart';

void main(List<String> args) async {
  await example1();
  //'SELECT * FROM book WHERE title = ?, AND code = ?,'
  //INSERT INTO book (title,code) VALUES (?, ?)
  //SELECT * FROM book WHERE title = ? AND code = ?
  //$stmt = $pdo->prepare("INSERT INTO myTable (name, age) VALUES (?, ?)");
  //$stmt = $pdo->prepare("UPDATE myTable SET name = :name WHERE id = :id");
  // final re =  toStatement('UPDATE myTable SET name = :name WHERE id := :id',{'name' : 'David', 'id' : 10});
  // print(re[0]);
  // final newQuery2 =
  //     toStatement2('SELECT * FROM book WHERE title = ? AND code = ?');
  // print(newQuery2);

   
}
