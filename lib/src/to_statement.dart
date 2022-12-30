import 'package:dargres/src/utils/utils.dart';

/// placeholder Identifier
class PlaceholderIdentifier {
  final String value;
  const PlaceholderIdentifier(this.value);

  /// The colon is the symbol ":"
  /// Example: "SELECT * FROM book WHERE title = :title AND code = :code"
  static const PlaceholderIdentifier colon = const PlaceholderIdentifier(':');

  // The question mark ? (also known as interrogation point)
  //static const PlaceholderStyle questionMark = const PlaceholderStyle('?');

  /// The question mark ? (also known as interrogation point)
  /// Example: "SELECT * FROM book WHERE title = ? AND code = ?"
  static const PlaceholderIdentifier onlyQuestionMark =
      const PlaceholderIdentifier('?');

  /// In business, @ (Arroba ) is a symbol meaning "at" or "each."
  /// Example: "SELECT * FROM book WHERE title = @title AND code = @code"
  static const PlaceholderIdentifier atSign = const PlaceholderIdentifier('@');

  /// Postgresql default style
  /// Example: "SELECT * FROM book WHERE title = $1 AND code = $2"
  /// Postgres uses $# for placeholders https://www.postgresql.org/docs/9.1/sql-prepare.html
  static const PlaceholderIdentifier pgDefault =
      const PlaceholderIdentifier(r'$#');
}

extension AppendToEnd on List {
  void replaceLast(dynamic item) {
    if (this.length == 0) {
      this.add(item);
    } else {
      this[this.length - 1] = item;
    }
  }

  /// like python index function
  /// Example: var placeholders = ['a','b','c','d','e'];
  /// pidx = placeholders.index(placeholders[-1],0,-1);
  /// Exception: ValueError: 'e' is not in list
  int indexWithEnd(Object? element, [int start = 0, int? stop]) {
    if (start < 0) start = 0;

    if (stop != null && stop < 0) stop = this.length - 1;

    for (int i = start; i < (stop != null ? stop : this.length); i++) {
      if (this[i] == element) return i;
    }
    throw Exception("ValueError: '$element' is not in list");
  }
}

/// outside quoted string
const OUTSIDE = 0;

/// inside single-quote string '...'
const INSIDE_SQ = 1;

/// inside quoted identifier   "..."
const INSIDE_QI = 2;

/// inside escaped single-quote string, E'...'
const INSIDE_ES = 3;

/// inside parameter name eg. :name
const INSIDE_PN = 4;

/// inside inline comment eg. --
const INSIDE_CO = 5;

/// the toStatement function is used to replace the 'placeholderIdentifier' to  '$#' for postgres sql statement style
/// Example: "INSERT INTO book (title) VALUES (:title)" to "INSERT INTO book (title) VALUES ($1)"
/// [placeholderIdentifier] placeholder identifier character represents the pattern that will be
///  replaced in the execution of the query by the supplied parameters
/// [params] parameters can be a list or a map
/// `Returns` [ String query,  List<dynamic> Function(dynamic) make_vals ]
/// Postgres uses $# for placeholders https://www.postgresql.org/docs/9.1/sql-prepare.html
List toStatement(String query, Map params,
    {String placeholderIdentifier = ':'}) {
  var in_quote_escape = false;
  var placeholders = [];
  var output_query = [];
  var state = OUTSIDE;
  var prev_c = null;
  String? next_c = null;

  //add space to end
  var splitString = '$query  '.split('');
  for (var i = 0; i < splitString.length; i++) {
    var c = splitString[i];

    if (i + 1 < splitString.length) {
      next_c = splitString[i + 1];
    } else {
      next_c = null;
    }

    if (state == OUTSIDE) {
      if (c == "'") {
        output_query.add(c);
        if (prev_c == "E") {
          state = INSIDE_ES;
        } else {
          state = INSIDE_SQ;
        }
      } else if (c == '"') {
        output_query.add(c);
        state = INSIDE_QI;
      } else if (c == "-") {
        output_query.add(c);
        if (prev_c == "-") {
          state = INSIDE_CO;
        }

        //ignore operator @@ or := :: @= ?? ?=
      } else if (c == placeholderIdentifier &&
          '$placeholderIdentifier='.contains(next_c != null ? next_c : '') ==
              false &&
          '$placeholderIdentifier$placeholderIdentifier'
                  .contains(next_c != null ? next_c : '') ==
              false &&
          prev_c != placeholderIdentifier) {
        state = INSIDE_PN;
        placeholders.add("");
      } else {
        output_query.add(c);
      }
    }
    //
    else if (state == INSIDE_SQ) {
      if (c == "'") {
        if (in_quote_escape) {
          in_quote_escape = false;
        } else if (next_c == "'") {
          in_quote_escape = true;
        } else {
          state = OUTSIDE;
        }
      }
      output_query.add(c);
    }
    //
    else if (state == INSIDE_QI) {
      if (c == '"') {
        state = OUTSIDE;
      }
      output_query.add(c);
    }
    //
    else if (state == INSIDE_ES) {
      if (c == "'" && prev_c != "\\") {
        // check for escaped single-quote
        state = OUTSIDE;
      }
      output_query.add(c);
    }
    //
    else if (state == INSIDE_PN) {
      placeholders.replaceLast(placeholders.last + c);

      if (next_c == null || (!Utils.isalnum(next_c) && next_c != "_")) {
        state = OUTSIDE;
        try {
          //print('to_statement last: ${placeholders.last}');
          var pidx = placeholders.indexWithEnd(placeholders.last, 0, -1);
          //print('to_statement pidx: $pidx');
          output_query.add("\$${pidx + 1}");
          //del placeholders[-1]
          placeholders.removeLast();
        } catch (_) {
          output_query.add("\$${placeholders.length}");
        }
      }
    }
    //
    else if (state == INSIDE_CO) {
      output_query.add(c);
      if (c == "\n") {
        state = OUTSIDE;
      }
    }
    prev_c = c;
  }

  for (var reserved in ["types", "stream"]) {
    if (placeholders.contains(reserved)) {
      throw Exception(
          "The name '$reserved' can't be used as a placeholder because it's "
          "used for another purpose.");
    }
  }

  /// [args]
  var make_vals = (Map args) {
    var vals = [];
    for (var p in placeholders) {
      try {
        vals.add(args[p]);
      } catch (_) {
        throw Exception(
            "There's a placeholder '$p' in the query, but no matching "
            "keyword argument.");
      }
    }
    return vals;
  };
  var resultQuery = output_query.join('');
  //resultQuery = resultQuery.substring(0, resultQuery.length - 1);
  resultQuery = resultQuery.trim();
  return [resultQuery, make_vals(params)];
}

