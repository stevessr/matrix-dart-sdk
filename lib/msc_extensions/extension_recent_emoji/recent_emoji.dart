// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Synchronizes recently used emoji through Matrix account data.
library;

import '../../matrix.dart';

const _unstableRecentEmojiEventType =
    'io.github.johennes.msc4356.recent_emoji';
const _legacyElementRecentEmojiEventType = 'io.element.recent_emoji';
const _maxRecentEmojiCount = 9007199254740991; // 2^53 - 1
const _maxRecentEmojis = 100;

/// Stable MSC4356 recent-emoji support with backwards compatibility for the
/// earlier MSC prefix and Element's historical account-data format.
extension RecentEmojiExtension on Client {
  /// Returns recently used emoji in most-recently-used order.
  ///
  /// Dart maps preserve insertion order, so callers should iterate [keys] or
  /// [entries] without re-sorting when they want the MSC4356 recency order.
  /// The integer value is the total number of uses recorded for that emoji.
  Map<String, int> get recentEmojis {
    final stable = accountData[EventTypes.RecentEmoji];
    if (stable != null) {
      return _parseStableRecentEmoji(stable);
    }

    // Preserve compatibility with clients which implemented MSC4356 before
    // stabilization.
    final unstable = accountData[_unstableRecentEmojiEventType];
    if (unstable != null) {
      return _parseStableRecentEmoji(unstable);
    }

    // Element used a compact [emoji, count] tuple representation before
    // MSC4356 standardized the extensible object representation.
    return _parseLegacyRecentEmoji(
      accountData[_legacyElementRecentEmojiEventType],
    );
  }

  /// Records one use of [emoji], moving it to the front of the recency list.
  Future<void> addRecentEmoji(String emoji) async {
    final existing = recentEmojis;
    final previousCount = existing[emoji] ?? 0;
    final nextCount = previousCount >= _maxRecentEmojiCount
        ? _maxRecentEmojiCount
        : previousCount + 1;

    final updated = <String, int>{emoji: nextCount};
    for (final entry in existing.entries) {
      if (entry.key == emoji || updated.length >= _maxRecentEmojis) continue;
      updated[entry.key] = entry.value;
    }

    await setRecentEmojiData(updated);
  }

  /// Replaces recent emoji account data.
  ///
  /// The iteration order of [data] becomes the MSC4356 last-used order. At
  /// most 100 valid entries are stored. Stable `m.recent_emoji` is always
  /// written, and the historical Element format is mirrored so older clients
  /// on the same account keep interoperating during migration.
  Future<void> setRecentEmojiData(Map<String, int> data) async {
    if (userID == null) return;

    final normalized = <String, int>{};
    for (final entry in data.entries) {
      if (normalized.length >= _maxRecentEmojis) break;
      if (!_isValidRecentEmojiTotal(entry.value)) continue;
      normalized[entry.key] = entry.value;
    }

    final stableContent = {
      'recent_emoji': [
        for (final entry in normalized.entries)
          {'emoji': entry.key, 'total': entry.value},
      ],
    };
    final legacyContent = {
      'recent_emoji': [
        for (final entry in normalized.entries) [entry.key, entry.value],
      ],
    };

    await setAccountData(userID!, EventTypes.RecentEmoji, stableContent);
    await setAccountData(
      userID!,
      _legacyElementRecentEmojiEventType,
      legacyContent,
    );
  }
}

Map<String, int> _parseStableRecentEmoji(BasicEvent event) {
  final recents = <String, int>{};
  final raw = event.content.tryGetList<Object?>('recent_emoji');
  if (raw == null) return recents;

  for (final item in raw) {
    if (recents.length >= _maxRecentEmojis) break;
    if (item is! Map<String, Object?>) continue;
    final emoji = item['emoji'];
    final total = item['total'];
    if (emoji is! String || total is! int || !_isValidRecentEmojiTotal(total)) {
      continue;
    }
    // A malformed event may repeat an emoji. Keep the first occurrence because
    // it is the most recent one according to the outer array ordering.
    recents.putIfAbsent(emoji, () => total);
  }
  return recents;
}

Map<String, int> _parseLegacyRecentEmoji(BasicEvent? event) {
  final recents = <String, int>{};
  final raw = event?.content.tryGetList<Object?>('recent_emoji');
  if (raw == null) return recents;

  for (final item in raw) {
    if (recents.length >= _maxRecentEmojis) break;
    if (item is! List || item.length < 2) continue;
    final emoji = item[0];
    final total = item[1];
    if (emoji is! String || total is! int || !_isValidRecentEmojiTotal(total)) {
      continue;
    }
    recents.putIfAbsent(emoji, () => total);
  }
  return recents;
}

bool _isValidRecentEmojiTotal(int total) =>
    total >= 0 && total <= _maxRecentEmojiCount;
