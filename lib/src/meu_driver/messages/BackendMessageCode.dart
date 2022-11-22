class BackendMessageCode {
  final int code;
  const BackendMessageCode(this.code);

  static final BackendMessageCode AuthenticationRequest =
      BackendMessageCode('R'.codeUnitAt(0));
  static final BackendMessageCode BackendKeyData =
      BackendMessageCode('K'.codeUnitAt(0));
  static final BackendMessageCode BindComplete =
      BackendMessageCode('2'.codeUnitAt(0));
  static final BackendMessageCode CloseComplete =
      BackendMessageCode('3'.codeUnitAt(0));
  static final BackendMessageCode CommandComplete =
      BackendMessageCode('C'.codeUnitAt(0));
  static final BackendMessageCode CopyData =
      BackendMessageCode('d'.codeUnitAt(0));
  static final BackendMessageCode CopyDone =
      BackendMessageCode('c'.codeUnitAt(0));
  static final BackendMessageCode CopyBothResponse =
      BackendMessageCode('W'.codeUnitAt(0));
  static final BackendMessageCode CopyInResponse =
      BackendMessageCode('G'.codeUnitAt(0));
  static final BackendMessageCode CopyOutResponse =
      BackendMessageCode('H'.codeUnitAt(0));
  static final BackendMessageCode DataRow =
      BackendMessageCode('D'.codeUnitAt(0));
  static final BackendMessageCode EmptyQueryResponse =
      BackendMessageCode('I'.codeUnitAt(0));
  static final BackendMessageCode ErrorResponse =
      BackendMessageCode('E'.codeUnitAt(0));
  static final BackendMessageCode FunctionCall =
      BackendMessageCode('F'.codeUnitAt(0));
  static final BackendMessageCode FunctionCallResponse =
      BackendMessageCode('V'.codeUnitAt(0));
  static final BackendMessageCode NoData =
      BackendMessageCode('n'.codeUnitAt(0));
  static final BackendMessageCode NoticeResponse =
      BackendMessageCode('N'.codeUnitAt(0));
  static final BackendMessageCode NotificationResponse =
      BackendMessageCode('A'.codeUnitAt(0));
  static final BackendMessageCode ParameterDescription =
      BackendMessageCode('t'.codeUnitAt(0));
  static final BackendMessageCode ParameterStatus =
      BackendMessageCode('S'.codeUnitAt(0));
  static final BackendMessageCode ParseComplete =
      BackendMessageCode('1'.codeUnitAt(0));
  static final BackendMessageCode PasswordPacket =
      BackendMessageCode(' '.codeUnitAt(0));
  static final BackendMessageCode PortalSuspended =
      BackendMessageCode('s'.codeUnitAt(0));
  static final BackendMessageCode ReadyForQuery =
      BackendMessageCode('Z'.codeUnitAt(0));
  static final BackendMessageCode RowDescription =
      BackendMessageCode('T'.codeUnitAt(0));
}
