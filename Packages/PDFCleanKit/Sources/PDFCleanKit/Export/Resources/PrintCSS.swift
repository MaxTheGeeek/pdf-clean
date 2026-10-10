import Foundation

/// Print-friendly CSS for `HTMLRenderer`'s document skeleton. A Swift string constant,
/// not a loaded resource file: the HTML export must stay fully self-contained offline
/// (constitution P1), and `Package.swift`'s `.copy("Fixtures")`-style resource rules
/// don't mix with compiled sources in the same directory (see T-003's spec drift note),
/// so this content lives in source, not in a `.css` file read at runtime.
enum PrintCSS {
    static let css = """
        body{font-family:-apple-system,Helvetica,Arial,sans-serif;line-height:1.5;margin:2em auto;max-width:40em;padding:0 1em;color:#111}
        h1,h2,h3,h4,h5,h6{line-height:1.25;margin-top:1.5em;margin-bottom:0.5em}
        p{margin:0.75em 0}
        pre{background:#f4f4f4;padding:0.75em;overflow-x:auto;white-space:pre-wrap}
        code,pre{font-family:ui-monospace,Menlo,Consolas,monospace}
        ul,ol{margin:0.5em 0;padding-left:1.5em}
        nav ol{list-style:decimal}
        hr{border:none;border-top:1px solid #ccc;margin:2em 0}
        @media print{body{max-width:none}}
        """
}
