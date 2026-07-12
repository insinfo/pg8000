import 'dart:convert';
import 'dart:typed_data';

import '../../../../saslprep/saslprep_export.dart';

import '../../../sasl_scram_exception.dart';
import '../../../utils/parsing.dart';
import '../../../utils/sasl.dart';
import '../../../utils/typed_data.dart';
import '../../../../../utils/crypto.dart';
import '../../auth.dart';
import '../../sasl_authenticator.dart';
import 'client_last.dart';

class ClientFirst extends SaslStep {
  final String clientFirstMessageBare;
  final UsernamePasswordCredential credential;
  final String rPrefix;
  final Hash hash;

  ClientFirst(super.bytesToSendToServer, this.hash, this.credential,
      this.clientFirstMessageBare, this.rPrefix);

  @override
  SaslStep transition(List<int> bytesReceivedFromServer,
      {PasswordDigestResolver? passwordDigestResolver}) {
    final serverFirstMessage = utf8.decode(bytesReceivedFromServer);

    final Map<String, dynamic> decodedMessage =
        parsePayload(serverFirstMessage);

    final r = decodedMessage['r'] as String?;
    if (r == null || !r.startsWith(rPrefix)) {
      throw SaslScramException('Server sent an invalid nonce.');
    }

    final s = decodedMessage['s'];
    final i = int.parse(decodedMessage['i'].toString());

    final encodedHeader = base64.encode(utf8.encode(gs2Header));
    final channelBinding = 'c=$encodedHeader';
    final nonce = 'r=$r';
    final clientFinalMessageWithoutProof = '$channelBinding,$nonce';

    String passwordDigest;
    if (passwordDigestResolver != null) {
      passwordDigest = passwordDigestResolver(credential);
    } else {
      passwordDigest = Saslprep.saslprep(credential.password!);
    }

    final salt = base64.decode(s.toString());

    final saltedPassword = hi(passwordDigest, salt, i, hash);
    final clientKey = computeHMAC(saltedPassword, 'Client Key', hash);
    final storedKey = h(clientKey, hash);
    final authMessage =
        '$clientFirstMessageBare,$serverFirstMessage,$clientFinalMessageWithoutProof';
    final clientSignature = computeHMAC(storedKey, authMessage, hash);
    final clientProof = xor(clientKey, clientSignature);
    final serverKey = computeHMAC(saltedPassword, 'Server Key', hash);
    final serverSignature = computeHMAC(serverKey, authMessage, hash);

    final base64clientProof = base64.encode(clientProof);
    final proof = 'p=$base64clientProof';
    final clientFinalMessage = '$clientFinalMessageWithoutProof,$proof';

    return ClientLast(
        coerceUint8List(utf8.encode(clientFinalMessage)), serverSignature);
  }

  static Uint8List computeHMAC(Uint8List data, String key, Hash hash) {
    return hmac(hash, data, utf8.encode(key));
  }

  static Uint8List h(Uint8List data, Hash hash) {
    return hash.convert(data);
  }

  static Uint8List xor(Uint8List a, Uint8List b) {
    final length = a.length < b.length ? a.length : b.length;
    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }

  static Uint8List hi(
      String password, Uint8List salt, int iterations, Hash hash) {
    return pbkdf2Hmac(hash, utf8.encode(password), salt, iterations);
  }
}