/// the toStatement2 function is used to replace the Question mark '?' to  '$1' for sql statement
/// "INSERT INTO book (title) VALUES (?)" to "INSERT INTO book (title) VALUES ($1)"
/// `Returns` [ String query,  List<dynamic> Function(dynamic) make_vals ]
/// Postgres uses $# for placeholders https://www.postgresql.org/docs/9.1/sql-prepare.html
String toStatement2(String query) {
  final placeholderIdentifier = '?';
  var in_quote_escape = false;
  // var placeholders = [];
  var outputQuery = [];
  var state = OUTSIDE;
  var paramCount = 1;
  //character anterior
  String? prev_c = null;
  String? next_c = null;

  //add space to end of string to force INSIDE_PN;
  final splitString = '$query  '.split('');
  for (var i = 0; i < splitString.length; i++) {
    final c = splitString[i];

    //print('for state: $state');

    if (i + 1 < splitString.length) {
      next_c = splitString[i + 1];
    } else {
      next_c = null;
    }

    if (state == OUTSIDE) {
      if (c == "'") {
        outputQuery.add(c);
        if (prev_c == "E") {
          state = INSIDE_ES;
        } else {
          state = INSIDE_SQ;
        }
      } else if (c == '"') {
        outputQuery.add(c);
        state = INSIDE_QI;
      } else if (c == "-") {
        outputQuery.add(c);
        if (prev_c == "-") {
          state = INSIDE_CO;
        }
        //ignore operator @@ or := :: @= ?? ?=
      } else if (c == placeholderIdentifier &&
          prev_c != placeholderIdentifier) {
        state = INSIDE_PN;
        
        //print('c == placeholder: $c');
        // placeholders.add("");
         outputQuery.add('\$$paramCount');
         paramCount++;
      } else {
        outputQuery.add(c);
      }
    }
    //
    else if (state == INSIDE_SQ) {
      if (c == "'") {
        if (in_quote_escape) {
          in_quote_escape = false;
        } else if (next_c == "'") {
          in_quote_escape = true;
        } else {
          state = OUTSIDE;
        }
      }
      outputQuery.add(c);
    }
    //
    else if (state == INSIDE_QI) {
      if (c == '"') {
        state = OUTSIDE;
      }
      outputQuery.add(c);
    }
    //
    else if (state == INSIDE_ES) {
      if (c == "'" && prev_c != "\\") {
        // check for escaped single-quote
        state = OUTSIDE;
      }
      outputQuery.add(c);
    }
    //
    else if (state == INSIDE_PN) {      
       if (next_c == null || (!Utils.isalnum(next_c) && next_c != "_")) {
         state = OUTSIDE;    
       }
      //print('state == INSIDE_PN: $c');
      outputQuery.add(c);
    }
    //
    else if (state == INSIDE_CO) {
      outputQuery.add(c);
      if (c == "\n") {
        state = OUTSIDE;
      }
    }
    prev_c = c;
  }

  final resultQuery = outputQuery.join('');
  //resultQuery = resultQuery.substring(0, resultQuery.length - 1);  
  return resultQuery.trim();
}
