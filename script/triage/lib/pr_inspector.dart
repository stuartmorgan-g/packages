// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'types.dart';
import 'utils.dart';

late String githubToken;

Future<List<Map<String, dynamic>>> fetchOpenPRs(String repo) async {
  final List<Map<String, dynamic>> allPrs = [];
  var page = 1;
  var hasNext = true;

  while (hasNext) {
    final Uri url = Uri.parse(
      'https://api.github.com/repos/$repo/pulls?state=open&per_page=100&page=$page',
    );
    try {
      final http.Response response = await _fetchGitHubUrl(url);

      if (response.statusCode == 200) {
        final List<Object> currentPrs = (jsonDecode(response.body) as List<dynamic>).cast<Object>();
        if (currentPrs.isEmpty) {
          hasNext = false;
          break;
        }
        allPrs.addAll(currentPrs.cast<Map<String, dynamic>>());

        // Check for next page in Link header
        final String? linkHeader = response.headers['link'];
        if (linkHeader != null && linkHeader.contains('rel="next"')) {
          page++;
        } else {
          hasNext = false;
        }
      } else {
        print('Failed to fetch PRs page $page: ${response.statusCode} ${response.reasonPhrase}');
        return allPrs; // Return what we have so far
      }
    } catch (e) {
      print('Error fetching PRs page $page: $e');
      return allPrs; // Return what we have so far
    }
  }
  return allPrs;
}

Future<PRInfo?> fetchPR(String repo, int prNumber) async {
  final Map<String, dynamic>? pr = await fetchSinglePR(repo, prNumber);
  if (pr == null) {
    return null;
  }
  final prAuthor = (pr['user']! as Map<String, dynamic>)['login']! as String;
  final DateTime prCreationDate = DateTime.parse(pr['created_at']! as String);
  final isDraft = pr['draft']! as bool;

  // Fetch all three types of comments
  final _PRCommentResult inlineReviews = await _fetchPRComments(
    repo,
    prNumber,
    authorUsername: prAuthor,
    commentType: _CommentType.reviewInline,
  );
  final _PRCommentResult overallReviews = await _fetchPRComments(
    repo,
    prNumber,
    authorUsername: prAuthor,
    commentType: _CommentType.reviewOverall,
    pendingReviewers: await _fetchPendingReviewers(repo, prNumber),
  );
  final _PRCommentResult issueComments = await _fetchPRComments(
    repo,
    prNumber,
    authorUsername: prAuthor,
    commentType: _CommentType.issue,
  );

  final LatestComments mergedComments = _mergeCommentAnalysis([
    inlineReviews.comments,
    overallReviews.comments,
    issueComments.comments,
  ]);

  final ({
    Comment? authorComment,
    Comment? memberComment,
    Comment? nonMemberComment,
    Map<ReviewState, int>? reviewStateCount,
  })
  commentAnalysis = (
    authorComment: mergedComments.author,
    memberComment: mergedComments.member,
    nonMemberComment: mergedComments.nonMember,
    reviewStateCount: overallReviews.reviewStateCount,
  );

  final ContributorType authorType;
  if (prAuthor.endsWith('[bot]') ||
      prAuthor == 'fluttergithubbot' ||
      prAuthor == 'engine-flutter-autoroll') {
    authorType = ContributorType.bot;
  } else if (pr['author_association'] == 'OWNER' ||
      pr['author_association'] == 'MEMBER' ||
      pr['author_association'] == 'COLLABORATOR') {
    authorType = ContributorType.member;
  } else {
    authorType = ContributorType.community;
  }

  return PRInfo(
    number: prNumber,
    author: prAuthor,
    title: pr['title']! as String,
    creationDate: prCreationDate,
    isDraft: isDraft,
    authorType: authorType,
    url: pr['html_url']! as String,
    comments: commentAnalysis,
  );
}

// Merges multiple LatestComments, keeping the newest for each category.
LatestComments _mergeCommentAnalysis(List<LatestComments> commentList) {
  return (
    author: newestComment(commentList.map((c) => c.author).toList()),
    member: newestComment(commentList.map((c) => c.member).toList()),
    nonMember: newestComment(commentList.map((c) => c.nonMember).toList()),
  );
}

enum _CommentType { issue, reviewInline, reviewOverall }

typedef _PRCommentResult = ({LatestComments comments, Map<ReviewState, int>? reviewStateCount});

