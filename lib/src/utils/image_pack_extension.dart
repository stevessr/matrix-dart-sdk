// SPDX-FileCopyrightText: 2019-Present, 2020, 2021 Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:slugify/slugify.dart';

import '../../matrix_api_lite.dart';
import '../room.dart';

const _legacyRoomImagePackEventType = 'im.ponies.room_emotes';
const _legacyUserImagePackEventType = 'im.ponies.user_emotes';
const _legacyImagePackRoomsEventType = 'im.ponies.emote_rooms';
const _maxCanonicalSpaceDepth = 16;

extension ImagePackRoomExtension on Room {
  /// Get all active image packs for the specified [usage], mapped by a stable
  /// display slug.
  ///
  /// Stable MSC2545 sources are loaded in specification priority order:
  /// globally-enabled packs, packs in this room, then packs in the canonical
  /// space hierarchy. Historical `im.ponies.*` events remain readable for
  /// backwards compatibility without duplicating an equivalent stable pack.
  Map<String, ImagePackContent> getImagePacks([ImagePackUsage? usage]) {
    final packs = <String, ImagePackContent>{};
    final seenPackSources = <String>{};

    void addImagePack(
      BasicEvent? event, {
      Room? room,
      String? slug,
      String stateKey = '',
    }) {
      if (event == null) return;

      // A stable room image pack supersedes the historical event with the same
      // room/state key. Track pack identity, rather than media URI identity:
      // MSC2545 permits multiple shortcodes (and multiple packs) to point at
      // the same MXC and those entries must remain independently selectable.
      //
      // BasicEvent intentionally has no stateKey because it is also used for
      // account data. Callers which are iterating room state therefore pass
      // the state key explicitly instead of down-casting the event here.
      final semanticType = event.type == _legacyRoomImagePackEventType
          ? EventTypes.RoomImagePack
          : event.type;
      final sourceKey = room == null
          ? 'account\u0000$semanticType\u0000$stateKey'
          : '${room.id}\u0000$semanticType\u0000$stateKey';
      if (!seenPackSources.add(sourceKey)) return;

      final imagePack = event.parsedImagePackContent;

      final rawSlug = slug ?? 'pack';
      var finalSlug = slugify(rawSlug);
      // `slugify` drops every character outside of the latin alphabet, so a
      // pack named in Chinese - or any other non-latin script - would slugify
      // to an empty string. Keep the original in that case.
      if (finalSlug.isEmpty) finalSlug = rawSlug;
      // Different packs may still slugify to the same value. Keep them
      // distinct instead of silently merging them.
      if (packs.containsKey(finalSlug)) {
        var suffix = 2;
        while (packs.containsKey('$finalSlug-$suffix')) {
          suffix++;
        }
        finalSlug = '$finalSlug-$suffix';
      }

      for (final entry in imagePack.images.entries) {
        final image = entry.value;

        // Image-level usage existed in the historical proposal and is kept for
        // compatibility. Stable MSC2545 defines usage at pack level. An absent
        // *or empty* usage array means all usages in the stable specification.
        final imageUsage = image.usage ?? imagePack.pack.usage;
        if (usage != null &&
            imageUsage?.isNotEmpty == true &&
            !imageUsage!.contains(usage)) {
          continue;
        }

        packs
                .putIfAbsent(
                  finalSlug,
                  () => ImagePackContent.fromJson({})
                    ..pack.displayName =
                        imagePack.pack.displayName ??
                        room?.getLocalizedDisplayname() ??
                        finalSlug
                    ..pack.avatarUrl = imagePack.pack.avatarUrl ?? room?.avatar
                    ..pack.attribution = imagePack.pack.attribution,
                )
                .images[entry.key] =
            image;
      }
    }

    void addReferencedPacks(BasicEvent? references) {
      final rooms = references?.content.tryGetMap<String, Object?>('rooms');
      if (rooms == null) return;

      for (final roomEntry in rooms.entries) {
        final packRoom = client.getRoomById(roomEntry.key);
        final referencedStateKeys = roomEntry.value;
        if (packRoom == null || referencedStateKeys is! Map<String, Object?>) {
          continue;
        }

        for (final stateKey in referencedStateKeys.keys) {
          // Stable state always wins when both forms exist. The semantic source
          // identity above also prevents the same pack being surfaced twice if
          // both stable and legacy account-data events reference it.
          final event =
              packRoom.getState(EventTypes.RoomImagePack, stateKey) ??
              packRoom.getState(_legacyRoomImagePackEventType, stateKey);
          final fallbackSlug =
              '${packRoom.getLocalizedDisplayname()}-${stateKey.isNotEmpty ? '$stateKey-' : ''}${packRoom.id}';
          addImagePack(
            event,
            room: packRoom,
            slug: fallbackSlug,
            stateKey: stateKey,
          );
        }
      }
    }

    void addRoomPacks(Room sourceRoom, String eventType) {
      final roomPacks = sourceRoom.states[eventType];
      if (roomPacks == null) return;
      for (final entry in roomPacks.entries) {
        addImagePack(
          entry.value,
          room: sourceRoom,
          slug: entry.value.stateKey?.isNotEmpty == true
              ? entry.value.stateKey
              : sourceRoom.id == id
              ? 'room'
              : sourceRoom.getLocalizedDisplayname(),
          stateKey: entry.key,
        );
      }
    }

    Iterable<Room> canonicalSpaces() sync* {
      var current = this;
      final visited = <String>{id};

      for (var depth = 0; depth < _maxCanonicalSpaceDepth; depth++) {
        final parents = current.states[EventTypes.SpaceParent];
        if (parents == null) return;

        Room? canonicalParent;
        for (final entry in parents.entries) {
          if (entry.value.content.tryGet<bool>('canonical') != true) continue;
          final candidate = client.getRoomById(entry.key);
          if (candidate == null ||
              candidate.membership != Membership.join ||
              !candidate.isSpace ||
              visited.contains(candidate.id)) {
            continue;
          }
          canonicalParent = candidate;
          break;
        }

        if (canonicalParent == null) return;
        visited.add(canonicalParent.id);
        yield canonicalParent;
        current = canonicalParent;
      }
    }

    // Stable globally-enabled room packs have the highest priority.
    addReferencedPacks(client.accountData[EventTypes.ImagePackRooms]);

    // Keep Element/MSC2545-era account data readable during migration. The
    // historical direct user pack has no stable equivalent, so it remains as
    // an additional user-scoped source.
    addImagePack(
      client.accountData[_legacyUserImagePackEventType],
      slug: 'user',
    );
    addReferencedPacks(client.accountData[_legacyImagePackRoomsEventType]);

    // Packs in the current room come next. Stable state wins source identity.
    addRoomPacks(this, EventTypes.RoomImagePack);
    addRoomPacks(this, _legacyRoomImagePackEventType);

    // Finally surface packs from the room's canonical space hierarchy when
    // the user is also joined to those spaces, as required by stable MSC2545.
    for (final space in canonicalSpaces()) {
      addRoomPacks(space, EventTypes.RoomImagePack);
      addRoomPacks(space, _legacyRoomImagePackEventType);
    }

    return packs;
  }

  /// Get a flat view of all image packs of a specified [usage], mapping pack
  /// slugs to a map of the image code to their mxc url
  Map<String, Map<String, String>> getImagePacksFlat([ImagePackUsage? usage]) =>
      getImagePacks(usage).map(
        (k, v) =>
            MapEntry(k, v.images.map((k, v) => MapEntry(k, v.url.toString()))),
      );
}
