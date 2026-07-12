/// FieldDescription
class ColumnDescription {
  final int index;
  final String name;

  final int fieldId;
  final int tableColNo;
  final int fieldType;
  final int dataSize;
  final int typeModifier;
  final int formatCode;
  bool get isBinary => formatCode == 1;

  ColumnDescription(this.index, this.name, this.fieldId, this.tableColNo,
      this.fieldType, this.dataSize, this.typeModifier, this.formatCode);

  @override
  String toString() =>
      'Column: index: $index, name: $name, fieldId: $fieldId, tableColNo: $tableColNo, fieldType: $fieldType, dataSize: $dataSize, typeModifier: $typeModifier, formatCode: $formatCode.';
}
