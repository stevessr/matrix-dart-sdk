// SPDX-FileCopyrightText: 2026 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_client.dart';

Map<String, Object?> _nameEvent(String name, String eventId) => {
  'sender': '@alice:example.com',
  'type': EventTypes.RoomName,
  'content': {'name': name},
  'state_key': '',
  'origin_server_ts': 1417731086799,
  'event_id': eventId,
};

void main() {
  test('sync models preserve state_after presence including empty', () {
    final update = SyncUpdate.fromJson({
      'next_batch': 'next',
      'rooms': {
        'join': {
          '!joined:example.com': {
            'state_after': {'events': <Object?>[]},
          },
        },
        'leave': {
          '!left:example.com': {
            'state_after': {
              'events': [_nameEvent('Left', r'$left')],
            },
          },
        },
      },
    });

    expect(update.rooms!.join!['!joined:example.com']!.stateAfter, isEmpty);
    expect(update.rooms!.leave!['!left:example.com']!.stateAfter, hasLength(1));

    final json = update.toJson();
    final rooms = json['rooms'] as Map<String, Object?>;
    final join = rooms['join'] as Map<String, Object?>;
    final joined = join['!joined:example.com'] as Map<String, Object?>;
    expect(joined.containsKey('state_after'), isTrue);
  });

  test('state_after wins over timeline state events', () async {
    final client = await getClient();
    await client.abortSync();
    final room = client.getRoomById('!726s6s6q:example.com')!;

    await client.handleSync(
      SyncUpdate.fromJson({
        'next_batch': 'state-after-test',
        'rooms': {
          'join': {
            room.id: {
              'state_after': {
                'events': [_nameEvent('After timeline', r'$after')],
              },
              'timeline': {
                'events': [_nameEvent('Inside timeline', r'$timeline')],
              },
            },
          },
        },
      }),
    );

    expect(room.name, 'After timeline');
    final storedRoom = await client.database.getSingleRoom(client, room.id);
    expect(storedRoom?.name, 'After timeline');
  });

  test('legacy sync applies timeline state without state_after', () async {
    final client = await getClient();
    await client.abortSync();
    final room = client.getRoomById('!726s6s6q:example.com')!;

    await client.handleSync(
      SyncUpdate.fromJson({
        'next_batch': 'legacy-state-test',
        'rooms': {
          'join': {
            room.id: {
              'state': {
                'events': [_nameEvent('Before timeline', r'$before')],
              },
              'timeline': {
                'events': [_nameEvent('Timeline wins', r'$legacyTimeline')],
              },
            },
          },
        },
      }),
    );

    expect(room.name, 'Timeline wins');
  });
}
