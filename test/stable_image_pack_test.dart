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

    test('treats an empty stable usage array as all usages', () {
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.RoomImagePack,
          stateKey: 'empty-usage',
          content: {
            'images': {
              'both': {'url': 'mxc://fakeServer.notExisting/both'},
            },
            'pack': {
              'display_name': 'Both',
              'usage': <String>[],
            },
          },
        ),
      );

      expect(
        room
            .getImagePacks(ImagePackUsage.emoticon)
            .values
            .any((pack) => pack.images.containsKey('both')),
        isTrue,
      );
      expect(
        room
            .getImagePacks(ImagePackUsage.sticker)
            .values
            .any((pack) => pack.images.containsKey('both')),
        isTrue,
      );
    });

    test('keeps multiple shortcodes which point at the same MXC', () {
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.RoomImagePack,
          stateKey: 'aliases',
          content: {
            'images': {
              'wave': {'url': 'mxc://fakeServer.notExisting/shared'},
              'hello': {'url': 'mxc://fakeServer.notExisting/shared'},
            },
          },
        ),
      );

      final pack = room
          .getImagePacks()
          .values
          .firstWhere((pack) => pack.images.containsKey('wave'));
      expect(pack.images.containsKey('wave'), isTrue);
      expect(pack.images.containsKey('hello'), isTrue);
    });

    test('keeps separate packs which reuse the same MXC', () {
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.RoomImagePack,
          stateKey: 'shared-a',
          content: {
            'images': {
              'first': {'url': 'mxc://fakeServer.notExisting/reused'},
            },
          },
        ),
      );
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.RoomImagePack,
          stateKey: 'shared-b',
          content: {
            'images': {
              'second': {'url': 'mxc://fakeServer.notExisting/reused'},
            },
          },
        ),
      );

      final packs = room.getImagePacks();
      expect(
        packs.values.where((pack) => pack.images.containsKey('first')).length,
        1,
      );
      expect(
        packs.values.where((pack) => pack.images.containsKey('second')).length,
        1,
      );
    });

    test('stable state supersedes an equivalent legacy pack', () {
      room.setState(
        stateEvent(
          room: room,
          type: 'im.ponies.room_emotes',
          stateKey: 'upgraded',
          content: {
            'images': {
              'legacy_only': {
                'url': 'mxc://fakeServer.notExisting/legacy-only',
              },
            },
          },
        ),
      );
      room.setState(
        stateEvent(
          room: room,
          type: EventTypes.RoomImagePack,
          stateKey: 'upgraded',
          content: {
            'images': {
              'stable_only': {
                'url': 'mxc://fakeServer.notExisting/stable-only',
              },
            },
          },
        ),
      );

      final packs = room.getImagePacks();
      expect(
        packs.values.any((pack) => pack.images.containsKey('stable_only')),
        isTrue,
      );
      expect(
        packs.values.any((pack) => pack.images.containsKey('legacy_only')),
        isFalse,
      );
    });
  });
}
