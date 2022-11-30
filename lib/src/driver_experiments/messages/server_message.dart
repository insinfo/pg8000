class ServerMessage {
  final int code;

  ServerMessage(this.code);

  static final ServerMessage Authentication = ServerMessage('R'.codeUnitAt(0));
  static final ServerMessage BackendKeyData = ServerMessage('K'.codeUnitAt(0));
  static final ServerMessage Bind = ServerMessage('B'.codeUnitAt(0));
  static final ServerMessage BindComplete = ServerMessage('2'.codeUnitAt(0));
  static final ServerMessage CommandComplete = ServerMessage('C'.codeUnitAt(0));
  static final ServerMessage Close = ServerMessage('X'.codeUnitAt(0));
  static final ServerMessage CloseStatementOrPortal =
      ServerMessage('C'.codeUnitAt(0));
  static final ServerMessage CloseComplete = ServerMessage('3'.codeUnitAt(0));
  static final ServerMessage DataRow = ServerMessage('D'.codeUnitAt(0));
  static final ServerMessage Describe = ServerMessage('D'.codeUnitAt(0));
  static final ServerMessage Error = ServerMessage('E'.codeUnitAt(0));
  static final ServerMessage Execute = ServerMessage('E'.codeUnitAt(0));
  static final ServerMessage EmptyQueryString =
      ServerMessage('I'.codeUnitAt(0));
  static final ServerMessage NoData = ServerMessage('n'.codeUnitAt(0));
  static final ServerMessage Notice = ServerMessage('N'.codeUnitAt(0));
  static final ServerMessage NotificationResponse =
      ServerMessage('A'.codeUnitAt(0));
  static final ServerMessage ParameterStatus = ServerMessage('S'.codeUnitAt(0));
  static final ServerMessage Parse = ServerMessage('P'.codeUnitAt(0));
  static final ServerMessage ParseComplete = ServerMessage('1'.codeUnitAt(0));
  static final ServerMessage PasswordMessage = ServerMessage('p'.codeUnitAt(0));
  static final ServerMessage PortalSuspended = ServerMessage('s'.codeUnitAt(0));
  static final ServerMessage Query = ServerMessage('Q'.codeUnitAt(0));
  static final ServerMessage RowDescription = ServerMessage('T'.codeUnitAt(0));
  static final ServerMessage ReadyForQuery = ServerMessage('Z'.codeUnitAt(0));
  static final ServerMessage Sync = ServerMessage('S'.codeUnitAt(0));
}
