import 'dart:typed_data';
import 'package:crclib/catalog.dart';

class TinyFrame {
  Function? write; // the writer function should be attached here

  Map<int, Map<String, dynamic>?> idListeners = {};
  Map<int, Map<String, dynamic>?> typeListeners = {};
  Map<String, dynamic>? fallbackListener;
  int peer; // the peer bit

  // ----------------------------- FRAME FORMAT ---------------------------------
  // The format can be adjusted to fit your particular application needs

  // If the connection is reliable, you can disable the SOF byte and checksums.
  // That can save up to 9 bytes of overhead.

  // ,-----+-----+-----+------+------------+- - - -+-------------,
  // | SOF | ID  | LEN | TYPE | HEAD_CKSUM | DATA  | DATA_CKSUM  |
  // | 0-1 | 1-4 | 1-4 | 1-4  | 0-4        | ...   | 0-4         | <- size (bytes)
  // '-----+-----+-----+------+------------+- - - -+-------------'
  //
  // SOF ......... start of frame, usually 0x01 (optional, configurable)
  // ID  ......... the frame ID (MSb is the peer bit)
  // LEN ......... number of data bytes in the frame
  // TYPE ........ message type (used to run Type Listeners, pick any values you like)
  // HEAD_CKSUM .. header checksum
  //
  // DATA ........ LEN bytes of data (can be 0, in which case DATA_CKSUM is omitted as well)
  // DATA_CKSUM .. checksum, implemented as XOR of all preceding bytes in the message

  //  !!! BOTH SIDES MUST USE THE SAME SETTINGS !!!
  // Settings can be adjusted by setting the properties after init

  // Adjust sizes as desired (1,2,4)
  int fieldIdBytes = 2;
  int fieldLenBytes = 2;
  int fieldTypeBytes = 1;

  // Checksum type
  // ('none', 'xor', 'crc16, 'crc32'
  String cksumType = 'xor';

  // Use a SOF byte to mark the start of a frame
  bool useFieldSofByte = true;
  // Value of the SOF byte (if TF_USE_SOF_BYTE == 1)
  int fieldSofValue = 0x01;
  // counter
  int nextFrameId = 0;

  int _fieldCksumBytes = 0;

  late String ps;
  late Uint8List rbuf;
  late int rlen;
  late Uint8List rpayload;
  late TF_Msg rf;

  TinyFrame(this.write, {this.peer = 1}) {
    resetParser();
  }

  void resetParser() {
    // parser state: SOF, ID, LEN, TYPE, HCK, PLD, PCK
    ps = 'SOF';
    // buffer for receiving bytes
    rbuf = Uint8List(0);
    // expected number of bytes to receive
    rlen = 0;
    // buffer for payload or checksum
    rpayload = Uint8List(0);
    // received frame
    rf = TF_Msg();
  }

  int _calcCksumBytes() {
    if (cksumType == 'none' || cksumType.isEmpty) {
      return 0;
    } else if (cksumType == 'xor') {
      return 1;
    } else if (cksumType == 'crc16') {
      return 2;
    } else if (cksumType == 'crc32') {
      return 4;
    } else {
      throw Exception("Bad cksum type!");
    }
  }

  int _cksum(Uint8List buffer) {
    if (cksumType == 'none' || cksumType.isEmpty) {
      return 0;
    } else if (cksumType == 'xor') {
      int acc = 0;
      for (int b in buffer) {
        acc ^= b;
      }
      return (~acc) & ((1 << (_fieldCksumBytes * 8)) - 1);
    } else if (cksumType == 'crc16') {
      return Crc16().convert(buffer).toBigInt().toInt();
    } else {
      return Crc32().convert(buffer).toBigInt().toInt();
    }
  }

  int _genFrameId() {
    int frameId = nextFrameId;

    nextFrameId += 1;
    if (nextFrameId > ((1 << (8 * fieldIdBytes - 1)) - 1)) {
      nextFrameId = 0;
    }

    if (peer == 1) {
      frameId |= 1 << (8 * fieldIdBytes - 1);
    }

    return frameId;
  }

  Uint8List _pack(int num, int bytes) => Uint8List.fromList(
      [for (int i = bytes - 1; i >= 0; i--) (num >> (i * 8)) & 0xFF]);

  int _unpack(Uint8List buf) {
    var result = 0;
    for (var i = 0; i < buf.length; i++) {
      result = (result << 8) | buf[i];
    }
    return result;
  }

  void query(int type, Function? listener, {Uint8List? pld, int? id}) {
    // Send a query
    final (id2, buf) = _compose(type: type, pld: pld, id: id);

    if (listener != null) {
      addIdListener(id2, listener);
    }

    // test if write is null, then invoke
    if (write != null) {
      write!(buf);
    }
  }

  void send(int type, Uint8List? pld, {int? id}) {
    // Like query, but with no listener
    query(type, null, pld: pld, id: id);
  }

  (int, Uint8List) _compose({required int type, Uint8List? pld, int? id}) {
    if (_fieldCksumBytes == 0) {
      _fieldCksumBytes = _calcCksumBytes();
    }

    pld ??= Uint8List(0);

    id ??= _genFrameId();

    final buf = <int>[];
    if (useFieldSofByte) {
      buf.addAll(_pack(fieldSofValue, 1));
    }

    buf.addAll(_pack(id, fieldIdBytes));
    buf.addAll(_pack(pld.length, fieldLenBytes));
    buf.addAll(_pack(type, fieldTypeBytes));

    if (_fieldCksumBytes > 0) {
      buf.addAll(_pack(_cksum(Uint8List.fromList(buf)), _fieldCksumBytes));
    }

    if (pld.isNotEmpty) {
      buf.addAll(pld);
      buf.addAll(_pack(_cksum(pld), _fieldCksumBytes));
    }

    return (id, Uint8List.fromList(buf));
  }

