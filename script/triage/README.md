This is a partially vibe-coded prototype for a PR triage tool. It attempts to classify PRs by
whose turn it is to act next (the Flutter team or the PR author), sort within categories by
how recently they have been commented on, and flag PRs that are missing reviewers.

The heuristics are imperfect, and currently it must run locolly, manually. If the team decides
to continue using it, it should be productionized and the heuristics should be improved.

To run it, add a GitHub token to your environment, and then run the tools with a target
repo (flutter/packages or /core-packges) and output file:

```sh
export GITHUB_TOKEN=github_pat_YOUR_TOKEN
dart run bin/pr_inspector.dart flutter/packages --html  /tmp/triage.html
```

Then open `/tmp/triage.html` in your browser.
