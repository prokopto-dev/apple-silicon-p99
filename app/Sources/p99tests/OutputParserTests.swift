import P99Core

private let ESC = "\u{1B}"

func runOutputParserTests() {
    // The exact byte sequences config.sh's say/warn/die emit.
    T.equal(OutputParser.parse("\(ESC)[1;32m==>\(ESC)[0m Downloading wrapper template"),
            .say("Downloading wrapper template"), "say line with ANSI")
    T.equal(OutputParser.parse("\(ESC)[1;33mWARN:\(ESC)[0m could not fetch arial32 — continuing"),
            .warn("could not fetch arial32 — continuing"), "warn line with ANSI")
    T.equal(OutputParser.parse("\(ESC)[1;31mERROR:\(ESC)[0m no game files at /tmp/x"),
            .error("no game files at /tmp/x"), "error line with ANSI")

    T.equal(OutputParser.parse("==> hello"), .say("hello"), "plain say")
    T.equal(OutputParser.parse("WARN: w"), .warn("w"), "plain warn")
    T.equal(OutputParser.parse("ERROR: e"), .error("e"), "plain error")

    // curl --progress-bar emits \r-delimited chunks like these.
    T.equal(OutputParser.parse("######                       45.3%"), .percent(45.3), "curl chunk 45.3")
    T.equal(OutputParser.parse(" 0.1%"), .percent(0.1), "curl chunk 0.1")
    T.equal(OutputParser.parse("############################ 100.0%"), .percent(100.0), "curl chunk 100")
    T.equal(OutputParser.parse("7%"), .percent(7), "integer percent")
    T.equal(OutputParser.parse("150.0%"), .percent(100), "percent capped at 100")

    // Only a bar-shaped line counts; prose mentioning % is raw output.
    T.equal(OutputParser.parse("done 45.3% of the work"), .raw("done 45.3% of the work"),
            "percent mid-sentence is raw")
    T.equal(OutputParser.parse("45.3% done"), .raw("45.3% done"), "trailing prose is raw")

    T.equal(OutputParser.parse("  extracting archive  "), .raw("extracting archive"),
            "raw line trimmed")
    T.equal(OutputParser.parse("\(ESC)[1;36msome tool output\(ESC)[0m"), .raw("some tool output"),
            "raw line ANSI-stripped")

    T.equal(OutputParser.stripANSI("\(ESC)[1;32mgreen\(ESC)[0m plain"), "green plain", "stripANSI")
    T.equal(OutputParser.stripANSI("no codes"), "no codes", "stripANSI no-op")
}
