import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

void main() {
  group('stable image animation metadata', () {
    test('marks static images as non-animated', () {
      final bytes = image.encodePng(image.Image(width: 2, height: 2));
      final file = MatrixImageFile(bytes: bytes, name: 'static.png');

      expect(file.isAnimated, isFalse);
      expect(file.info['is_animated'], isFalse);
    });

    test('marks multi-frame images as animated', () {
      final source = image.Image(width: 2, height: 2)
        ..addFrame(image.Image(width: 2, height: 2));
      final bytes = image.encodeGif(source);
      final file = MatrixImageFile(bytes: bytes, name: 'animated.gif');

      expect(file.isAnimated, isTrue);
      expect(file.info['is_animated'], isTrue);
    });

    test('does not shrink animated images to a static frame', () async {
      final source = image.Image(width: 4, height: 4)
        ..addFrame(image.Image(width: 4, height: 4));
      final bytes = image.encodeGif(source);

      final shrunk = await MatrixImageFile.shrink(
        bytes: bytes,
        name: 'animated.gif',
        maxDimension: 1,
      );

      expect(shrunk.isAnimated, isTrue);
      expect(identical(shrunk.bytes, bytes), isTrue);
      expect(shrunk.info['is_animated'], isTrue);
    });

    test('omits animation metadata when the image cannot be decoded', () {
      final file = MatrixImageFile(
        bytes: Uint8List.fromList([0, 1, 2, 3]),
        name: 'broken.png',
        mimeType: 'image/png',
      );

      expect(file.isAnimated, isNull);
      expect(file.info.containsKey('is_animated'), isFalse);
    });
  });
}
