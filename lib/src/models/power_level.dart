// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

extension type PowerLevel(int level) {
  /// Local sentinel for the infinite room-creator power level in room v12+.
  ///
  /// Matrix power-level values on the wire are limited to 2^53 - 1 by
  /// Canonical JSON, so 2^53 is both exactly representable and impossible to
  /// collide with a legitimate finite power level received from the server.
  static const int ownerPowerLevel = 9007199254740992;
  static const int defaultAdminLevel = 100;
  static const int defaultModeratorLevel = 50;
  static const int defaultUserLevel = 0;

  static PowerLevel get owner => PowerLevel(ownerPowerLevel);
  static PowerLevel get admin => PowerLevel(defaultAdminLevel);
  static PowerLevel get moderator => PowerLevel(defaultModeratorLevel);
  static PowerLevel get user => PowerLevel(defaultUserLevel);

  PowerLevelRole get role => level == ownerPowerLevel
      ? PowerLevelRole.owner
      : level >= defaultAdminLevel
      ? PowerLevelRole.admin
      : level >= defaultModeratorLevel
      ? PowerLevelRole.moderator
      : PowerLevelRole.user;

  bool operator <(PowerLevel other) => level < other.level;
  bool operator >(PowerLevel other) => level > other.level;
  bool operator >=(PowerLevel other) => level >= other.level;
  bool operator <=(PowerLevel other) => level <= other.level;
}

enum PowerLevelRole { user, moderator, admin, owner }
