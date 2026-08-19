// SPDX-FileCopyrightText: 2019-Present, 2020 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/src/utils/copy_map.dart';
import 'package:test/test.dart';

void main() {
  group('Map-copy-extension', () {
    test('it should work', () {
      final original = <String, dynamic>{
        'attr': 'fox',
        'child': <String, dynamic>{
          'attr': 'bunny',
          'list': [1, 2],
        },
      };
      final copy = copyMap(original);
      original['child']['attr'] = 'raccoon';
      expect((copy['child'] as Map)['attr'], 'bunny');
      original['child']['list'].add(3);
      expect((copy['child'] as Map)['list'], [1, 2]);
    });

    test('it normalizes nested maps with non-specific key types', () {
      final copy = copyMap(<Object?, Object?>{
        'content': <Object?, Object?>{'body': 'hello'},
        'unsigned': <Object?, Object?>{
          'm.thread': <Object?, Object?>{
            'latest_event': <Object?, Object?>{
              'content': <Object?, Object?>{'body': 'reply'},
            },
          },
        },
      });

      expect(copy['content'], <String, Object?>{'body': 'hello'});
      expect((copy['unsigned'] as Map)['m.thread'], <String, Object?>{
        'latest_event': <String, Object?>{
          'content': <String, Object?>{'body': 'reply'},
        },
      });
    });
  });
}
