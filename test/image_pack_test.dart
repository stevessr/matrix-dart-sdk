// SPDX-FileCopyrightText: 2019-Present, 2021 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_client.dart';

void main() {
  group('Image Pack', () {
    late Client client;
    late Room room;
    late Room room2;

    test('setupClient', () async {
      client = await getClient();
      room = Room(id: '!1234:fakeServer.notExisting', client: client);
      room2 = Room(id: '!abcd:fakeServer.notExisting', client: client);
      room.setState(
        Event(
          type: 'm.room.power_levels',
          content: {},
          room: room,
          stateKey: '',
          senderId: client.userID!,
          eventId: '\$fakeid1:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      room.setState(
        Event(
          type: 'm.room.member',
          content: {'membership': 'join'},
          room: room,
          stateKey: client.userID,
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid2:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      room2.setState(
        Event(
          type: 'm.room.power_levels',
          content: {},
          room: room2,
          stateKey: '',
          senderId: client.userID!,
          eventId: '\$fakeid3:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      room2.setState(
        Event(
          type: 'm.room.member',
          content: {'membership': 'join'},
          room: room2,
          stateKey: client.userID,
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid4:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      client.rooms.add(room);
      client.rooms.add(room2);
    });

    test('Single room', () async {
      room.setState(
        Event(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'room_plain': {'url': 'mxc://room_plain'},
            },
          },
          room: room,
          stateKey: '',
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid5:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      final packs = room.getImagePacks();
      expect(packs.length, 1);
      expect(packs['room']?.images.length, 1);
      expect(
        packs['room']?.images['room_plain']?.url.toString(),
        'mxc://room_plain',
      );
      var packsFlat = room.getImagePacksFlat();
      expect(packsFlat, {
        'room': {'room_plain': 'mxc://room_plain'},
      });
      room.setState(
        Event(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'emote': {
                'url': 'mxc://emote',
                'usage': ['emoticon'],
              },
              'sticker': {
                'url': 'mxc://sticker',
                'usage': ['sticker'],
              },
            },
          },
          room: room,
          stateKey: '',
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid6:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      packsFlat = room.getImagePacksFlat(ImagePackUsage.emoticon);
      expect(packsFlat, {
        'room': {'emote': 'mxc://emote'},
      });
      packsFlat = room.getImagePacksFlat(ImagePackUsage.sticker);
      expect(packsFlat, {
        'room': {'sticker': 'mxc://sticker'},
      });
      room.setState(
        Event(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'emote': {'url': 'mxc://emote'},
              'sticker': {'url': 'mxc://sticker'},
            },
            'pack': {
              'usage': ['emoticon'],
            },
          },
          room: room,
          stateKey: '',
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid7:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      packsFlat = room.getImagePacksFlat(ImagePackUsage.emoticon);
      expect(packsFlat, {
        'room': {'emote': 'mxc://emote', 'sticker': 'mxc://sticker'},
      });
      packsFlat = room.getImagePacksFlat(ImagePackUsage.sticker);
      expect(packsFlat, {});

      room.setState(
        Event(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'fox': {'url': 'mxc://fox'},
            },
            'pack': {
              'usage': ['emoticon'],
            },
          },
          room: room,
          stateKey: 'fox',
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid8:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      packsFlat = room.getImagePacksFlat(ImagePackUsage.emoticon);
      expect(packsFlat, {
        'room': {'emote': 'mxc://emote', 'sticker': 'mxc://sticker'},
        'fox': {'fox': 'mxc://fox'},
      });
    });

    test('user pack', () async {
      client.accountData['im.ponies.user_emotes'] = BasicEvent.fromJson({
        'type': 'im.ponies.user_emotes',
        'content': {
          'images': {
            'user': {'url': 'mxc://user'},
          },
        },
      });
      final packsFlat = room.getImagePacksFlat(ImagePackUsage.emoticon);
      expect(packsFlat, {
        'room': {'emote': 'mxc://emote', 'sticker': 'mxc://sticker'},
        'fox': {'fox': 'mxc://fox'},
        'user': {'user': 'mxc://user'},
      });
    });

    test('other rooms', () async {
      room2.setState(
        Event(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'other_room_emote': {'url': 'mxc://other_room_emote'},
            },
            'pack': {
              'usage': ['emoticon'],
            },
          },
          room: room2,
          stateKey: '',
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid9:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      client.accountData['im.ponies.emote_rooms'] = BasicEvent.fromJson({
        'type': 'im.ponies.emote_rooms',
        'content': {
          'rooms': {
            '!abcd:fakeServer.notExisting': {'': {}},
          },
        },
      });
      var packsFlat = room.getImagePacksFlat(ImagePackUsage.emoticon);
      expect(packsFlat, {
        'room': {'emote': 'mxc://emote', 'sticker': 'mxc://sticker'},
        'fox': {'fox': 'mxc://fox'},
        'user': {'user': 'mxc://user'},
        'empty-chat-abcdfakeservernotexisting': {
          'other_room_emote': 'mxc://other_room_emote',
        },
      });
      room2.setState(
        Event(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'other_fox': {'url': 'mxc://other_fox'},
            },
            'pack': {
              'usage': ['emoticon'],
            },
          },
          room: room2,
          stateKey: 'fox',
          senderId: '@fakeuser:fakeServer.notExisting',
          eventId: '\$fakeid10:fakeServer.notExisting',
          originServerTs: DateTime.now(),
        ),
      );
      client.accountData['im.ponies.emote_rooms'] = BasicEvent.fromJson({
        'type': 'im.ponies.emote_rooms',
        'content': {
          'rooms': {
            '!abcd:fakeServer.notExisting': {'': {}, 'fox': {}},
          },
        },
      });
      packsFlat = room.getImagePacksFlat(ImagePackUsage.emoticon);
      expect(packsFlat, {
        'room': {'emote': 'mxc://emote', 'sticker': 'mxc://sticker'},
        'fox': {'fox': 'mxc://fox'},
        'user': {'user': 'mxc://user'},
        'empty-chat-abcdfakeservernotexisting': {
          'other_room_emote': 'mxc://other_room_emote',
        },
        'empty-chat-fox-abcdfakeservernotexisting': {
          'other_fox': 'mxc://other_fox',
        },
      });
    });

    test('non-latin state keys stay separate packs', () async {
      final chineseRoom = Room(
        id: '!chinese:fakeServer.notExisting',
        client: client,
      );
      for (final entry in {
        '表情包': 'mxc://first',
        '贴纸': 'mxc://second',
      }.entries) {
        chineseRoom.setState(
          Event(
            type: 'im.ponies.room_emotes',
            content: {
              'images': {
                'fox': {'url': entry.value},
              },
            },
            room: chineseRoom,
            stateKey: entry.key,
            senderId: '@fakeuser:fakeServer.notExisting',
            eventId: '\$fake_${entry.value}:fakeServer.notExisting',
            originServerTs: DateTime.now(),
          ),
        );
      }

      // `slugify` reduces both state keys to an empty string, so without
      // keeping the original they would be merged into a single pack.
      final packs = chineseRoom.getImagePacks();
      expect(packs.containsKey('表情包'), true);
      expect(packs.containsKey('贴纸'), true);
      expect(packs['表情包']?.images['fox']?.url.toString(), 'mxc://first');
      expect(packs['贴纸']?.images['fox']?.url.toString(), 'mxc://second');
    });

    test('dispose client', () async {
      await client.dispose(closeDatabase: true);
    });
  });
}
