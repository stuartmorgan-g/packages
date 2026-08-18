// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

enum CommentFreshness { fresh, stale, veryStale, none }

// The subset of review states that we want to display.
enum ReviewState { approved, changesRequested, pending, commented }

enum ContributorType { member, bot, community }

typedef Comment = ({String username, DateTime date});
typedef LatestComments = ({Comment? author, Comment? member, Comment? nonMember});

typedef CommentAnalysis = ({
  Comment? authorComment,
  Comment? memberComment,
  Comment? nonMemberComment,
  Map<ReviewState, int>? reviewStateCount,
});

class PRAnalysis {
  PRAnalysis({
    required this.pr,
    required this.authorFreshness,
    required this.memberFreshness,
    required this.teamStaleDays,
    required this.missingReviewer,
    required this.hasInProgressReview,
  });

  final PRInfo pr;
  final CommentFreshness authorFreshness;
  final CommentFreshness memberFreshness;
  final int teamStaleDays;
  final bool missingReviewer;
  final bool hasInProgressReview;
}

class PRInfo {
  PRInfo({
    required this.number,
    required this.author,
    required this.title,
    required this.creationDate,
    required this.authorType,
    required this.isDraft,
    required this.url,
    required this.comments,
  });

  final int number;
  final String author;
  final String title;
  final DateTime creationDate;
  final ContributorType authorType;
  final bool isDraft;
  final String url;
  final CommentAnalysis comments;
}
