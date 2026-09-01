// SPDX-FileCopyrightText: 2026 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_client.dart';

Event stateEvent({
  required Room room,
  required String type,
  required Map<String, Object?> content,
  String stateKey = '',
  String eventId = r'$stable-image-pack',
}) => Event(
  type: type,
  content: content,
  room: room,
  stateKey: stateKey,
  senderId: room.client.userID!,
  eventId: '$eventId:${room.id}',
  originServerTs: DateTime.now(),
);

void main() {
  group('Stable MSC2545 image packs', () {
    late Client client;
    late Room room;
    late Room globalPackRoom;
    late Room space;

    setUpAll(() async {
      client = await getClient();
      room = Room(id: '!room:fakeServer.notExisting', client: client);
      globalPackRoom = Room(
        id: '!global:fakeServer.notExisting',
        client: client,
      );
      space = Room(id: '!space:fakeServer.notExisting', client: client);
      client.rooms.addAll([room, globalPackRoom, space]);

      space.setState(
        stateEvent(
          room: space,
          type: EventTypes.RoomCreate,
          content: {'type': 'm.space'},
        ),
      );
    });

    tearDownAll(() async {
      await client.dispose(closeDatabase: true);
    });

    test('loads stable packs from current room state', () {
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.RoomImagePack,
          stateKey: 'local',
          content: {
            'images': {
              'local_wave': {
                'url': 'mxc://fakeServer.notExisting/local-wave',
                'body': 'Local wave',
              },
            },
            'pack': {
              'display_name': 'Local pack',
              'usage': ['emoticon'],
            },
          },
        ),
      );

      final packs = room.getImagePacks(ImagePackUsage.emoticon);
      expect(
        packs['local']?.images['local_wave']?.url.toString(),
        'mxc://fakeserver.notexisting/local-wave',
      );
    });

    test('loads globally enabled stable room packs before local packs', () {
      globalPackRoom.setState(
        stateEvent(
          room: globalPackRoom,
          type: EventTypes.RoomImagePack,
          stateKey: 'global',
          content: {
            'images': {
              'global_party': {
                'url': 'mxc://fakeServer.notExisting/global-party',
              },
            },
            'pack': {
              'display_name': 'Global pack',
              'usage': ['emoticon'],
            },
          },
        ),
      );
      client.accountData[EventTypes.ImagePackRooms] = BasicEvent.fromJson({
        'type': EventTypes.ImagePackRooms,
        'content': {
          'rooms': {
            globalPackRoom.id: {'global': <String, Object?>{}},
          },
        },
      });

      final packs = room.getImagePacks(ImagePackUsage.emoticon);
      final globalEntry = packs.entries.firstWhere(
        (entry) => entry.value.images.containsKey('global_party'),
      );
      expect(
        globalEntry.value.images['global_party']?.url.toString(),
        'mxc://fakeserver.notexisting/global-party',
      );
      expect(
        packs.keys.toList().indexOf(globalEntry.key),
        lessThan(packs.keys.toList().indexOf('local')),
      );
    });

    test('loads packs from joined canonical space hierarchy', () {
      space.setState(
        stateEvent(
          room: space,
          type: EventTypes.RoomImagePack,
          stateKey: 'space-pack',
          content: {
            'images': {
              'space_cat': {'url': 'mxc://fakeServer.notExisting/space-cat'},
            },
            'pack': {
              'display_name': 'Space pack',
              'usage': ['emoticon'],
            },
          },
        ),
      );
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.SpaceParent,
          stateKey: space.id,
          content: {
            'canonical': true,
            'via': ['fakeServer.notExisting'],
          },
        ),
      );

      final packs = room.getImagePacks(ImagePackUsage.emoticon);
      final spaceEntry = packs.values.firstWhere(
        (pack) => pack.images.containsKey('space_cat'),
      );
      expect(
        spaceEntry.images['space_cat']?.url.toString(),
        'mxc://fakeserver.notexisting/space-cat',
      );
    });
  });
}
