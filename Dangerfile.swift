import Danger
import Foundation

let danger = Danger()

/// 1. Check for CHANGELOG entry (skip for chore/ deps/ docs-only)
let isChangelogRequired = !danger.github.pullRequest.title.lowercased().hasPrefix("chore") &&
    !danger.github.pullRequest.title.lowercased().hasPrefix("deps") &&
    !danger.github.pullRequest.title.lowercased().hasPrefix("docs")
let hasChangelog = danger.git.modifiedFiles.contains { $0.hasPrefix("CHANGELOG") || $0.hasPrefix("changelog") }
if isChangelogRequired && !hasChangelog {
    warn("Please add a CHANGELOG entry for your changes")
}

// 2. Check PR size (warn if >600 lines)
let additions = danger.github.pullRequest.additions
let deletions = danger.github.pullRequest.deletions
let totalChanges = additions + deletions
if totalChanges > 600 {
    warn("PR is large (\(totalChanges) changes). Consider splitting into smaller PRs.")
}

// 3. Ensure assignees
if danger.github.pullRequest.assignee == nil {
    warn("Please assign someone to review this PR")
}

// 4. Check for debug code left behind
let swiftFiles = danger.git.modifiedFiles.filter { $0.hasSuffix(".swift") }
let debugLeft = swiftFiles.filter { content in
    let fileContent = try? danger.utils.readFile(content)
    return fileContent?.contains("print(\"DEBUG") == true ||
        fileContent?.contains("fatalError(") == true
}

if !debugLeft.isEmpty {
    warn("Debug code or fatalError found in: \(debugLeft.joined(separator: ", "))")
}

/// 5. Check for untracked/secrets files
let hasEnv = danger.git.createdFiles.contains { $0.hasSuffix(".env") || $0.hasPrefix(".env.") }
if hasEnv {
    fail("Do not commit .env files. Use Doppler or environment variables.")
}

/// 6. Verify docs updated for user-facing changes
let isUserFacing = danger.github.pullRequest.title.lowercased().contains("feature") ||
    danger.github.pullRequest.title.lowercased().contains("fix")
let hasDocs = danger.git.modifiedFiles.contains { $0.hasPrefix("docs/") || $0.hasPrefix("README") }
if isUserFacing, !hasDocs, !danger.github.pullRequest.title.lowercased().hasPrefix("chore") {
    message("Consider updating documentation")
}

/// 7. SwiftLint check results (if available)
let swiftLintSummary = danger.utils.parseResultsLink()

/// Summary message
var summaryLines: [String] = []
summaryLines.append("### Summary")
summaryLines.append("- Files: \(danger.git.modifiedFiles.count)")
summaryLines.append("- Additions: +\(additions)")
summaryLines.append("- Deletions: -\(deletions)")
message(summaryLines.joined(separator: "\n"))
