import Foundation

/// The single source of truth shared by the report and the living-spec views
/// so a `ReportSuite` produces a cohesive pair: identical anchors (deep links
/// can't drift), the same summary counts, one palette, and one theme
/// mechanism. Both `HTMLReportGenerator` and `SpecPageGenerator` render
/// through this.
enum ReportShared {

    // MARK: Anchors (the deep-link contract — both views agree by using these)

    static func featureAnchor(_ feature: Int) -> String { "feature-\(feature)" }
    static func scenarioAnchor(_ feature: Int, _ scenario: Int) -> String {
        "scenario-\(feature)-\(scenario)"
    }

    // MARK: Theme (palette + pre-paint + toggle — identical on both pages)

    /// Runs in <head> before first paint: restore the remembered theme (else
    /// the system preference) and the remembered rail state. No flash.
    static func themePrePaintScript() -> String {
        """
        <script>
        (function () {
          var t = localStorage.getItem('pickle-theme');
          if (!t) t = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
          document.documentElement.setAttribute('data-theme', t);
          if (localStorage.getItem('pickle-rail') === 'collapsed')
            document.documentElement.setAttribute('data-rail', 'collapsed');
        })();
        </script>

        """
    }

    /// The sidebar toggle (☰) — lives on the LEFT, beside the title, over the
    /// rail it controls.
    static func railToggleButton() -> String {
        "<button class=\"icon-btn\" onclick=\"toggleRail()\" aria-label=\"Toggle sidebar\" title=\"Toggle sidebar\">\u{2630}</button>"
    }

    /// The theme toggle (◐) — top-right, where theme switches conventionally sit.
    static func themeToggleButton() -> String {
        "<button class=\"icon-btn\" onclick=\"cycleTheme()\" aria-label=\"Toggle theme\" title=\"Toggle light/dark\">\u{25D0}</button>"
    }

    /// Theme cycling + the persistent-but-collapsible sidebar toggle
    /// (remembered, like the theme). Shared by both pages.
    static func cycleThemeJS() -> String {
        """
        function cycleTheme() {
          const root = document.documentElement;
          const next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
          root.setAttribute('data-theme', next);
          localStorage.setItem('pickle-theme', next);
        }
        function toggleRail() {
          const root = document.documentElement;
          if (root.getAttribute('data-rail') === 'collapsed') {
            root.removeAttribute('data-rail');
            localStorage.setItem('pickle-rail', 'expanded');
          } else {
            root.setAttribute('data-rail', 'collapsed');
            localStorage.setItem('pickle-rail', 'collapsed');
          }
        }
        """
    }

