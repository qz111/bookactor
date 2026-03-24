import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SHA-256 of known bytes is 64 hex characters', () {
    final bytes = utf8.encode('hello world');
    final digest = sha256.convert(bytes);
    expect(digest.toString().length, equals(64));
  });

  test('SHA-256 is deterministic for same input', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final d1 = sha256.convert(bytes).toString();
    final d2 = sha256.convert(bytes).toString();
    expect(d1, equals(d2));
  });

  test('SHA-256 differs for different inputs', () {
    final d1 = sha256.convert(utf8.encode('abc')).toString();
    final d2 = sha256.convert(utf8.encode('xyz')).toString();
    expect(d1, isNot(equals(d2)));
  });

  test('SHA-256 of concatenated multi-image bytes differs from single image', () {
    final img1 = Uint8List.fromList([1, 2, 3]);
    final img2 = Uint8List.fromList([4, 5, 6]);
    final combined = Uint8List.fromList([...img1, ...img2]);
    final multiHash = sha256.convert(combined).toString();
    final singleHash = sha256.convert(img1).toString();
    expect(multiHash, isNot(equals(singleHash)));
  });

  test('SHA-256 of concatenated multi-image bytes is deterministic', () {
    final img1 = Uint8List.fromList([1, 2, 3]);
    final img2 = Uint8List.fromList([4, 5, 6]);
    final combined = Uint8List.fromList([...img1, ...img2]);
    final hash1 = sha256.convert(combined).toString();
    final hash2 = sha256.convert(combined).toString();
    expect(hash1, equals(hash2));
  });
}
