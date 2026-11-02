import Foundation
import Testing
@testable import BrowserKit

@Suite struct PullContextTests {
    @Test func excerptSkipsTemplateBoilerplate() {
        let body = """
        <!-- Describe your change. Link the ticket. -->
        ## Summary

        Two concurrent 401s both call `refresh()`, and the second overwrites the **new** token with a stale one.
        This serializes refreshes behind one [task](https://example.com/task).

        ## Checklist
        - [x] Tests
        - [ ] Docs

        Closes #412
        """
        #expect(PullContext.excerpt(markdown: body)
                == "Two concurrent 401s both call refresh(), and the second overwrites the new token with a stale one. This serializes refreshes behind one task.")
    }

    @Test func excerptSkipsShortLinesImagesAndCode() {
        let body = """
        Fixes #3

        ![screenshot](https://example.com/a.png)

        ```swift
        let a = 1
        ```

        WIP

        - Replaces the JSON file cache with a GRDB table
        """
        #expect(PullContext.excerpt(markdown: body) == "Replaces the JSON file cache with a GRDB table")
    }

    @Test func excerptKeepsProseThatStartsWithFix() {
        #expect(PullContext.excerpt(markdown: "Fixes the crash when a tab closes during a download.")
                == "Fixes the crash when a tab closes during a download.")
    }

    @Test func excerptIsNilWithoutProse() {
        #expect(PullContext.excerpt(markdown: nil) == nil)
        #expect(PullContext.excerpt(markdown: "") == nil)
        #expect(PullContext.excerpt(markdown: "## Summary\n\n- [ ] Tests\n\nCloses #1") == nil)
    }

    @Test func areasDropSharedPrefixAndSourceFolders() {
        let paths = [
            "Packages/BrowserKit/Sources/BrowserKit/GitHub/GitHubClient.swift",
            "Packages/BrowserKit/Sources/BrowserKit/GitHub/PullContext.swift",
            "Packages/BrowserKit/Sources/BrowserKit/Persistence/AppDatabase.swift",
        ]
        #expect(PullContext.areas(paths: paths) == [.init(name: "GitHub", count: 2), .init(name: "Persistence", count: 1)])
    }

    @Test func areasAcrossPackagesSkipSourceFolders() {
        let paths = ["App/Pages/Reviews.swift", "Packages/BrowserKit/Sources/BrowserKit/GitHub/GitHubClient.swift"]
        #expect(PullContext.areas(paths: paths).map(\.name) == ["App/Pages", "Packages/BrowserKit"])
    }

    @Test func areasInOneFolderNameIt() {
        #expect(PullContext.areas(paths: ["App/Pages/A.swift", "App/Pages/B.swift"]) == [.init(name: "Pages", count: 2)])
        #expect(PullContext.areas(paths: ["App/Pages/A.swift"]) == [.init(name: "App/Pages", count: 1)])
    }

    @Test func areasMixRootFilesAndFolders() {
        let areas = PullContext.areas(paths: ["README.md", "App/Pages/A.swift", "App/Pages/B.swift", "project.yml"])
        #expect(areas.map(\.name) == ["App/Pages", "README.md", "project.yml"])
        #expect(PullContext.areas(paths: []).isEmpty)
    }

    @Test func fingerprintFollowsTheText() {
        let url = URL(string: "https://github.com/a/b/pull/1")!
        var pull = GitHubPull(repo: "a/b", number: 1, title: "Fix", url: url, body: "Body", files: ["a.swift"])
        let first = PullContext.fingerprint(pull)
        #expect(first == PullContext.fingerprint(pull))
        pull.updatedAt = Date()
        #expect(first == PullContext.fingerprint(pull))
        pull.body = "Changed"
        #expect(first != PullContext.fingerprint(pull))
    }

    @Test func summaryStoreRoundTripsAndPrunes() async throws {
        let store = PullSummaryStore(database: try AppDatabase.inMemory())
        await store.save(id: "a/b#1", fingerprint: "f1", summary: PullSummary(gist: "Gist", overview: "Overview."))
        let loaded = await store.load(["a/b#1", "a/b#2"])
        #expect(loaded.count == 1)
        #expect(loaded["a/b#1"]?.fingerprint == "f1")
        #expect(loaded["a/b#1"]?.summary == PullSummary(gist: "Gist", overview: "Overview."))
        await store.prune(keeping: [])
        #expect(await store.load(["a/b#1"]).count == 1)
    }
}