    /// The palette (Solarized Light / Dracula) plus the chrome both pages
    /// share: reset, body, the theme toggle, tags, links, and the summary
    /// cards + progress bars. Component-specific CSS lives in each generator.
    /// Returned WITHOUT a <style> wrapper; generators wrap it with their own.
    static func commonCSS() -> String {
        """
        /* Palette: Solarized Light / Dracula — the Soroban site's tokens.
           data-theme is set before paint by the head script. */
        :root, :root[data-theme="light"] {
          --bg: #fdf6e3; --surface: #eee8d5; --text: #073642;
          --muted: #657b83; --faint: #93a1a1; --accent: #268bd2;
          --error: #dc322f; --border: rgba(7,54,66,0.12); --shadow: rgba(7,54,66,0.06);
          --passed: #2aa198; --failed: #dc322f; --skipped: #93a1a1; --undefined: #b58900;
        }
        :root[data-theme="dark"] {
          --bg: #282a36; --surface: #343746; --text: #f8f8f2;
          --muted: #bd93f9; --faint: #6272a4; --accent: #ff79c6;
          --error: #ff5555; --border: rgba(248,248,242,0.1); --shadow: rgba(0,0,0,0.3);
          --passed: #50fa7b; --failed: #ff5555; --skipped: #6272a4; --undefined: #ffb86c;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font: 16px/1.6 system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: var(--text); padding: 20px; transition: background 0.2s ease, color 0.2s ease; -webkit-font-smoothing: antialiased; }
        a { color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        .page-header-left { display: flex; align-items: center; gap: 0.7rem; }
        .icon-btn { border: 1px solid var(--border); background: var(--bg); color: var(--muted); border-radius: 8px; width: 2.2rem; height: 2.2rem; font-size: 1.05rem; cursor: pointer; line-height: 1; flex: none; }
        .icon-btn:hover { color: var(--text); }
        .tag { display: inline-block; background: color-mix(in srgb, var(--accent) 14%, transparent); color: var(--accent); padding: 2px 8px; border-radius: 999px; font-size: 11px; margin-right: 4px; }
        /* Shared page header — identical on both views so they read as one
           family: a title row with the theme toggle, a muted sub-line, and a
           cross-link, on a 1040px centered column with a bottom divider. */
        .page-width { max-width: 1040px; margin-left: auto; margin-right: auto; }
        .page-header { max-width: 1040px; margin: 0 auto 1.25rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border); }
        .page-header-row { display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
        .page-header h1 { font-size: 1.7rem; letter-spacing: -0.015em; }
        .page-sub { margin-top: 0.5rem; color: var(--faint); font-size: 0.9rem; }
        .page-sub .check { color: var(--passed); font-weight: 700; }
        .page-sub strong { color: var(--text); }
        .cross-link { margin-top: 0.4rem; font-size: 0.9rem; }
        /* Shared two-column layout + persistent sticky outline rail — both
           views are identical here: a pinned feature list with scroll-spy. */
        .page-layout { max-width: 1040px; margin: 0 auto; display: grid; grid-template-columns: 210px minmax(0, 1fr); gap: 2.5rem; align-items: start; }
        .page-body { min-width: 0; }
        .rail { position: sticky; top: 1rem; max-height: calc(100vh - 2rem); overflow-y: auto; overscroll-behavior: contain; font-size: 0.9rem; line-height: 1.4; }
        .rail h2 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--faint); margin-bottom: 0.6rem; }
        .rail ul { list-style: none; border-left: 1px solid var(--border); }
        .rail a { display: flex; align-items: center; gap: 0.45rem; padding: 0.25rem 0 0.25rem 0.85rem; color: var(--muted); font-weight: 600; border-left: 2px solid transparent; margin-left: -1px; text-decoration: none; }
        .rail a:hover { color: var(--accent); }
        .rail a[aria-current] { color: var(--accent); border-left-color: var(--accent); }
        .rail .dot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
        .rail .dot.passed { background: var(--passed); }
        .rail .dot.failed { background: var(--failed); }
        .rail .dot.skipped { background: var(--skipped); }
        @media (max-width: 900px) { .page-layout { grid-template-columns: 1fr; } .rail { display: none; } }
        /* Persistent by default, collapsible on demand (☰) — remembered. */
        html[data-rail="collapsed"] .page-layout { grid-template-columns: minmax(0, 1fr); }
        html[data-rail="collapsed"] .rail { display: none; }
        /* Feature sections render as the SAME card on both views — defined
           by a border, not a grey fill, so the theme stays clean. */
        .feature, .spec-feature { border: 1px solid var(--border); border-radius: 12px; margin-bottom: 16px; overflow: hidden; }
        /* Scenario-outline groups: an outline's expanded examples collapse
           under one header (name + count), so a run of cases reads as one
           family instead of N look-alike rows. The accent stripe marks the
           span; nested cases indent and lose their own top border. */
        .outline-group { border-top: 1px solid var(--border); }
        .outline-group > summary { display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem 1.1rem; cursor: pointer; list-style: none; border-left: 3px solid var(--accent); }
        .outline-group > summary::-webkit-details-marker { display: none; }
        .outline-group > summary::before { content: '\\25B6'; font-size: 10px; color: var(--faint); transition: transform 0.2s; flex: none; }
        .outline-group[open] > summary::before { transform: rotate(90deg); }
        .outline-group > summary:hover { background: color-mix(in srgb, var(--faint) 8%, transparent); }
        .outline-group[data-status="failed"] > summary { color: var(--failed); }
        .outline-name { flex: 1; min-width: 0; overflow-wrap: anywhere; font-weight: 600; }
        .outline-badge { flex: none; font-size: 0.7rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.03em; color: var(--accent); background: color-mix(in srgb, var(--accent) 14%, transparent); padding: 2px 8px; border-radius: 999px; }
        .outline-cases { border-left: 3px solid color-mix(in srgb, var(--accent) 35%, transparent); }
        .outline-cases > .scenario { border-top: 1px dashed var(--border); }
        .outline-cases > .scenario:first-child { border-top: none; }
        """
    }

