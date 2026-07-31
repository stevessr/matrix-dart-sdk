import 'dart:async';

import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

class Thread {
  final Room room;
  final Event rootEvent;
  Event? lastEvent;
  String? prev_batch;
  bool? currentUserParticipated;
  int? count;
  final Client client;

  /// The count of unread notifications.
  int notificationCount = 0;

  /// The count of highlighted notifications.
  int highlightCount = 0;

  Thread({
    required this.room,
    required this.rootEvent,
    required this.client,
    required this.currentUserParticipated,
    required this.count,
    required this.notificationCount,
    required this.highlightCount,
    this.prev_batch,
    this.lastEvent,
  });

  /// Returns true if this room is unread. To check if there are new messages
  /// in muted rooms, use [hasNewMessages].
  bool get isUnread => notificationCount > 0;

  Map<String, dynamic> toJson() => {
    ...rootEvent.toJson(),
    'unsigned': {
      'm.thread': {
        'latest_event': lastEvent?.toJson(),
        'count': count,
        'current_user_participated': currentUserParticipated,
      },
    },
  };

  factory Thread.fromJson(Map<String, dynamic> json, Client client) {
    final room = client.getRoomById(json['room_id']);
    if (room == null) throw Error();
    Event? lastEvent;
    if (json['unsigned']?['m.relations']?['m.thread']?['latest_event'] !=
        null) {
      lastEvent = Event.fromMatrixEvent(
        MatrixEvent.fromJson(
          json['unsigned']?['m.relations']?['m.thread']?['latest_event'],
        ),
        room,
      );
    }
    if (json['unsigned']?['m.thread']?['latest_event'] != null) {
      lastEvent = Event.fromMatrixEvent(
        MatrixEvent.fromJson(json['unsigned']?['m.thread']?['latest_event']),
        room,
      );
    }
    // Although I was making this part according to specification, it's a bit off
    // I have no clue why
    final thread = Thread(
      room: room,
      client: client,
      rootEvent: Event.fromMatrixEvent(MatrixEvent.fromJson(json), room),
      lastEvent: lastEvent,
      count: json['unsigned']?['m.relations']?['m.thread']?['count'],
      currentUserParticipated:
          json['unsigned']?['m.relations']?['m.thread']?['current_user_participated'],
      highlightCount: 0,
      notificationCount: 0,
    );
    return thread;
  }

  Future<Event?> refreshLastEvent({
    timeout = const Duration(seconds: 30),
  }) async {
    final lastEvent = _refreshingLastEvent ??= _refreshLastEvent();
    _refreshingLastEvent = null;
    return lastEvent;
  }

  Future<Event?>? _refreshingLastEvent;

  Future<Event?> _refreshLastEvent({
    timeout = const Duration(seconds: 30),
  }) async {
    if (room.membership != Membership.join) return null;

    final result = await client
        .getRelatingEventsWithRelType(
          room.id,
          rootEvent.eventId,
          'm.thread',
          recurse: false,
        )
        .timeout(timeout);
    final matrixEvent = result.chunk.firstOrNull;
    if (matrixEvent == null) {
      if (lastEvent?.type == EventTypes.refreshingLastEvent) {
        lastEvent = null;
      }
      Logs().d(
        'No last event found for thread ${rootEvent.eventId} in ${rootEvent.roomId}',
      );
      return null;
    }
    var event = Event.fromMatrixEvent(
      matrixEvent,
      room,
      status: EventStatus.synced,
    );
    if (event.type == EventTypes.Encrypted) {
      final encryption = client.encryption;
      if (encryption != null) {
        event = await encryption.decryptRoomEvent(event);
      }
    }
    lastEvent = event;

    return event;
  }

  /// When was the last event received.
  DateTime get latestEventReceivedTime {
    final lastEventTime = lastEvent?.originServerTs;
    if (lastEventTime != null) return lastEventTime;

    if (room.membership == Membership.invite) return DateTime.now();

    return rootEvent.originServerTs;
  }

  bool get hasNewMessages {
    final lastEvent = this.lastEvent;

    // There is no known event or the last event is only a state fallback event,
    // we assume there is no new messages.
    if (lastEvent == null ||
        !client.roomPreviewLastEvents.contains(lastEvent.type)) {
      return false;
    }

    // Read marker is on the last event so no new messages.
    if (lastEvent.receipts.any(
      (receipt) => receipt.user.senderId == client.userID!,
    )) {
      return false;
    }

    // If the last event is sent, we mark the room as read.
    if (lastEvent.senderId == client.userID) return false;

    // Get the timestamp of read marker and compare
    final readAtMilliseconds =
        room.receiptState.byThread[rootEvent.eventId]?.latestOwnReceipt?.ts ??
        0;
    return readAtMilliseconds < lastEvent.originServerTs.millisecondsSinceEpoch;
  }

