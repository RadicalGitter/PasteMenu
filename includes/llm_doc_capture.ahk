; ---------------------------------------------------------------------
; LLM document capture:
; - Cheaply detect Word/PDF context for the active paste target.
; - Extract markdown from Word via COM (deferred to LLM click time).
;   Falls back to clipboard (Ctrl+A → Ctrl+C) when COM is unavailable
;   (e.g. Protected View, UAC mismatch, Office sandbox).
; - Extract plain text from PDF readers via clipboard (lazy).
; Browser selections use normal selected-text capture. Browser PDF titles are
; deliberately not treated as document contexts because title-only detection
; produces false positives on ordinary web pages.
; ---------------------------------------------------------------------

; Detect doc context for a captured paste target. Returns 0 if none.
LLMDocDetectContext(target) {
    if !IsObject(target) || !target.HasOwnProp("win") || !target.win
        return 0

    procName := ""
    try procName := WinGetProcessName("ahk_id " target.win)
    procLower := StrLower(procName)

    if (procLower = "winword.exe")
        return LLMDocDetectWord(target)

    if LLMDocIsPdfContext(target, procLower)
        return LLMDocDetectPdf(target, procName)

    return 0
}

; Cheap document check used by the root menu gate. It must not touch the
; clipboard or bind COM; otherwise document support makes normal menu open slow.
LLMDocIsActiveDocumentContext(hwnd := 0) {
    if !hwnd
        hwnd := WinActive("A")
    if !hwnd
        return false

    procName := ""
    try procName := WinGetProcessName("ahk_id " hwnd)
    procLower := StrLower(procName)
    if (procLower = "winword.exe")
        return true

    target := {win: hwnd}
    return LLMDocIsPdfContext(target, procLower)
}

LLMDocIsPdfContext(target, procLower := "") {
    if !IsObject(target) || !target.HasOwnProp("win") || !target.win
        return false
    if (procLower = "") {
        procName := ""
        try procName := WinGetProcessName("ahk_id " target.win)
        procLower := StrLower(procName)
    }

    return LLMDocIsDedicatedPdfProcess(procLower)
}

LLMDocIsDedicatedPdfProcess(procLower) {
    static known := Map(
        "acrord32.exe", true,
        "acrobat.exe", true,
        "foxitpdfreader.exe", true,
        "foxitreader.exe", true,
        "sumatrapdf.exe", true,
        "pdfxedit.exe", true
    )
    return known.Has(procLower)
}

LLMDocIsBrowserProcess(procLower) {
    static known := Map(
        "chrome.exe", true,
        "msedge.exe", true,
        "firefox.exe", true,
        "brave.exe", true,
        "bravebrowser.exe", true,
        "vivaldi.exe", true,
        "opera.exe", true,
        "opera_gx.exe", true
    )
    return known.Has(procLower)
}

; ---------------- Word ----------------

; Cheap detection: use process/title only, then defer COM and markdown extraction.
LLMDocDetectWord(target) {
    winTitle := ""
    try winTitle := WinGetTitle("ahk_id " target.win)
    docName := LLMDocExtractWordFileNameFromTitle(winTitle)
    if (docName = "")
        docName := winTitle != "" ? winTitle : "Word document"

    return {
        kind: "word",
        fileName: docName,
        hasSelection: false,
        payloadMarkdown: "",
        preview: "",
        payloadLabel: "selection or full document",
        deferredExtractor: LLMDocWordDeferredExtract.Bind(target)
    }
}

; Deferred Word extraction — called when the LLM item is clicked.
; 1. Re-acquires COM and runs the paragraph walker (structured markdown).
; 2. If COM is unavailable, falls back to Ctrl+A → Ctrl+C (plain text).
LLMDocWordDeferredExtract(target) {
    ; --- COM path (preferred: structured markdown) ---
    wordApp := 0
    try wordApp := ComObjActive("Word.Application")
    if IsObject(wordApp) {
        wordWindow := LLMDocWordFindTargetWindow(wordApp, target)
        if !IsObject(wordWindow)
            return LLMDocWordClipboardExtract(target)

        selection := 0
        try selection := wordWindow.Selection
        selText := ""
        if IsObject(selection)
            try selText := selection.Text
        selText := LLMDocCleanWordText(selText)
        if (Trim(selText) != "") {
            md := ""
            try md := LLMDocWordRangeToMarkdown(selection.Range)
            if (Trim(md) != "")
                return md
            ; A known selection is more important than preserving formatting.
            return selText
        }

        activeDoc := 0
        try activeDoc := wordWindow.Document
        if IsObject(activeDoc) {
            md := ""
            try md := LLMDocWordRangeToMarkdown(activeDoc.Content)
            if (Trim(md) != "")
                return md
        }
    }

    ; --- Clipboard fallback (plain text, no markdown structure) ---
    ; Works when COM is blocked by Protected View, UAC, or Office sandboxing.
    return LLMDocWordClipboardExtract(target)
}

