// SPDX-FileCopyrightText: 2026 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_client.dart';

void main() {
  group('Stable MSC4356 recent emoji', () {
    late Client client;

    setUpAll(() async {
      client = await getClient();
    });

    tearDownAll(() async {
      await client.dispose(closeDatabase: true);
    });

    test('reads stable object format in last-used order', () {
      client.accountData[EventTypes.RecentEmoji] = BasicEvent.fromJson({
        'type': EventTypes.RecentEmoji,
        'content': {
          'recent_emoji': [
            {'emoji': '😅', 'total': 7},
            {'emoji': '👍', 'total': 84},
          ],
        },
      });

      expect(client.recentEmojis.keys.toList(), ['😅', '👍']);
      expect(client.recentEmojis['😅'], 7);
      expect(client.recentEmojis['👍'], 84);
    });

    test('stable account data takes precedence over legacy Element data', () {
      client.accountData['io.element.recent_emoji'] = BasicEvent.fromJson({
        'type': 'io.element.recent_emoji',
        'content': {
          'recent_emoji': [
            ['🦙', 99],
          ],
        },
      });

      expect(client.recentEmojis.keys.toList(), ['😅', '👍']);
      expect(client.recentEmojis.containsKey('🦙'), false);
    });

    test('falls back to historical Element tuple format', () {
      client.accountData.remove(EventTypes.RecentEmoji);
      client.accountData['io.element.recent_emoji'] = BasicEvent.fromJson({
        'type': 'io.element.recent_emoji',
        'content': {
          'recent_emoji': [
            ['🦙', 4],
            ['🖇️', 2],
          ],
        },
      });

      expect(client.recentEmojis, {'🦙': 4, '🖇️': 2});
    });

    test('ignores invalid counters and duplicate trailing entries', () {
      client.accountData[EventTypes.RecentEmoji] = BasicEvent.fromJson({
        'type': EventTypes.RecentEmoji,
        'content': {
          'recent_emoji': [
            {'emoji': '😺', 'total': 3},
            {'emoji': 'bad-negative', 'total': -1},
            {'emoji': '😺', 'total': 100},
            {'emoji': 'bad-float', 'total': 1.5},
          ],
        },
      });

      expect(client.recentEmojis, {'😺': 3});
    });
  });
}