  Future<TimelineChunk?> getEventContext(String eventId) async {
    // Fetch the event context for a thread by paginating the thread's
    // `/relations` around `eventId`. We use the `/relations` API (not
    // `/event_context`) because the ThreadTimeline paginates via
    // `/relations`; `/event_context` returns `/messages` tokens that are
    // meaningless to `/relations` and cause the timeline to re-fetch the
    // same page forever.
    String? fromToken;
    String? firstPrevBatch;
    String? lastNextBatch;
    final allEvents = <Event>[];

    do {
      final resp = await client.getRelatingEvents(
        room.id,
        rootEvent.eventId,
        limit: Room.defaultHistoryCount,
        from: fromToken,
        dir: Direction.b,
        recurse: true,
      );

      firstPrevBatch ??= resp.prevBatch;
      lastNextBatch = resp.nextBatch;

      final pageEvents = resp.chunk
          .map((e) => Event.fromMatrixEvent(e, room))
          .where(
            (e) =>
                e.relationshipType == RelationshipTypes.thread &&
                e.relationshipEventId == rootEvent.eventId,
          )
          .toList();

      allEvents.addAll(pageEvents);

      // Stop if we found the target event or there are no more pages.
      if (pageEvents.any((e) => e.eventId == eventId)) {
        break;
      }
      if (resp.nextBatch == null || resp.nextBatch == fromToken) {
        break;
      }
      fromToken = resp.nextBatch;
    } while (true);

    // Try to decrypt encrypted events but don't update the database.
    if (room.encrypted && client.encryptionEnabled) {
      for (var i = 0; i < allEvents.length; i++) {
        if (allEvents[i].type == EventTypes.Encrypted &&
            allEvents[i].content['can_request_session'] == true) {
          allEvents[i] = await client.encryption!.decryptRoomEvent(
            allEvents[i],
          );
        }
      }
    }

    // Seed the chunk with native /relations tokens.
    // - nextBatch (resp.nextBatch) is the backward/older continuation token,
    //   which the ThreadTimeline stores into chunk.prevBatch to page further
    //   back without overlap.
    // - prevBatch (resp.prevBatch) is the forward/newer token, stored into
    //   chunk.nextBatch for requestFuture.
    return TimelineChunk(
      events: allEvents,
      prevBatch: lastNextBatch ?? '',
      nextBatch: firstPrevBatch ?? '',
    );
  }