; Returns the Word window matching the captured target instead of trusting
; Word.Application.Selection, which may belong to another open document.
LLMDocWordFindTargetWindow(wordApp, target) {
    if !IsObject(wordApp) || !IsObject(target) || !target.HasOwnProp("win") || !target.win
        return 0

    count := 0
    try count := wordApp.Windows.Count
    Loop count {
        wordWindow := 0
        try wordWindow := wordApp.Windows.Item(A_Index)
        if !IsObject(wordWindow)
            continue
        hwnd := 0
        try hwnd := wordWindow.Hwnd
        if (hwnd = target.win)
            return wordWindow
    }
    return 0
}

; Clipboard-based Word extraction: first copy the user's current selection,
; then fall back to the whole document only when nothing was selected.
LLMDocWordClipboardExtract(target) {
    if !LLMDocActivateForCapture(target)
        return ""

    clipSaved := 0
    hasSavedClip := false
    try {
        clipSaved := ClipboardAll()
        hasSavedClip := true
    }

    sentinel := "__PASTEMENU_LLM_WORD_SENT__" A_TickCount "__"
    extracted := ""
    didSelectAll := false

    if LLMDocPdfSetSentinel(sentinel) {
        Send "^c"
        extracted := LLMDocPdfWaitForClipboard(sentinel, 500)
    }

    if (Trim(extracted) = "") {
        ; No current selection — capture the whole document.
        if !LLMDocPdfSetSentinel(sentinel)
            return ""
        Send "^a"
        Sleep 35
        didSelectAll := true
        Send "^c"
        extracted := LLMDocPdfWaitForClipboard(sentinel, 1200)
    }

    ; Collapse the selection so the document looks untouched after capture.
    if didSelectAll
        Send "{Left}"

    if hasSavedClip
        try A_Clipboard := clipSaved

    return extracted
}

; Extract a document name from a Word window title.
; Handles: "filename.docx - Microsoft Word", "filename [Read-Only] - Word", etc.
LLMDocExtractWordFileNameFromTitle(title) {
    if (title = "")
        return ""
    ; Prefer an explicit .docx filename in the title.
    if RegExMatch(title, 'i)([^\\/:*?"<>|]+\.docx)', &m)
        return m[1]
    ; Fall back to text before the " - Word" separator.
    if RegExMatch(title, '^(.+?)\s+-\s+(?:Microsoft\s+)?Word\b', &m)
        return Trim(m[1])
    return ""
}

LLMDocWordRangeToMarkdown(range) {
    if !IsObject(range)
        return ""

    out := ""
    processedTables := Map()

    paragraphs := 0
    try paragraphs := range.Paragraphs
    if !IsObject(paragraphs)
        return ""

    count := 0
    try count := paragraphs.Count

    i := 1
    while (i <= count) {
        para := 0
        try para := paragraphs.Item(i)
        if !IsObject(para) {
            i += 1
            continue
        }

        if LLMDocWordParagraphInTable(para) {
            tbl := 0
            try tbl := para.Range.Tables.Item(1)
            if IsObject(tbl) {
                key := 0
                try key := tbl.Range.Start
                if !processedTables.Has(key) {
                    processedTables[key] := true
                    out .= LLMDocWordTableToMarkdown(tbl) "`r`n"
                }
            }
            i += 1
            continue
        }

        out .= LLMDocWordParagraphToMarkdown(para) "`r`n"
        i += 1
    }

    ; Trim trailing newlines but keep internal structure.
    while (SubStr(out, -1) = "`n" || SubStr(out, -1) = "`r")
        out := SubStr(out, 1, StrLen(out) - 1)
    return out
}

LLMDocWordParagraphInTable(para) {
    info := 0
    try info := para.Range.Information(12) ; wdWithInTable
    return info ? true : false
}

