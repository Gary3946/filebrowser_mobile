import 'package:flutter_test/flutter_test.dart';

import 'package:filebrowser_mobile/src/api/models.dart';
import 'package:filebrowser_mobile/src/ui/share_actions.dart';

FbResource _file(String name, int size) =>
    FbResource(path: '/$name', name: name, size: size, isDir: false);

FbResource _dir(String name) =>
    FbResource(path: '/$name/', name: name, size: 0, isDir: true);

void main() {
  group('shareOptionsFor', () {
    test('empty selection offers nothing', () {
      final o = shareOptionsFor(const []);
      expect(o.canShareLink, isFalse);
      expect(o.canSendFiles, isFalse);
      expect(o.totalSendBytes, 0);
    });

    test('a single file offers both link and send', () {
      final o = shareOptionsFor([_file('a.txt', 42)]);
      expect(o.canShareLink, isTrue);
      expect(o.canSendFiles, isTrue);
      expect(o.totalSendBytes, 42);
    });

    test('a single folder offers a link but not sending', () {
      final o = shareOptionsFor([_dir('photos')]);
      expect(o.canShareLink, isTrue);
      expect(o.canSendFiles, isFalse);
      expect(o.totalSendBytes, 0);
    });

    test('multiple files offer sending (with summed size) but no link', () {
      final o = shareOptionsFor([_file('a.txt', 10), _file('b.txt', 30)]);
      expect(o.canShareLink, isFalse);
      expect(o.canSendFiles, isTrue);
      expect(o.totalSendBytes, 40);
    });

    test('a folder in a multi-selection disables sending too', () {
      final o = shareOptionsFor([_file('a.txt', 10), _dir('photos')]);
      expect(o.canShareLink, isFalse);
      expect(o.canSendFiles, isFalse);
      expect(o.totalSendBytes, 0);
    });
  });
}
