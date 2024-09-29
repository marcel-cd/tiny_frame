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