LLMDocWordParagraphToMarkdown(para) {
    text := ""
    try text := para.Range.Text
    text := LLMDocCleanWordText(text)

    ; Replace inline images.
    shapeCount := 0
    try shapeCount := para.Range.InlineShapes.Count
    imagePrefix := ""
    if (shapeCount > 0) {
        Loop shapeCount
            imagePrefix .= "<Inserted image, not included in send>`r`n"
    }

    if (Trim(text) = "") {
        ; Empty paragraph: preserve as blank line.
        return imagePrefix = "" ? "" : RTrim(imagePrefix, "`r`n")
    }

    outlineLevel := 10
    try outlineLevel := para.OutlineLevel
    listType := 0
    try listType := para.Range.ListFormat.ListType

    ; Apply uniform whole-paragraph bold/italic if mixed-state detection is unavailable.
    bold := 0
    italic := 0
    try bold := para.Range.Bold
    try italic := para.Range.Italic

    inner := LLMDocWordResolveInline(para)
    if (inner = "")
        inner := text

    ; Whole-paragraph wrap only if not already wrapped inline.
    if (bold = -1 && !InStr(inner, "**"))
        inner := "**" inner "**"
    if (italic = -1 && !InStr(inner, "*") && !InStr(inner, "_"))
        inner := "*" inner "*"

    prefix := ""
    if (listType = 2 || listType = 3 || listType = 4 || listType = 5) {
        ; Numbered / outline / mixed list.
        level := 1
        try level := para.Range.ListFormat.ListLevelNumber
        if (level < 1)
            level := 1
        indent := ""
        Loop level - 1
            indent .= "  "
        marker := (listType = 2 || listType = 4 || listType = 5) ? "1. " : "- "
        prefix := indent marker
    } else if (listType = 1) {
        level := 1
        try level := para.Range.ListFormat.ListLevelNumber
        if (level < 1)
            level := 1
        indent := ""
        Loop level - 1
            indent .= "  "
        prefix := indent "- "
    } else if (outlineLevel >= 1 && outlineLevel <= 9) {
        hashes := ""
        n := Min(outlineLevel, 6)
        Loop n
            hashes .= "#"
        prefix := hashes " "
    }

    return imagePrefix prefix inner
}

LLMDocWordResolveInline(para) {
    rng := 0
    try rng := para.Range
    if !IsObject(rng)
        return ""

    text := ""
    try text := rng.Text
    text := LLMDocCleanWordText(text)
    if (text = "")
        return ""

    ; Substitute hyperlinks as [text](url).
    hyperlinks := 0
    try hyperlinks := rng.Hyperlinks
    if IsObject(hyperlinks) {
        hCount := 0
        try hCount := hyperlinks.Count
        Loop hCount {
            hl := 0
            try hl := hyperlinks.Item(A_Index)
            if !IsObject(hl)
                continue
            display := ""
            try display := hl.TextToDisplay
            if (display = "") {
                try display := hl.Range.Text
            }
            address := ""
            try address := hl.Address
            if (display = "" || address = "")
                continue
            displayClean := LLMDocCleanWordText(display)
            replacement := "[" displayClean "](" address ")"
            text := StrReplace(text, displayClean, replacement, , , 1)
        }
    }

    return text
}

LLMDocWordTableToMarkdown(tbl) {
    rows := 0
    cols := 0
    try rows := tbl.Rows.Count
    try cols := tbl.Columns.Count
    if (rows < 1 || cols < 1)
        return ""

    out := ""
    Loop rows {
        rowIdx := A_Index
        line := "|"
        colIdx := 1
        while (colIdx <= cols) {
            cellText := ""
            try {
                cell := tbl.Cell(rowIdx, colIdx)
                cellText := cell.Range.Text
            }
            cellText := LLMDocCleanWordText(cellText)
            cellText := StrReplace(cellText, "`r`n", " ")
            cellText := StrReplace(cellText, "`r", " ")
            cellText := StrReplace(cellText, "`n", " ")
            cellText := StrReplace(cellText, "|", "\|")
            line .= " " Trim(cellText) " |"
            colIdx += 1
        }
        out .= line "`r`n"

        if (rowIdx = 1) {
            sep := "|"
            Loop cols
                sep .= " --- |"
            out .= sep "`r`n"
        }
    }

    while (SubStr(out, -1) = "`n" || SubStr(out, -1) = "`r")
        out := SubStr(out, 1, StrLen(out) - 1)
    return out
}

