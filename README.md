Port of the TinyFrame C library from https://github.com/MightyPork/TinyFrame

Used an automated code conversion tool from to port https://github.com/MightyPork/PonyFrame from python to dart with some minor modifications

## Features

TinyFrame is a simple library for building and parsing data frames to be sent over a serial interface (e.g. UART, telnet, socket). 

## Usage

```dart
import 'dart:typed_data';
import 'package:tiny_frame/tiny_frame.dart';

void main() {
  const typeID = 1;
  // create a TinyFrame instance with a write function
  // TF_WriteImpl in C Library
  final tf = TinyFrame((Uint8List data) => print('write: $data'));
  // some optional settings
  tf.cksumType = 'xor';
  // generate a listener for the id 1
  tf.addTypeListener(typeID, (_, TF_Msg msg) => print('main: $msg'));
  // if no listener is found for the id, this listener will be called
  tf.addFallbackListener((_, TF_Msg msg) => print('fallback: $msg'));
  // send to slave on id 1
  tf.send(typeID, Uint8List.fromList('abcde'.codeUnits));
}
```


## TinyFrame
```sh
,-----+-----+-----+------+------------+- - - -+-------------,
| SOF | ID  | LEN | TYPE | HEAD_CKSUM | DATA  | DATA_CKSUM  |
| 0-1 | 1-4 | 1-4 | 1-4  | 0-4        | ...   | 0-4         | <- size (bytes)
'-----+-----+-----+------+------------+- - - -+-------------'

SOF ......... start of frame, usually 0x01 (optional, configurable)
ID  ......... the frame ID (MSb is the peer bit)
LEN ......... number of data bytes in the frame
TYPE ........ message type (used to run Type Listeners, pick any values you like)
HEAD_CKSUM .. header checksum

DATA ........ LEN bytes of data
DATA_CKSUM .. data checksum (left out if LEN is 0)
```

