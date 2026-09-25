// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../matrix.dart';

enum DelayedEventAction { send, cancel, restart }

extension DelayedEventsHandler on Client {
  static const _unstableFeature = 'org.matrix.msc4140';
  static const _stableFeature = 'org.matrix.msc4140.stable';

  Future<bool> isMsc4140Supported() async {
    final versions = await getVersions();
    return versions.unstableFeatures?[_stableFeature] == true ||
        versions.unstableFeatures?[_unstableFeature] == true;
  }

  Future<bool> isMsc4140StableSupported() async {
    final versions = await getVersions();
    return versions.unstableFeatures?[_stableFeature] == true;
  }

  /// Schedules a delayed message or state event as defined by MSC4140.
  ///
  /// Until MSC4140 lands in a released Matrix specification, homeservers
  /// advertise `org.matrix.msc4140.stable` when the stable endpoint shape is
  /// available. Otherwise the unstable endpoint is used when
  /// `org.matrix.msc4140` is advertised.
  Future<String> scheduleDelayedEvent({
    required String roomId,
    required String eventType,
    required String txnId,
    required int delayInMs,
    required Map<String, Object?> content,
    String? stateKey,
  }) async {
    if (delayInMs <= 0) {
      throw ArgumentError.value(delayInMs, 'delayInMs', 'must be positive');
    }

    final versions = await getVersions();
    final stable = versions.unstableFeatures?[_stableFeature] == true;
    final unstable = versions.unstableFeatures?[_unstableFeature] == true;
    if (!stable && !unstable) {
      throw UnsupportedError('Homeserver does not advertise MSC4140 support');
    }

    final prefix = stable
        ? '_matrix/client/v3'
        : '_matrix/client/unstable/org.matrix.msc4140';
    final requestUri = Uri(
      path:
          '$prefix/rooms/${Uri.encodeComponent(roomId)}/delayed_event/${Uri.encodeComponent(eventType)}/${Uri.encodeComponent(txnId)}',
    );

    final request = http.Request('PUT', baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.headers['content-type'] = 'application/json';
    request.bodyBytes = utf8.encode(
      jsonEncode({
        'delay_ms': delayInMs,
        if (stateKey != null) 'state_key': stateKey,
        'content': content,
      }),
    );
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);

    final json = jsonDecode(utf8.decode(responseBody)) as Map<String, dynamic>;
    return json['delay_id'] as String;
  }

  /// Applies [action] to a scheduled delayed event.
  Future<void> manageDelayedEvent(
    String delayId,
    DelayedEventAction action,
  ) async {
    final versions = await getVersions();
    final stable = versions.unstableFeatures?[_stableFeature] == true;
    final unstable = versions.unstableFeatures?[_unstableFeature] == true;
    if (!stable && !unstable) {
      throw UnsupportedError('Homeserver does not advertise MSC4140 support');
    }

    final prefix = stable
        ? '_matrix/client/v1/delayed_events'
        : '_matrix/client/unstable/org.matrix.msc4140/delayed_events';
    final requestUri = Uri(
      path:
          '$prefix/${Uri.encodeComponent(delayId)}/${Uri.encodeComponent(action.name)}',
    );

    final request = http.Request('POST', baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    request.headers['content-type'] = 'application/json';
    request.bodyBytes = utf8.encode(jsonEncode(<String, Object?>{}));
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);
  }

  /// Retrieves one scheduled or recently finalised delayed event.
  Future<DelayedEvent> getDelayedEvent(String delayId) async {
    final versions = await getVersions();
    final stable = versions.unstableFeatures?[_stableFeature] == true;
    final unstable = versions.unstableFeatures?[_unstableFeature] == true;
    if (!stable && !unstable) {
      throw UnsupportedError('Homeserver does not advertise MSC4140 support');
    }

    final prefix = stable
        ? '_matrix/client/v1/delayed_events'
        : '_matrix/client/unstable/org.matrix.msc4140/delayed_events';
    final requestUri = Uri(
      path: '$prefix/${Uri.encodeComponent(delayId)}',
    );

    final request = http.Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, responseBody);

    final json = jsonDecode(utf8.decode(responseBody)) as Map<String, dynamic>;
    return DelayedEvent.fromJson(json);
  }
}
