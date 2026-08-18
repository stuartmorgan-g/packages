// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:pr_inspector/html_output.dart';
import 'package:pr_inspector/pr_inspector.dart';
import 'package:pr_inspector/text_output.dart';
import 'package:pr_inspector/types.dart';
import 'package:pr_inspector/utils.dart';

Future<void> main(List<String> arguments) async {
  githubToken = Platform.environment['GITHUB_TOKEN'] ?? '';

  final parser = ArgParser()
    ..addOption('pr', abbr: 'p', help: 'The PR number to inspect.')
    ..addOption('html', help: 'Output as an HTML page to the given file.');

  const usage = '''
Usage:
  dart run bin/pr_inspector.dart <owner>/<repo> [--pr <PR number>] [--html <file>]
''';

  try {
    final ArgResults results = parser.parse(arguments);
    if (results.rest.length != 1) {
      print('Please provide exactly one repository (e.g., owner/repo).\n');
      print(usage);
      exit(64);
    }
    final String repo = results.rest.first;
    final prNumberOpt = results['pr'] as String?;
    final htmlFileOpt = results['html'] as String?;

    List<PRInfo> prs;
    if (prNumberOpt != null) {
      try {
        final int prNumber = int.parse(prNumberOpt);
        print('Fetching PR #$prNumber for $repo...');
        final PRInfo? pr = await fetchPR(repo, prNumber);
        if (pr != null) {
          prs = [pr];
        } else {
          print('PR #$prNumber not found in $repo.');
          exit(1);
        }
      } on FormatException {
        print('Error: --pr value must be an integer.\n');
        print(usage);
        exit(64);
      }
    } else {
      print('Fetching open PRs for $repo...');
      final List<Map<String, dynamic>> rawPRs = await fetchOpenPRs(repo);
      print('Found ${rawPRs.length} open PRs.');
      prs = [];
      for (final pr in rawPRs) {
        print('Analyzing PR #${pr['number']}...');
        final PRInfo? analyzedPr = await fetchPR(repo, pr['number']! as int);
        if (analyzedPr != null) {
          prs.add(analyzedPr);
        }
      }

      if (prs.isEmpty) {
        print('No open pull requests found for $repo.');
        exit(0);
      }
    }

    final List<PRAnalysis> analyzedPRs = prs.map(_analyzePR).toList();

    final List<PRAnalysis> sortedPRs = analyzedPRs
        .sortedBy<num>((item) {
          // Use score-based sorting to reduce boilerplate if/else-if chains.
          // - High score corresponds to things we most need to look at, so should
          //   sort to the top.
          // - Within a score band, the staleness of the PR, in days, is the score,
          //   so bands should be wide enough for a reasonable date range (e.g.,
          //   increments of 100 to allow for several months, which should be at the
          //   extreme end of how stale something can be).
          final DateTime newestImportantCommentDate =
              newestComment([
                if (item.teamStaleDays < 0) item.pr.comments.authorComment,
                item.pr.comments.memberComment,
              ])?.date ??
              item.pr.creationDate;
          final isCommunity = item.pr.authorType == ContributorType.community;
          final isBot = item.pr.authorType == ContributorType.bot;

          int score = newestImportantCommentDate.difference(DateTime.now()).inDays.abs();

          if (item.pr.isDraft) {
            // Team drafts are lowest priorty, with community drafts just above that.
            score += item.pr.authorType == ContributorType.member ? 0 : 100;
          } else if (isBot) {
            // Bots are just above those.
            score += 200;
          } else {
            // Anything with a missing reviewer is the highest priority,
            // and PRs with no in-progress review are next.
            if (isCommunity && item.missingReviewer) {
              score += 1000;
            } else if (isCommunity && item.missingReviewer) {
              score += 900;
            } else {
              // Sort everything else to the middle.
              score += 500;
              // ... but give PRs where the ball is in our court a little boost,
              // so we look at those more often. We give external contributors
              // more time to reply before we ping them.
              if (item.teamStaleDays >= 0) {
                score += 14;
              }
            }
          }

          return score;
        })
        // Sort the highest scores first.
        .reversed
        .toList();

    if (htmlFileOpt != null) {
      final file = File(htmlFileOpt);
      generateHtml(repo, sortedPRs, file);
    } else {
      for (final pr in sortedPRs) {
        await printPRDetails(repo, pr);
      }
    }
  } on ArgParserException catch (e) {
    print(e.message);
    print(usage);
    exit(64);
  }
}