Future<_PRCommentResult> _fetchPRComments(
  String repo,
  int prNumber, {
  required String authorUsername,
  required _CommentType commentType,
  Iterable<String> pendingReviewers = const [],
}) async {
  Comment? latestAuthorComment;
  Comment? latestMemberComment;
  Comment? latestNonMemberComment;
  var page = 1;
  var hasNext = true;

  final String urlBase;
  final bool sorted;
  final String dateKey;
  switch (commentType) {
    case _CommentType.reviewInline:
      urlBase = 'https://api.github.com/repos/$repo/pulls/$prNumber/comments';
      sorted = true;
      dateKey = 'updated_at';
    case _CommentType.reviewOverall:
      urlBase = 'https://api.github.com/repos/$repo/pulls/$prNumber/reviews';
      sorted = false;
      dateKey = 'submitted_at';
    case _CommentType.issue:
      urlBase = 'https://api.github.com/repos/$repo/issues/$prNumber/comments';
      sorted = false;
      dateKey = 'updated_at';
  }
  final Map<String, ReviewState> reviewStates = {};
  while (hasNext) {
    Uri url;
    if (sorted) {
      // For sortable sources, sort descending and use the standard page size.
      url = Uri.parse('$urlBase?sort=created&direction=desc&page=$page');
    } else {
      // For non-sortable sources, use the maximum page size since we will need
      // to retrieve all comments.
      url = Uri.parse('$urlBase?per_page=100&page=$page');
    }
    try {
      final http.Response response = await _fetchGitHubUrl(url);

      if (response.statusCode == 200) {
        final List<Map<String, dynamic>> comments = (jsonDecode(response.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();
        if (comments.isEmpty) {
          hasNext = false;
          break;
        }

        for (final comment in comments) {
          final author = (comment['user']! as Map<String, dynamic>)['login']! as String;
          // Ignore bots.
          if (author.endsWith('[bot]') || author == 'fluttergithubbot') {
            continue;
          }

          final association = comment['author_association']! as String;
          final DateTime date = DateTime.parse(comment[dateKey]! as String);
          final Comment currentComment = (username: author, date: date);

          if (author == authorUsername) {
            if (latestAuthorComment == null ||
                (!sorted && date.isAfter(latestAuthorComment.date))) {
              latestAuthorComment = currentComment;
            }
          } else if (association == 'MEMBER' ||
              association == 'OWNER' ||
              association == 'COLLABORATOR') {
            if (commentType == _CommentType.reviewOverall) {
              switch (comment['state']) {
                case 'APPROVED':
                  reviewStates[author] = ReviewState.approved;
                case 'CHANGES_REQUESTED':
                  reviewStates[author] = ReviewState.changesRequested;
                case 'PENDING':
                  reviewStates[author] = ReviewState.pending;
                case 'COMMENTED':
                  reviewStates[author] = ReviewState.commented;
                default:
                  reviewStates.remove(author);
              }
            }
            if (latestMemberComment == null ||
                (!sorted && date.isAfter(latestMemberComment.date))) {
              latestMemberComment = currentComment;
            }
          } else {
            if (latestNonMemberComment == null ||
                (!sorted && date.isAfter(latestNonMemberComment.date))) {
              latestNonMemberComment = currentComment;
            }
          }
        }

        // If we found both important comments, we can stop for sorted searches.
        if (sorted && latestAuthorComment != null && latestMemberComment != null) {
          break;
        }

        final String? linkHeader = response.headers['link'];
        if (linkHeader != null && linkHeader.contains('rel="next"')) {
          page++;
        } else {
          hasNext = false;
        }
      } else {
        print(
          'Failed to fetch comments for PR #$prNumber ($commentType) page $page: ${response.statusCode} ${response.reasonPhrase}',
        );
        break;
      }
    } catch (e) {
      print('Error fetching comments for PR #$prNumber ($commentType) page $page: $e');
      break;
    }
  }
  // Add pending reviewers to the review states. If someone is in the pending
  // reviewers list, any review comment found above is older than the last
  // time review was re-requested, so replace those states.
  for (final reviewer in pendingReviewers) {
    reviewStates[reviewer] = ReviewState.pending;
  }
  final Map<ReviewState, int> reviewStateCount = {};
  for (final ReviewState state in reviewStates.values) {
    reviewStateCount[state] = (reviewStateCount[state] ?? 0) + 1;
  }
  return (
    comments: (
      author: latestAuthorComment,
      member: latestMemberComment,
      nonMember: latestNonMemberComment,
    ),
    reviewStateCount: commentType == _CommentType.reviewOverall ? reviewStateCount : null,
  );
}

Future<Iterable<String>> _fetchPendingReviewers(String repo, int prNumber) async {
  final Uri url = Uri.parse(
    'https://api.github.com/repos/$repo/pulls/$prNumber/requested_reviewers',
  );
  try {
    final http.Response response = await _fetchGitHubUrl(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final List<Map<String, dynamic>> users = (data['users']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return users.map((user) => user['login']! as String);
    } else {
      print(
        'Failed to fetch reviewers for PR #$prNumber: ${response.statusCode} ${response.reasonPhrase}',
      );
      return [];
    }
  } catch (e) {
    print('Error fetching reviewers for PR #$prNumber: $e');
    return [];
  }
}

Future<Map<String, dynamic>?> fetchSinglePR(String repo, int prNumber) async {
  final Uri url = Uri.parse('https://api.github.com/repos/$repo/pulls/$prNumber');
  try {
    final http.Response response = await _fetchGitHubUrl(url);
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as Map<String, dynamic>).cast<String, Object>();
    } else {
      print('Failed to fetch PR #$prNumber: ${response.statusCode} ${response.reasonPhrase}');
      return null;
    }
  } catch (e) {
    print('Error fetching PR #$prNumber: $e');
    return null;
  }
}

Future<http.Response> _fetchGitHubUrl(Uri url) async {
  return http.get(
    url,
    headers: githubToken.isNotEmpty ? {'Authorization': 'Bearer $githubToken'} : {},
  );
}
