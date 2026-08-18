// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'types.dart';
import 'utils.dart';

void generateHtml(String repo, List<PRAnalysis> prs, File file) {
  file.createSync(recursive: true);
  final buffer = StringBuffer();
  buffer.write(_generateHtmlHeader(repo));
  for (final pr in prs) {
    buffer.write(_generatePRRow(repo, pr));
  }
  buffer.write(_generateHtmlFooter());
  file.writeAsStringSync(buffer.toString());
}

String _generateHtmlHeader(String repo) {
  return '''
<!DOCTYPE html>
<html>
<head>
<title>PR Inspector: $repo</title>
<style>
  body { font-family: sans-serif; margin: 20px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
  tr { font-size: 11pt; }
  tr:nth-child(even) { background-color: #ebf7fd; }
  th, td { border: none; padding: 8px; text-align: left; vertical-align: top; }
  th { background-color: #7dc7f4; }
  h1 { font-size: 1.5em; }
  .draft { color: #888; }
  .date-header { min-width: 6em; }
  .date-red { color: red; }
  .date-yellow { color: orange; }
  .date-green { color: green; }
  .missing-reviewer { background-color: #ffcccc; }
</style>
</head>
<body>
  <h1>$repo PRs</h1>
  <table>
    <thead>
      <tr>
        <th>PR</th>
        <th>Title</th>
        <th>Author</th>
        <th class="date-header">Created</th>
        <th class="date-header">Last Author Comment</th>
        <th class="date-header">Last Member Comment</th>
        <th class="date-header">Last Other Comment</th>
        <th class="date-header">Reviews</th>
      </tr>
    </thead>
    </tbody>
''';
}

String _generateHtmlFooter() {
  return '''
    </tbody>
  </table>
</body>
</html>
''';
}

String _generatePRRow(String repo, PRAnalysis prAnalysis) {
  final PRInfo pr = prAnalysis.pr;
  final Map<ReviewState, int>? reviewStateCount = pr.comments.reviewStateCount;
  var reviewStateString = '';
  for (final ReviewState state in ReviewState.values) {
    final int count = reviewStateCount?[state] ?? 0;
    if (count > 0) {
      // Break between other review states and pending reviews.
      if (reviewStateString.isNotEmpty && state == ReviewState.pending) {
        reviewStateString += '<br>';
      }
      reviewStateString += emojiForReviewState(state) * count;
    }
  }
  return '''
  <tr>
    <td><a href="${pr.url}" target="_blank">#${pr.number}</a></td>
    <td ${pr.isDraft ? 'class="draft"' : ''}>${_escapeHtml(pr.title)}</td>
    <td>${emojiForContributorType(pr.authorType)} ${_escapeHtml(pr.author)}</td>
    <td>${formatAsDay(pr.creationDate)}</td>
    <td class="${_dateClassForFreshness(prAnalysis.authorFreshness)}">${_formatCommentHtml(pr.comments.authorComment)}</td>
    <td class="${_dateClassForFreshness(prAnalysis.memberFreshness)}">${_formatCommentHtml(pr.comments.memberComment)}</td>
    <td>${_formatCommentHtml(pr.comments.nonMemberComment)}</td>
    <td${prAnalysis.missingReviewer ? ' class="missing-reviewer"' : ''}>$reviewStateString</td>
  </tr>
''';
}

String _escapeHtml(String html) {
  return html
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _formatCommentHtml(Comment? comment) {
  if (comment == null) {
    return 'N/A';
  }
  return '${_escapeHtml(comment.username)}<br>${formatAsDay(comment.date)}';
}

String? _dateClassForFreshness(CommentFreshness freshness) {
  return switch (freshness) {
    CommentFreshness.fresh => 'date-green',
    CommentFreshness.stale => 'date-yellow',
    CommentFreshness.veryStale => 'date-red',
    CommentFreshness.none => null,
  };
}
