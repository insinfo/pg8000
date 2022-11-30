import '../authentication_request_type.dart';
import 'server_message.dart';

class AuthenticationRequestMessage {
  ServerMessage code = ServerMessage.Authentication;
  AuthenticationRequestType authRequestType;
  AuthenticationRequestMessage(this.authRequestType);
}
