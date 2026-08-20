// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';


import '../matrix.dart';

/// Abstract base class for all timeline implementations.
/// Provides common functionality for event management, aggregation, and search.
abstract class Timeline {
  /// The list of events in this timeline
  List<Event> get events;

  /// Map of event ID to map of type to set of aggregated events
  final Map<String, Map<String, Set<Event>>> aggregatedEvents = {};

  /// Called when the timeline is updated
  final void Function()? onUpdate;
  
  /// Called when an event at specific index changes
  final void Function(int index)? onChange;
  
  /// Called when an event is inserted at specific index
  final void Function(int index)? onInsert;
  
  /// Called when an event is removed from specific index
  final void Function(int index)? onRemove;
  
  /// Called when a new event is added to the timeline
  final void Function()? onNewEvent;

  bool get canRequestHistory;
  bool get canRequestFuture;
  bool get allowNewEvent;
  bool get isRequestingFuture;
  bool get isRequestingHistory;
  bool get isFragmentedTimeline;

  Timeline({
    this.onUpdate,
    this.onChange,
    this.onInsert,
    this.onRemove,
    this.onNewEvent,
  });

  /// Searches for the event in this timeline. If not found, requests from server.
  Future<Event?> getEventById(String id);

  /// Request more previous events
  Future<void> requestHistory({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  });

  /// Request more future events
  Future<void> requestFuture({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  });

  /// Set the read marker to an event in this timeline
  Future<void> setReadMarker({String? eventId, bool? public});

  /// Request keys for undecryptable events
  void requestKeys({
    bool tryOnlineBackup = true,
    bool onlineKeyBackupOnly = true,
  });

  /// Search events in this timeline
  Stream<(List<Event>, String?)> startSearch({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? prevBatch,
    @Deprecated('Use [prevBatch] instead.') String? sinceEventId,
    int? limit,
    bool Function(Event)? searchFunc,
  });

  Future<void> fetchAggregatedEvents(
    String eventId,
    String relType, {
    String? eventType,
  });

  /// Cancel all subscriptions
  void cancelSubscriptions();
}

// TODO: make up a better name
extension TimelineExtension on List<Event> {
  int get firstIndexWhereNotError {
    if (isEmpty) return 0;
    final index = indexWhere((event) => !event.status.isError);
    if (index == -1) return length;
    return index;
  }
}