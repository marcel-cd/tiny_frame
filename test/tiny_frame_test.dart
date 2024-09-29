import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tiny_frame/tiny_frame.dart';

void main() {
  group('Sending Tests', () {
    test('Sending CRC xor', () {
      var result = Uint8List(0);
      final tf = TinyFrame((Uint8List data) => result = data);
      tf.send(1, Uint8List.fromList('abcde'.codeUnits));
      expect(
          result,
          Uint8List.fromList(
              [1, 128, 0, 0, 5, 1, 122, 97, 98, 99, 100, 101, 158]));
    });
  });
  group('Receiving Tests', () {
    test('Fallback Listener', () {
      var result = Uint8List(0);
      final tf = TinyFrame(() => ());
      tf.write = (Uint8List data) => {tf.accept(data)};
      tf.addFallbackListener((_, TF_Msg msg) => result = msg.data);
      final abcde = Uint8List.fromList('abcde'.codeUnits);
      tf.send(1, abcde);
      expect(result, abcde);
    });
    test('Type Listener', () {
      var result = Uint8List(0);
      final tf = TinyFrame(() => ());
      tf.write = (Uint8List data) => {tf.accept(data)};
      tf.addTypeListener(
          1, (_, TF_Msg msg) => result = msg.data);
      final abcde = Uint8List.fromList('abcde'.codeUnits);
      tf.send(1, abcde);
      expect(result, abcde);
    });
  });
}