LLMDocCleanWordText(text) {
    if (text = "")
        return ""
    ; Word ends paragraphs with \r (0x0D) and end-of-cell with 0x07; strip those.
    text := StrReplace(text, Chr(0x07), "")
    text := StrReplace(text, Chr(0x0B), "`n") ; vertical tab → line break
    text := StrReplace(text, Chr(0x0D), "")
    return text
}

LLMDocStripMarkdownForPreview(md) {
    if (md = "")
        return ""
    out := md
    out := RegExReplace(out, "m)^#{1,6}\s*", "")
    out := RegExReplace(out, "m)^\s*[-*]\s+", "")
    out := RegExReplace(out, "m)^\s*\d+\.\s+", "")
    out := StrReplace(out, "**", "")
    out := StrReplace(out, "<Inserted image, not included in send>", "")
    return out
}

; ---------------- PDF ----------------

LLMDocDetectPdf(target, procName) {
    title := ""
    try title := WinGetTitle("ahk_id " target.win)
    fileName := LLMDocExtractPdfFileName(title)
    if (fileName = "")
        fileName := title != "" ? title : procName

    return {
        kind: "pdf",
        fileName: fileName,
        hasSelection: false,
        payloadMarkdown: "",
        preview: "",
        payloadLabel: "PDF text (extracted on send)",
        deferredExtractor: LLMDocExtractPdfPayload.Bind(target)
    }
}

LLMDocExtractPdfFileName(title) {
    if (title = "")
        return ""
    if RegExMatch(title, 'i)([^\\/:*?"<>|]+\.pdf)', &m)
        return m[1]
    return ""
}

LLMDocExtractPdfPayload(target) {
    if !IsObject(target)
        return ""

    procName := ""
    try procName := WinGetProcessName("ahk_id " target.win)
    procLower := StrLower(procName)

    if LLMDocIsBrowserProcess(procLower) {
        pdfPath := LLMDocTryGetBrowserLocalPdfPath(target)
        if (pdfPath != "") {
            text := LLMDocExtractPdfViaPdfToText(pdfPath)
            if (Trim(text) != "")
                return text
            text := LLMDocExtractPdfViaWord(pdfPath)
            if (Trim(text) != "")
                return text
        }
    }

    return LLMDocExtractPdfPlainText(target)
}

LLMDocTryGetBrowserLocalPdfPath(target) {
    url := LLMDocGetBrowserAddress(target)
    path := LLMDocFileUrlToPath(url)
    if (path = "")
        return ""
    if !RegExMatch(path, "i)\.pdf$")
        return ""
    if !FileExist(path)
        return ""
    return path
}

LLMDocGetBrowserAddress(target) {
    if !LLMDocActivateForCapture(target)
        return ""

    clipSaved := 0
    hasSavedClip := false
    try {
        clipSaved := ClipboardAll()
        hasSavedClip := true
    }

    sentinel := "__PASTEMENU_LLM_URL_SENTINEL__" A_TickCount "__"
    url := ""
    if LLMDocPdfSetSentinel(sentinel) {
        Send "^l"
        Sleep 25
        Send "^c"
        url := LLMDocPdfWaitForClipboard(sentinel, 500)
        Send "{Esc}"
    }

    if hasSavedClip
        try A_Clipboard := clipSaved

    return Trim(url)
}