  Future<ThreadTimeline> getTimeline({
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function(int insertID)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async {
    // await postLoad();

    var events = <Event>[];

    await client.database.transaction(() async {
      events = await client.database.getThreadEventList(this, limit: limit);
    });

    var chunk = TimelineChunk(events: events);
    // Load the timeline arround eventContextId if set
    if (eventContextId != null) {
      if (!events.any((Event event) => event.eventId == eventContextId)) {
        chunk =
            await getEventContext(eventContextId) ?? TimelineChunk(events: []);
      }
    }

    final timeline = ThreadTimeline(
      thread: this,
      chunk: chunk,
      onChange: onChange,
      onRemove: onRemove,
      onInsert: onInsert,
      onNewEvent: onNewEvent,
      onUpdate: onUpdate,
    );

    // Fetch all users from database we have got here.
    if (eventContextId == null) {
      final userIds = events.map((event) => event.senderId).toSet();
      for (final userId in userIds) {
        if (room.getState(EventTypes.RoomMember, userId) != null) continue;
        final dbUser = await client.database.getUser(userId, room);
        if (dbUser != null) room.setState(dbUser);
      }
    }

    // Try again to decrypt encrypted events and update the database.
    if (room.encrypted && client.encryptionEnabled) {
      // decrypt messages
      for (var i = 0; i < chunk.events.length; i++) {
        if (chunk.events[i].type == EventTypes.Encrypted) {
          if (eventContextId != null) {
            // for the fragmented timeline, we don't cache the decrypted
            //message in the database
            chunk.events[i] = await client.encryption!.decryptRoomEvent(
              chunk.events[i],
            );
          } else {
            // else, we need the database
            await client.database.transaction(() async {
              for (var i = 0; i < chunk.events.length; i++) {
                if (chunk.events[i].content['can_request_session'] == true) {
                  chunk.events[i] = await client.encryption!.decryptRoomEvent(
                    chunk.events[i],
                    store: !room.isArchived,
                    updateType: EventUpdateType.history,
                  );
                }
              }
            });
          }
        }
      }
    }

    return timeline;
  }

  Future<String?> sendTextEvent(
    String message, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    bool parseMarkdown = true,
    bool parseCommands = true,
    String msgtype = MessageTypes.Text,
    StringBuffer? commandStdout,
    bool addMentions = true,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,
  }) {
    return room.sendTextEvent(
      message,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      parseCommands: parseCommands,
      parseMarkdown: parseMarkdown,
      msgtype: msgtype,
      commandStdout: commandStdout,
      addMentions: addMentions,
      displayPendingEvent: displayPendingEvent,
      threadLastEventId: lastEvent?.eventId,
      threadRootEventId: rootEvent.eventId,
    );
  }

  Future<String?> sendLocation(String body, String geoUri, {String? txid}) {
    final event = <String, dynamic>{
      'msgtype': 'm.location',
      'body': body,
      'geo_uri': geoUri,
    };
    return room.sendEvent(
      event,
      txid: txid,
      threadLastEventId: lastEvent?.eventId,
      threadRootEventId: rootEvent.eventId,
    );
  }

  Future<String?> sendFileEvent(
    MatrixFile file, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    int? shrinkImageMaxDimension,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,

    /// Displays an event in the timeline with the transaction ID as the event
    /// ID and a status of SENDING, SENT or ERROR until it gets replaced by
    /// the sync event. Using this can display a different sort order of events
    /// as the sync event does replace but not relocate the pending event.
    bool displayPendingEvent = true,
  }) async {
    return await room.sendFileEvent(
      file,
      txid: txid,
      inReplyTo: inReplyTo,
      editEventId: editEventId,
      shrinkImageMaxDimension: shrinkImageMaxDimension,
      thumbnail: thumbnail,
      extraContent: extraContent,
      displayPendingEvent: displayPendingEvent,
      threadLastEventId: lastEvent?.eventId,
      threadRootEventId: rootEvent.eventId,
    );
  }

  Future<void> setReadMarker({String? eventId, bool? public}) async {
    if (eventId == null) return null;
    return await client.postReceipt(
      room.id,
      (public ?? client.receiptsPublicByDefault)
          ? ReceiptType.mRead
          : ReceiptType.mReadPrivate,
      eventId,
      threadId: rootEvent.eventId,
    );
  }

  Future<void> setLastEvent(Event event) async {
    lastEvent = event;
    final thread = await client.database.getThread(
      room.id,
      rootEvent.eventId,
      client,
    );
    Logs().v(
      'Set lastEvent to ${room.id}:${rootEvent.eventId} (${event.senderId})',
    );
    await client.database.storeThread(
      room.id,
      rootEvent,
      lastEvent,
      currentUserParticipated ?? false,
      notificationCount,
      highlightCount,
      (thread?.count ?? 0) + 1,
      client,
    );
  }

  Future<int> requestHistory({
    int historyCount = Room.defaultHistoryCount,
    void Function()? onHistoryReceived,
    direction = Direction.b,
    StateFilter? filter,
  }) async {
    final prev_batch = this.prev_batch;

    final storeInDatabase = !room.isArchived;

    // Ensure stateFilter is not null and set lazyLoadMembers to true if not already set
    filter ??= StateFilter(lazyLoadMembers: true);
    filter.lazyLoadMembers ??= true;

    if (prev_batch == null) {
      throw 'Tried to request history without a prev_batch token';
    }

    final resp = await client.getRelatingEvents(
      room.id,
      rootEvent.eventId,
      from: prev_batch,
      limit: historyCount,
      dir: direction,
      recurse: true,
    );

    if (onHistoryReceived != null) onHistoryReceived();

    await client.database.transaction(() async {
      if (storeInDatabase && direction == Direction.b) {
        this.prev_batch = resp.prevBatch;
        await client.database.setThreadPrevBatch(
          resp.prevBatch,
          room.id,
          rootEvent.eventId,
          client,
        );
      }
    });

    return resp.chunk.length;
  }
}
