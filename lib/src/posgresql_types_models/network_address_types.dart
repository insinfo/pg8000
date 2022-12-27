/// https://www.postgresql.org/docs/current/datatype-net-types.html#:~:text=2.-,cidr,of%20bits%20in%20the%20netmask
///
/// cidr	7 or 19 bytes	IPv4 and IPv6 networks
/// Example: PostgreCidr('2001:4f8:3:ba:​2e0:81ff:fe22:d1f1/128');
/// PostgreCidr('10.1.2.3/32');
/// The essential difference between inet and cidr data types is that inet accepts values
/// with nonzero bits to the right of the netmask, whereas cidr does not.
/// For example, 192.168.0.1/24 is valid for inet but not for cidr.
class PostgreCidr {
  final String name = 'cidr';

  /// ex: 192.168.100.128/25
  String ip;

  PostgreCidr({required this.ip});

  @override
  String toString() {
    return '{$ip}';
  }
}

/// 7 or 19 bytes	IPv4 and IPv6 hosts and networks
/// The essential difference between inet and cidr data types is that inet accepts values
/// with nonzero bits to the right of the netmask, whereas cidr does not.
/// For example, 192.168.0.1/24 is valid for inet but not for cidr.
class PostgreInet {
  final String name = 'inet';

  String ip;

  PostgreInet({required this.ip});

  @override
  String toString() {
    return '{$ip}';
  }
}

/// 6 bytes	MAC addresses
class PostgreMacaddr {
  final String name = 'macaddr';

  /// Example: '08:00:2b:01:02:03'
  String mac;

  PostgreMacaddr({required this.mac});

  @override
  String toString() {
    return '{$mac}';
  }
}

/// macaddr8	8 bytes	MAC addresses (EUI-64 format)
class PostgreMacaddr8 {
  final String name = 'macaddr8';

  /// Example: '08-00-2b-01-02-03-04-05'
  String mac;

  PostgreMacaddr8({required this.mac});

  @override
  String toString() {
    return '{$mac}';
  }
}
