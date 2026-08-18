// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'types.dart';

// Formats an ISO 8601 date to YYYY-MM-DD format.
String formatAsDay(DateTime date) {
  return date.toIso8601String().split('T').first;
}

Comment? newestComment(List<Comment?> comments) {
  final List<Comment> nonNull = comments.whereType<Comment>().toList();
  nonNull.sort((a, b) => b.date.compareTo(a.date));
  return nonNull.firstOrNull;
}

String emojiForReviewState(ReviewState state) {
  return switch (state) {
    ReviewState.approved => '✅',
    ReviewState.changesRequested => '❌',
    ReviewState.pending => '🟠',
    ReviewState.commented => '💬',
  };
}

String emojiForContributorType(ContributorType type) {
  return switch (type) {
    ContributorType.member => '💼',
    ContributorType.bot => '🤖',
    ContributorType.community => '🌎',
  };
}