LLMDocFileUrlToPath(url) {
    url := Trim(url)
    if !RegExMatch(url, "i)^file://")
        return ""

    ; Local drive URL: file:///E:/Downloads/name.pdf
    if RegExMatch(url, "i)^file:///([A-Za-z]:/.*)$", &m) {
        path := LLMDocUrlUnescape(m[1])
        return StrReplace(path, "/", "\")
    }

    ; UNC URL: file://server/share/name.pdf
    if RegExMatch(url, "i)^file://([^/]+)/(.+)$", &m) {
        server := LLMDocUrlUnescape(m[1])
        sharePath := LLMDocUrlUnescape(m[2])
        return "\\" server "\" StrReplace(sharePath, "/", "\")
    }

    return ""
}

LLMDocUrlUnescape(value) {
    if (value = "")
        return ""
    buf := Buffer((StrLen(value) + 1) * 2, 0)
    StrPut(value, buf, "UTF-16")
    ; URL_UNESCAPE_INPLACE = 0x00100000
    try DllCall("Shlwapi.dll\UrlUnescapeW", "Ptr", buf.Ptr, "Ptr", 0, "Ptr", 0, "UInt", 0x00100000)
    return StrGet(buf, "UTF-16")
}

LLMDocExtractPdfViaPdfToText(pdfPath) {
    exePath := LLMDocFindPdfToTextExe()
    if (exePath = "" || pdfPath = "" || !FileExist(pdfPath))
        return ""

    outPath := A_Temp "\PasteMenu_pdftotext_" A_TickCount "_" Random(100000, 999999) ".txt"
    cmd := LLMDocQuoteArg(exePath) " -layout -enc UTF-8 " LLMDocQuoteArg(pdfPath) " " LLMDocQuoteArg(outPath)
    exitCode := 1
    try exitCode := RunWait(cmd, , "Hide")

    text := ""
    if (exitCode = 0 && FileExist(outPath)) {
        try text := ReadTextFile(outPath, "UTF-8")
    }
    try FileDelete(outPath)
    return text
}

LLMDocFindPdfToTextExe() {
    static cached := "__unset__"
    if (cached != "__unset__")
        return cached

    candidates := []
    root := ""
    try root := LLMCallsGetLocalRootDir()
    if (root != "") {
        candidates.Push(root "\pdftotext.exe")
        candidates.Push(root "\tools\pdftotext.exe")
        candidates.Push(root "\bin\pdftotext.exe")
        candidates.Push(root "\third_party\pdftotext\pdftotext.exe")
    }
    candidates.Push(A_ScriptDir "\pdftotext.exe")
    candidates.Push(A_ScriptDir "\tools\pdftotext.exe")
    candidates.Push(A_ScriptDir "\bin\pdftotext.exe")
    candidates.Push(A_ScriptDir "\third_party\pdftotext\pdftotext.exe")

    pathEnv := EnvGet("PATH")
    Loop Parse pathEnv, ";" {
        dir := Trim(A_LoopField, " `t`"")
        if (dir != "")
            candidates.Push(dir "\pdftotext.exe")
    }

    for _, candidate in candidates {
        if FileExist(candidate) {
            cached := candidate
            return cached
        }
    }

    cached := ""
    return cached
}

LLMDocQuoteArg(value) {
    return '"' StrReplace(value, '"', '\"') '"'
}

LLMDocExtractPdfViaWord(pdfPath) {
    if (pdfPath = "" || !FileExist(pdfPath))
        return ""

    wordApp := 0
    doc := 0
    text := ""
    try {
        wordApp := ComObject("Word.Application")
        wordApp.Visible := false
        wordApp.DisplayAlerts := 0
        doc := wordApp.Documents.Open(pdfPath, false, true)
        text := doc.Content.Text
        text := LLMDocCleanWordText(text)
    }
    try {
        if IsObject(doc)
            doc.Close(0)
    }
    try {
        if IsObject(wordApp)
            wordApp.Quit(0)
    }
    return text
}

; Lazy extraction for PDFs: try Ctrl+C; if clipboard stays empty, Ctrl+A then Ctrl+C.
; Returns markdown-ish plain text (no structure available from PDF).
LLMDocExtractPdfPlainText(target) {
    if !IsObject(target)
        return ""
    if !LLMDocActivateForCapture(target)
        return ""

    clipSaved := 0
    hasSavedClip := false
    try {
        clipSaved := ClipboardAll()
        hasSavedClip := true
    }

    extracted := ""
    sentinel := "__PASTEMENU_LLM_PDF_SENTINEL__" A_TickCount "__"

    ; First attempt: copy whatever is already selected.
    if LLMDocPdfSetSentinel(sentinel) {
        Send "^c"
        text := LLMDocPdfWaitForClipboard(sentinel, 260)
        if (text != "" && !LLMDocLooksLikePdfUrl(text))
            extracted := text
    }

    ; Fallback: select all then copy.
    if (extracted = "") {
        if LLMDocPdfSetSentinel(sentinel) {
            Send "^a"
            Sleep 35
            Send "^c"
            text := LLMDocPdfWaitForClipboard(sentinel, 1400)
            if (text != "" && !LLMDocLooksLikePdfUrl(text))
                extracted := text
        }
        ; Collapse the selection so the PDF looks untouched after capture.
        if (extracted != "")
            Send "{Left}"
    }

    if hasSavedClip {
        try A_Clipboard := clipSaved
    }

    return extracted
}

LLMDocLooksLikePdfUrl(text) {
    text := Trim(text)
    return RegExMatch(text, "i)^(file|https?)://.*\.pdf(?:$|[?#])")
}

LLMDocNormalizePdfText(text) {
    if (text = "")
        return ""

    normalized := StrReplace(text, "`r`n", "`n")
    normalized := StrReplace(normalized, "`r", "`n")
    lines := StrSplit(normalized, "`n")
    paragraphs := []
    current := ""

    for _, rawLine in lines {
        line := Trim(rawLine)
        if (line = "") {
            if (current != "") {
                paragraphs.Push(current)
                current := ""
            }
            continue
        }

        if (current = "") {
            current := line
            continue
        }

        if LLMDocPdfShouldKeepLineBreak(current, line) {
            paragraphs.Push(current)
            current := line
        } else {
            trimmedCurrent := RTrim(current)
            if (SubStr(trimmedCurrent, 0) = "-")
                current := RTrim(SubStr(trimmedCurrent, 1, StrLen(trimmedCurrent) - 1)) line
            else
                current := trimmedCurrent " " line
        }
    }

    if (current != "")
        paragraphs.Push(current)

    out := ""
    for _, para in paragraphs {
        if (out != "")
            out .= "`r`n`r`n"
        out .= para
    }
    return out
}

LLMDocPdfShouldKeepLineBreak(prevLine, nextLine) {
    prevLine := RTrim(prevLine)
    nextLine := Trim(nextLine)

    if RegExMatch(nextLine, "i)^(\s*[-*•]|\s*\d+[\.)]\s+|\s*[A-Z][A-Z0-9 ,:/-]{5,}$)")
        return true
    if RegExMatch(prevLine, "[.!?;:\)\]]$")
        return true
    if RegExMatch(nextLine, "^\s{2,}")
        return true

    return false
}

LLMDocPdfSetSentinel(sentinel) {
    try A_Clipboard := sentinel
    catch {
        return false
    }
    deadline := A_TickCount + 80
    while (A_TickCount < deadline) {
        if (A_Clipboard = sentinel)
            return true
        Sleep 5
    }
    return false
}

; Fast-focus helper used only for clipboard-based capture — never for paste.
; Shorter timeout than FocusPasteTarget: we only need the window to receive ^a/^c,
; not guarantee foreground readiness for a paste operation.
LLMDocActivateForCapture(target) {
    if !IsObject(target) || !target.HasOwnProp("win") || !target.win
        return false
    if !WinExist("ahk_id " target.win)
        return false

    try WinActivate("ahk_id " target.win)
    activated := 0
    try activated := WinWaitActive("ahk_id " target.win,, 0.35)
    if !activated
        return false

    if target.HasOwnProp("ctrlName") && target.ctrlName != ""
        try ControlFocus(target.ctrlName, "ahk_id " target.win)
    Sleep 30
    return true
}

LLMDocPdfWaitForClipboard(sentinel, timeoutMs) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        cur := A_Clipboard
        if (cur != "" && cur != sentinel)
            return cur
        Sleep 25
    }
    return ""
}

; ---------------- Preview helper ----------------

LLMDocBuildPreview(text) {
    if (text = "")
        return ""
    cleaned := Trim(StrReplace(StrReplace(StrReplace(text, "`r`n", " "), "`r", " "), "`n", " "))
    cleaned := RegExReplace(cleaned, "\s+", " ")
    if (StrLen(cleaned) <= 80)
        return cleaned

    head := SubStr(cleaned, 1, 32)
    tail := SubStr(cleaned, -32)
    return Trim(head) " [...] " Trim(tail)
}

; Resolve the payload markdown to send for an LLM call. Returns "" if none.
; If the context has a deferred extractor (e.g. PDF), runs it now.
LLMDocResolvePayload(docContext) {
    if !IsObject(docContext)
        return ""
    if docContext.HasOwnProp("payloadMarkdown") && docContext.payloadMarkdown != ""
        return docContext.payloadMarkdown
    if docContext.HasOwnProp("deferredExtractor") && docContext.deferredExtractor {
        text := ""
        try text := docContext.deferredExtractor.Call()
        if (text != "") {
            docContext.payloadMarkdown := text
            return text
        }
    }
    return ""
}