    // MARK: Outline rail (the SAME component on both views)

    /// The persistent sticky outline rail: one jump link per feature with a
    /// status dot. Identical markup on report and spec; `railNavJS` powers
    /// the jump + scroll-spy. Feature elements must carry `id=featureAnchor(i)`.
    static func railHTML(from result: TestRunResult) -> String {
        var html = "<nav class=\"rail\" aria-label=\"Features\">\n  <h2>Features</h2>\n  <ul>\n"
        for (i, feature) in result.featureResults.enumerated() {
            let status = feature.failedCount > 0 ? "failed"
                : (feature.scenarioResults.allSatisfy(\.skipped) ? "skipped" : "passed")
            let id = featureAnchor(i)
            html += "    <li><a href=\"#\(id)\" data-target=\"\(id)\" onclick=\"jumpTo('\(id)'); return false;\">"
            html += "<span class=\"dot \(status)\"></span>\(esc(feature.featureName))</a></li>\n"
        }
        html += "  </ul>\n</nav>\n"
        return html
    }

    // MARK: Outline grouping (shared by both views)

    /// One run of a feature's scenarios: either a standalone scenario or a
    /// group of consecutive examples from the same `Scenario Outline`. The
    /// original index is preserved so anchors (`scenarioAnchor(feature, index)`)
    /// stay stable across both views.
    enum ScenarioSegment {
        case single(index: Int, scenario: ScenarioResult)
        case outline(name: String, cases: [(index: Int, scenario: ScenarioResult)])
    }

    /// Folds a feature's scenarios into segments: consecutive results sharing a
    /// non-nil `outlineName` collapse into one `.outline` group; everything
    /// else passes through as `.single`. Expansion is in source order, so a
    /// simple run-length pass groups each outline's examples exactly.
    static func segments(_ scenarios: [ScenarioResult]) -> [ScenarioSegment] {
        var segments: [ScenarioSegment] = []
        var i = 0
        while i < scenarios.count {
            let s = scenarios[i]
            guard let outline = s.outlineName else {
                segments.append(.single(index: i, scenario: s))
                i += 1
                continue
            }
            var cases: [(index: Int, scenario: ScenarioResult)] = []
            while i < scenarios.count, scenarios[i].outlineName == outline {
                cases.append((index: i, scenario: scenarios[i]))
                i += 1
            }
            segments.append(.outline(name: outline, cases: cases))
        }
        return segments
    }

    /// A group's rolled-up status for its header badge/colour.
    static func groupStatus(_ cases: [(index: Int, scenario: ScenarioResult)]) -> String {
        if cases.contains(where: { !$0.scenario.passed && !$0.scenario.skipped }) { return "failed" }
        if cases.allSatisfy({ $0.scenario.skipped }) { return "skipped" }
        return "passed"
    }

    /// jumpTo (opens a target that's a <details> or inside one, then scrolls)
    /// + scroll-spy that marks the rail link for the feature in view. Shared
    /// by both pages.
    static func railNavJS() -> String {
        """
        function jumpTo(id) {
          const el = document.getElementById(id);
          if (!el) return;
          if (el.tagName === 'DETAILS') el.open = true;
          const f = el.closest('details.feature');
          if (f) f.open = true;
          el.classList.remove('hidden');
          el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
        (function () {
          const links = new Map();
          document.querySelectorAll('.rail a[data-target]').forEach(a => links.set(a.dataset.target, a));
          if (!links.size) return;
          let current = null;
          const obs = new IntersectionObserver((entries) => {
            for (const e of entries) { if (e.isIntersecting) current = e.target.id; }
            links.forEach(a => a.removeAttribute('aria-current'));
            const active = current && links.get(current);
            if (active) active.setAttribute('aria-current', 'true');
          }, { rootMargin: '-10% 0px -80% 0px' });
          links.forEach((_, id) => { const el = document.getElementById(id); if (el) obs.observe(el); });
        })();
        """
    }