PRAnalysis _analyzePR(PRInfo pr) {
  final DateTime lastAuthorCommentDate = pr.comments.authorComment?.date ?? pr.creationDate;
  final DateTime? lastMemberCommentDate = pr.comments.memberComment?.date;
  final bool lastCommentIsAuthor =
      lastMemberCommentDate == null || lastAuthorCommentDate.isAfter(lastMemberCommentDate);
  final isCommunityPR = pr.authorType == ContributorType.community;
  final bool hasBlockingReview =
      (pr.comments.reviewStateCount?[ReviewState.changesRequested] ?? 0) > 0;
  // In theory this should be a really useful signal, but we can't dismiss
  // revview requests that come from CODEOWNERS, so we don't use this. We may
  // want to revisit using CODEOWNERS in the first place.
  final bool hasPendingReview = (pr.comments.reviewStateCount?[ReviewState.pending] ?? 0) > 0;
  final bool hasCommentReview = (pr.comments.reviewStateCount?[ReviewState.commented] ?? 0) > 0;

  // Try to figure out if this PR is waiting for the author to do something, vs.
  // waiting for the Flutter team. This is heuristic, so will give wrong answers
  // sometimes. In general, err on the side of assuming it's waiting for the
  // Flutter team so that we look at it.
  var waitingForPRAuthor = false;
  if (pr.isDraft) {
    waitingForPRAuthor = true;
  } else if (hasBlockingReview && !lastCommentIsAuthor) {
    // This should generally be correct; if it's not we probably need to
    // re-request review in triage.
    waitingForPRAuthor = true;
  } else if (hasCommentReview && !lastCommentIsAuthor) {
    // This probably means that the author hasn't responded to review feedback
    // yet, but we'll need to see how often this is wrong (e.g., due to an
    // old comment review that was never dismissed).
    waitingForPRAuthor = true;
  } else if (isCommunityPR && !(hasBlockingReview || hasCommentReview)) {
    // If a community PR doesn't have any active requests from the team, that's
    // probably a sign that the ball is in our court.
    waitingForPRAuthor = false;
  } else if (!isCommunityPR && !lastCommentIsAuthor) {
    // For team PRs, where missing a PR that needs attention is much less of
    // an issue (since they can escalate directly with reviewers), just follow
    // the last comment date.
    waitingForPRAuthor = true;
  }
  // TODO(stuartmorgan): Other heuristics? Should we fall back on the last comment date if
  // we can't determine who's turn it is?

  CommentFreshness memberFreshness = CommentFreshness.none;
  CommentFreshness authorFreshness = CommentFreshness.none;

  int teamStaleDays;
  if (waitingForPRAuthor) {
    teamStaleDays = -1; // Not team's turn
    // Determine author freshness based on their last action
    final Duration authorElapsedTime = DateTime.now().difference(lastAuthorCommentDate);
    if (authorElapsedTime.inDays > 14) {
      authorFreshness = CommentFreshness.veryStale;
    } else if (authorElapsedTime.inDays > 7) {
      authorFreshness = CommentFreshness.stale;
    } else {
      authorFreshness = CommentFreshness.fresh;
    }
    // Member freshness is N/A if it's not their turn, unless there are no member comments
    memberFreshness = lastMemberCommentDate == null
        ? CommentFreshness.none
        : CommentFreshness.fresh;
  } else {
    final Duration elapsedTime = DateTime.now().difference(
      lastMemberCommentDate ?? pr.creationDate,
    );
    teamStaleDays = elapsedTime.inDays;
    if (elapsedTime.inDays > 14) {
      memberFreshness = CommentFreshness.veryStale;
    } else if (elapsedTime.inDays > 7) {
      memberFreshness = CommentFreshness.stale;
    } else {
      memberFreshness = CommentFreshness.fresh;
    }
  }

  final bool hasInProgressReview = hasPendingReview || hasCommentReview || hasBlockingReview;

  // Don't count <2 as missing unless one of them is an approval, since
  // community PR reviews are often intentionally serial (to reduce sunk time
  // if the PR is abandoned).
  final bool missingReviewer =
      isCommunityPR &&
      !hasInProgressReview &&
      (pr.comments.reviewStateCount?[ReviewState.approved] ?? 0) <= 1;

  return PRAnalysis(
    pr: pr,
    authorFreshness: authorFreshness,
    memberFreshness: memberFreshness,
    teamStaleDays: teamStaleDays,
    missingReviewer: missingReviewer,
    hasInProgressReview: hasInProgressReview,
  );
}
