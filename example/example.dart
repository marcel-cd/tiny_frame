import 'dart:typed_data';

import 'package:tiny_frame/tiny_frame.dart';

void write(Uint8List data) => print('write: $data');
void main() {
  const mainID = 1;
  // create a TinyFrame instance as master (peer id set)
  // the write method has to be implemented, tinyframe will call it
  // to send the data after building the frame
  final tf = TinyFrame(write);
  // some optional settings
  tf.cksumType = 'xor';
  // generate a listener for the id 1
  tf.addIdListener(mainID, (Uint8List frame) => print('main: $frame'));
  // if no listener is found for the id, this listener will be called
  tf.addFallbackListener((Uint8List frame) => print('fallback: $frame'));

  // send to slave on id 1
  tf.send(mainID, Uint8List.fromList('abcde'.codeUnits));
}
