class SerialConnectionParams {
  SerialConnectionParams({
    required this.port,
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'None',
  });

  final String port;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final String parity;

  String get displayName => '$port ${baudRate}bps';

  static const baudRatePresets = [
    300,
    1200,
    2400,
    4800,
    9600,
    14400,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];
  static const dataBitsOptions = [5, 6, 7, 8];
  static const stopBitsOptions = [1, 2];
  static const parityOptions = ['None', 'Odd', 'Even', 'Mark', 'Space'];
}
