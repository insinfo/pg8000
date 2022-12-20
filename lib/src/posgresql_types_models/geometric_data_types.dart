/// https://www.postgresql.org/docs/current/datatype-geometric.html
/// Geometric data types represent two-dimensional spatial objects
/// Name	Storage Size	Description	Representation
/// point	16 bytes	Point on a plane	(x,y)
class PostgrePoint {
  double x;
  double y;
  final String name = 'point';

  PostgrePoint(this.x, this.y);

  factory PostgrePoint.fromString(String str) {
    var vals = str.replaceAll('(', '').replaceAll(')', '').split(',');
    return PostgrePoint(double.parse(vals[0]), double.parse(vals[1]));
  }

  @override
  String toString() {
    return '($x,$y)';
  }
}

/// Infinite line
/// 32 bytes 	{A,B,C}
/// Lines are represented by the linear equation Ax + By + C = 0, where A and B are not both zero.
/// Values of type line are input and output in the following form: { A, B, C }
class PostgreLine {
  /// ( x1 , y1 )
  PostgrePoint p1;

  /// ( x2 , y2 )
  PostgrePoint p2;
  final String name = 'line';

  PostgreLine({this.p1, this.p2});
  // { A, B, C } Ex: {0,-1,3}
  PostgreLine.fromLinearEquation(String str) {
    //Convert line equation to two points: Ax + By + C = 0, onde A = 1, B =-1, C = 2
    var line = str;
    if (str.contains('(')) {
      line = str.replaceFirst('(', '').replaceFirst(')', '');
    } else if (str.contains('{')) {
      line = str.replaceFirst('{', '').replaceFirst('}', '');
    }

    var vals = line.split(',');
    var A = double.parse(vals[0]); // 1.3333333333333333
    var B = double.parse(vals[1]); // -1
    var C = double.parse(vals[2]); // 0.3333333333333335
    var solve = _lineEquationToPoints(A, B, C);
    p1 = solve[0];
    p2 = solve[1];
  }

  List<PostgrePoint> _lineEquationToPoints(num A, num B, num C) {
    // Calculate the slope
    var slope = -A / B;

    // Calculate the y-intercept
    var y_intercept = -C / B;

    // Find the first point by setting x = 0 and solving for y
    double x1 = 2;
    var y1 = slope * x1 + y_intercept;

    // Find the second point by setting x = 1 and solving for y
    double x2 = 5;
    var y2 = slope * x2 + y_intercept;

    // Return the two points as a tuple
    return [PostgrePoint(x1, y1), PostgrePoint(x2, y2)];
  }

  //https://math.stackexchange.com/questions/422602/convert-two-points-to-line-eq-ax-by-c-0
  String _pointsToLine(double x1, double y1, double x2, double y2) {
    // Calculate the slope
    double slope = (y2 - y1) / (x2 - x1);

    // Calculate the y-intercept
    double yIntercept = y1 - slope * x1;

    // Calculate A, B, and C
    double A = slope;
    double B = -1;
    double C = yIntercept;

    // Return the line equation
    return "{$A,$B,$C}";
  }

  @override
  String toString() {
    if (p1 == null || p2 == null) {
      return null;
    }
    return _pointsToLine(p1.x, p1.y, p2.x, p2.y);
  }
}

/// Finite line segment
/// 32 bytes
class PostgreLineSegment {
  PostgrePoint start;
  PostgrePoint end;
  final String name = 'lseg';

  PostgreLineSegment({this.start, this.end});

  @override
  String toString() {
    return '( ( ${start.x},${start.y} ) , ( ${end.x},${end.y}  ) )';
  }
}

class PostgreBox {
  ///top Left corner
  /// x1 , y1
  PostgrePoint topLeft;

  ///bottom right corner
  /// x2 , y2
  PostgrePoint bottomRight;
  final String name = 'box';

  PostgreBox({this.topLeft, this.bottomRight});

  @override
  String toString() {
    return '((${topLeft.x},${topLeft.y}),(${bottomRight.x},${bottomRight.y})';
  }
}

/// Paths are represented by lists of connected points
/// Closed path (similar to polygon)  ((x1,y1),...)
/// Open path [(x1,y1),...]
/// 16+16n bytes
class PostgrePath {
  List<PostgrePoint> segments = [];
  final String name = 'path';

  PostgrePath({this.segments});

  @override
  String toString() {
    return '(${segments.map((e) => e.toString()).join(',')})';
  }
}

/// Polygons are represented by lists of points (the vertexes of the polygon)
/// Polygon (similar to closed path)
/// 40+16n bytes ((x1,y1),...)
class PostgrePolygon {
  List<PostgrePoint> segments = [];
  final String name = 'polygon';

  PostgrePolygon({this.segments});

  @override
  String toString() {
    return '(${segments.map((e) => e.toString()).join(',')})';
  }
}

/// Polygon (similar to closed path)
/// 24 bytes <(x,y),r> (center point and radius)
class PostgreCircle {
  /// center point
  PostgrePoint centerPoint;

  /// radius
  double radius;
  final String name = 'circle';

  PostgreCircle({this.centerPoint, this.radius});

  @override
  String toString() {
    return '<(${centerPoint.x},${centerPoint.y}),$radius>';
  }
}
