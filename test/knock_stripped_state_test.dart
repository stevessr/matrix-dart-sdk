// SPDX-FileCopyrightText: 2026 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:test/test.dart';

import 'fake_client.dart';

Map<String, Object?> _createEvent(String sender) => {
  'sender': sender,
  'type': EventTypes.RoomCreate,
  'state_key': '',
  'content': {
    'room_version': '12',
    'additional_creators': ['@co-creator:example.org'],
  },
};

void main() {
  test(
    'invite and knock stripped state preserve room create semantics',
    () async {
      final client = await getClient();
      await client.abortSync();

      const inviteRoomId = '!opaqueInviteRoom';
      const knockRoomId = '!opaqueKnockRoom';

      await client.handleSync(
        SyncUpdate.fromJson({
          'next_batch': 'stripped-state-test',
          'rooms': {
            'invite': {
              inviteRoomId: {
                'invite_state': {
                  'events': [_createEvent('@inviter:example.org')],
                },
              },
            },
            'knock': {
              knockRoomId: {
                'knock_state': {
                  'events': [_createEvent('@knocker:example.org')],
                },
              },
            },
          },
        }),
      );

      final inviteRoom = client.getRoomById(inviteRoomId);
      expect(inviteRoom, isNotNull);
      expect(inviteRoom!.membership, Membership.invite);
      expect(inviteRoom.roomVersion, '12');

      final knockRoom = client.getRoomById(knockRoomId);
      expect(knockRoom, isNotNull);
      expect(knockRoom!.membership, Membership.knock);
      expect(knockRoom.roomVersion, '12');
      expect(knockRoom.creatorUserIds, {
        '@knocker:example.org',
        '@co-creator:example.org',
      });
    },
  );
}
