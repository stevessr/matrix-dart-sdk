// SPDX-FileCopyrightText: 2026 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_client.dart';

Event _stateEvent({
  required Room room,
  required String type,
  required String sender,
  required Map<String, Object?> content,
  String eventId = r'$state',
}) => Event(
  room: room,
  eventId: eventId,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
  senderId: sender,
  type: type,
  content: content,
  stateKey: '',
);

void main() {
  test('domainless room and event IDs do not expose a fake domain', () {
    expect('!opaqueRoomId'.isValidMatrixIdStrict(), isTrue);
    expect(r'$opaqueEventId'.isValidMatrixIdStrict(), isTrue);
    expect('!opaqueRoomId'.domain, isNull);
    expect(r'$opaqueEventId'.domain, isNull);
    expect('!legacy:example.org'.domain, 'example.org');
    expect(r'$legacy:example.org'.domain, 'example.org');

    final parsed = 'matrix:roomid/opaqueRoomId'.parseIdentifierIntoParts();
    expect(parsed?.primaryIdentifier, '!opaqueRoomId');
  });

  test(
    'room v12 creator semantics are version gated and truly infinite',
    () async {
      final client = await getClient();
      await client.abortSync();
      final room = Room(id: '!opaqueRoomId', client: client);

      room.setState(
        _stateEvent(
          room: room,
          type: EventTypes.RoomCreate,
          sender: '@alice:example.org',
          eventId: r'$create',
          content: {
            'room_version': '11',
            'additional_creators': ['@bob:example.org'],
          },
        ),
      );

      // additional_creators has no meaning before room version 12.
      expect(room.creatorUserIds, {'@alice:example.org'});

      room.states[EventTypes.RoomCreate]!['']!.content['room_version'] = '12';
      expect(room.creatorUserIds, {'@alice:example.org', '@bob:example.org'});

      room.setState(
        _stateEvent(
          room: room,
          type: EventTypes.RoomPowerLevels,
          sender: '@alice:example.org',
          eventId: r'$power',
          content: {
            'users': {'@carol:example.org': 9007199254740991},
          },
        ),
      );

      final creator = room.getPowerLevelByUserId('@alice:example.org');
      final finiteMaximum = room.getPowerLevelByUserId('@carol:example.org');
      expect(creator.role, PowerLevelRole.owner);
      expect(finiteMaximum.role, PowerLevelRole.admin);
      expect(creator.level, greaterThan(finiteMaximum.level));
    },
  );
}