  void accept(Uint8List bytes) {
    // Parse bytes received on the serial port
    for (int b in bytes) {
      acceptByte(b);
    }
  }

  void acceptByte(int b) {
    if (_fieldCksumBytes == 0) {
      _fieldCksumBytes = _calcCksumBytes();
    }

    if (ps == 'SOF') {
      if (useFieldSofByte) {
        if (b != fieldSofValue) {
          return;
        }

        rpayload = Uint8List(0);
        rpayload = Uint8List.fromList([...rpayload, b]);
      }

      ps = 'ID';
      rlen = fieldIdBytes;
      rbuf = Uint8List(0);

      if (useFieldSofByte) {
        return;
      }
    }

    if (ps == 'ID') {
      rpayload = Uint8List.fromList([...rpayload, b]);
      rbuf = Uint8List.fromList([...rbuf, b]);

      if (rbuf.length == rlen) {
        rf.id = _unpack(rbuf);

        ps = 'LEN';
        rlen = fieldLenBytes;
        rbuf = Uint8List(0);
      }
      return;
    }

    if (ps == 'LEN') {
      rpayload = Uint8List.fromList([...rpayload, b]);
      rbuf = Uint8List.fromList([...rbuf, b]);

      if (rbuf.length == rlen) {
        rf.len = _unpack(rbuf);

        ps = 'TYPE';
        rlen = fieldTypeBytes;
        rbuf = Uint8List(0);
      }
      return;
    }

    if (ps == 'TYPE') {
      rpayload = Uint8List.fromList([...rpayload, b]);
      rbuf = Uint8List.fromList([...rbuf, b]);

      if (rbuf.length == rlen) {
        rf.type = _unpack(rbuf);

        if (_fieldCksumBytes > 0) {
          ps = 'HCK';
          rlen = _fieldCksumBytes;
          rbuf = Uint8List(0);
        } else {
          ps = 'PLD';
          rlen = rf.len;
          rbuf = Uint8List(0);
        }
      }
      return;
    }

    if (ps == 'HCK') {
      rbuf = Uint8List.fromList([...rbuf, b]);

      if (rbuf.length == rlen) {
        int hck = _unpack(rbuf);
        int actual = _cksum(rpayload);

        if (hck != actual) {
          resetParser();
        } else {
          if (rf.len == 0) {
            handleRxFrame();
            resetParser();
          } else {
            ps = 'PLD';
            rlen = rf.len;
            rbuf = Uint8List(0);
            rpayload = Uint8List(0);
          }
        }
      }
      return;
    }

    if (ps == 'PLD') {
      rpayload = Uint8List.fromList([...rpayload, b]);
      rbuf = Uint8List.fromList([...rbuf, b]);

      if (rbuf.length == rlen) {
        rf.data = rpayload;

        if (_fieldCksumBytes > 0) {
          ps = 'PCK';
          rlen = _fieldCksumBytes;
          rbuf = Uint8List(0);
        } else {
          handleRxFrame();
          resetParser();
        }
      }
      return;
    }

    if (ps == 'PCK') {
      rbuf = Uint8List.fromList([...rbuf, b]);

      if (rbuf.length == rlen) {
        int pck = _unpack(rbuf);
        int actual = _cksum(rpayload);

        if (pck != actual) {
          resetParser();
        } else {
          handleRxFrame();
          resetParser();
        }
      }
      return;
    }
  }

  void handleRxFrame() {
    final frame = rf;

    if (idListeners.containsKey(frame.id) && idListeners[frame.id] != null) {
      final lst = idListeners[frame.id]!;
      final rv = lst['fn']!(this, frame);
      if (rv == TF.CLOSE || rv == null) {
        idListeners[frame.id] = null;
        return;
      } else if (rv == TF.RENEW) {
        lst['age'] = 0;
        return;
      } else if (rv == TF.STAY) {
        return;
      }
      // TF.NEXT lets another handler process it
    }

    if (typeListeners.containsKey(frame.type) &&
        typeListeners[frame.type] != null) {
      final lst = typeListeners[frame.type]!;
      final rv = lst['fn']!(this, frame);
      if (rv == TF.CLOSE) {
        typeListeners[frame.type] = null;
        return;
      } else if (rv != TF.NEXT) {
        return;
      }
    }

    if (fallbackListener != null) {
      final lst = fallbackListener!;
      final rv = lst['fn']!(this, frame);
      if (rv == TF.CLOSE) {
        fallbackListener = null;
      }
    }
  }

  void addIdListener(int id, Function lst, {double? lifetime}) {
    // Add a ID listener that expires in "lifetime" seconds
    idListeners[id] = {
      'fn': lst,
      'lifetime': lifetime,
      'age': 0,
    };
  }

  void addTypeListener(int type, Function lst) {
    // Add a type listener
    typeListeners[type] = {
      'fn': lst,
    };
  }

  void addFallbackListener(Function lst) {
    // Add a fallback listener
    fallbackListener = {
      'fn': lst,
    };
  }
}

class TF_Msg {
  /// A TF message object
  Uint8List data = Uint8List(0);
  int len = 0;
  int type = 0;
  int id = 0;

  @override
  String toString() {
    return 'ID ${id.toRadixString(16)}h, type ${type.toRadixString(16)}h, len $len, body: $data';
  }
}

class TF {
  /// Constants
  static const String STAY = 'STAY';
  static const String RENEW = 'RENEW';
  static const String CLOSE = 'CLOSE';
  static const String NEXT = 'NEXT';
}
