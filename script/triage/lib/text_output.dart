// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_print

import 'package:ansicolor/ansicolor.dart';

import 'types.dart';
import 'utils.dart';

Future<void> printPRDetails(String repo, PRAnalysis prAnalysis) async {
  final PRInfo pr = prAnalysis.pr;
  final greypen = AnsiPen()..gray(level: 0.5);
  final Map<ReviewState, int>? reviewStateCount = pr.comments.reviewStateCount;
  var reviewStateString = '';
  for (final state in ReviewState.values) {
    final count = reviewStateCount?[state] ?? 0;
    if (count > 0) {
      reviewStateString += ' ${emojiForReviewState(state)}' * count;
    }
  }
  if (reviewStateString.isNotEmpty) {
    reviewStateString = ' $reviewStateString';
  }
  print(
    '  #${pr.number}: ${pr.isDraft ? greypen(pr.title) : pr.title} by ${emojiForContributorType(pr.authorType)}${pr.author} on ${formatAsDay(pr.creationDate)}$reviewStateString',
  );

  final greenPen = AnsiPen()..green();
  final yellowPen = AnsiPen()..yellow();
  final redPen = AnsiPen()..red();
  final AnsiPen? memberColor = _penForFreshness(
    prAnalysis.memberFreshness,
    greenPen,
    yellowPen,
    redPen,
  );
  final AnsiPen? authorColor = _penForFreshness(
    prAnalysis.authorFreshness,
    greenPen,
    yellowPen,
    redPen,
  );

  print('    Latest Comments:');
  print('      Author: ${_formatComment(pr.comments.authorComment, dateColor: authorColor)}');
  print('      Member: ${_formatComment(pr.comments.memberComment, dateColor: memberColor)}');
  print('      Non-Member: ${_formatComment(pr.comments.nonMemberComment)}');
  print('');
}

AnsiPen? _penForFreshness(CommentFreshness freshness, AnsiPen green, AnsiPen yellow, AnsiPen red) {
  return switch (freshness) {
    CommentFreshness.fresh => green,
    CommentFreshness.stale => yellow,
    CommentFreshness.veryStale => red,
    CommentFreshness.none => null,
  };
}

String _formatComment(Comment? comment, {AnsiPen? dateColor}) {
  if (comment == null) {
    return dateColor == null ? 'N/A' : dateColor('N/A');
  }
  String dateString = formatAsDay(comment.date);
  if (dateColor != null) {
    dateString = dateColor(dateString);
  }
  return '${comment.username} at $dateString';
}