    /// CSS for the summary cards. Report-only — the spec shows its counts in
    /// the verified line instead of the full pass/fail/progress breakdown.
    static func summaryCSS() -> String {
        """
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 20px; }
        .summary-card { border: 1px solid var(--border); border-radius: 12px; padding: 16px; }
        .summary-card h3 { font-size: 13px; text-transform: uppercase; color: var(--faint); margin-bottom: 8px; letter-spacing: 0.04em; }
        .summary-card .count { font-size: 28px; font-weight: bold; }
        .summary-card .breakdown { font-size: 13px; color: var(--muted); margin-top: 4px; }
        .progress-bar { height: 8px; background: color-mix(in srgb, var(--faint) 25%, transparent); border-radius: 4px; overflow: hidden; margin-top: 8px; display: flex; }
        .progress-bar .passed { background: var(--passed); }
        .progress-bar .failed { background: var(--failed); }
        .progress-bar .skipped { background: var(--skipped); }
        .progress-bar .undefined { background: var(--undefined); }
        """
    }

    // MARK: Summary (report-only cards; the counts also drive the spec's line)

    static func summaryHTML(from result: TestRunResult) -> String {
        var html = "<div class=\"summary\">\n"

        html += "  <div class=\"summary-card\">\n"
        html += "    <h3>Features</h3>\n"
        html += "    <div class=\"count\">\(result.totalFeatureCount)</div>\n"
        html += "    <div class=\"breakdown\">\(result.passedFeatureCount) passed, \(result.failedFeatureCount) failed</div>\n"
        html += progressBar(passed: result.passedFeatureCount, failed: result.failedFeatureCount,
                            skipped: 0, undefined: 0, total: result.totalFeatureCount)
        html += "  </div>\n"

        html += "  <div class=\"summary-card\">\n"
        html += "    <h3>Scenarios</h3>\n"
        html += "    <div class=\"count\">\(result.totalScenarioCount)</div>\n"
        html += "    <div class=\"breakdown\">\(result.passedScenarioCount) passed, \(result.failedScenarioCount) failed"
        if result.skippedScenarioCount > 0 { html += ", \(result.skippedScenarioCount) skipped" }
        html += "</div>\n"
        html += progressBar(passed: result.passedScenarioCount, failed: result.failedScenarioCount,
                            skipped: result.skippedScenarioCount, undefined: 0,
                            total: result.totalScenarioCount)
        html += "  </div>\n"

        html += "  <div class=\"summary-card\">\n"
        html += "    <h3>Steps</h3>\n"
        html += "    <div class=\"count\">\(result.totalStepCount)</div>\n"
        html += "    <div class=\"breakdown\">\(result.passedStepCount) passed, \(result.failedStepCount) failed, \(result.skippedStepCount) skipped"
        if result.undefinedStepCount > 0 { html += ", \(result.undefinedStepCount) undefined" }
        html += "</div>\n"
        html += progressBar(passed: result.passedStepCount, failed: result.failedStepCount,
                            skipped: result.skippedStepCount, undefined: result.undefinedStepCount,
                            total: result.totalStepCount)
        html += "  </div>\n"

        html += "</div>\n"
        return html
    }

    private static func progressBar(passed: Int, failed: Int, skipped: Int, undefined: Int, total: Int) -> String {
        guard total > 0 else { return "" }
        func pct(_ n: Int) -> Double { Double(n) / Double(total) * 100 }
        var html = "    <div class=\"progress-bar\">"
        if passed > 0 { html += "<div class=\"passed\" style=\"width:\(pct(passed))%\"></div>" }
        if failed > 0 { html += "<div class=\"failed\" style=\"width:\(pct(failed))%\"></div>" }
        if skipped > 0 { html += "<div class=\"skipped\" style=\"width:\(pct(skipped))%\"></div>" }
        if undefined > 0 { html += "<div class=\"undefined\" style=\"width:\(pct(undefined))%\"></div>" }
        html += "</div>\n"
        return html
    }

    // MARK: Helpers (shared escaping + duration formatting)

    static func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 0.001 {
            return String(format: "%.0f\u{00B5}s", seconds * 1_000_000)
        } else if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.2fs", seconds)
        } else {
            let mins = Int(seconds) / 60
            let secs = seconds - Double(mins * 60)
            return String(format: "%dm %.1fs", mins, secs)
        }
    }
}
