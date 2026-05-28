; ---------------------------------------------------------------------
; Error logging:
; - Records unhandled runtime errors to a local workspace log.
; - Load-time parser errors cannot be caught by OnError.
; ---------------------------------------------------------------------

AppLogUnhandledError(thrown, mode) {
    logPath := AppGetLocalErrorLogPath()
    EnsureParentDirectory(logPath)

    stamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    text := "`r`n## " stamp " - " mode "`r`n`r`n"

    if IsObject(thrown) {
        text .= "- Message: " AppErrorProp(thrown, "Message") "`r`n"
        text .= "- What: " AppErrorProp(thrown, "What") "`r`n"
        text .= "- File: " AppErrorProp(thrown, "File") "`r`n"
        text .= "- Line: " AppErrorProp(thrown, "Line") "`r`n"
        extra := AppErrorProp(thrown, "Extra")
        if (extra != "")
            text .= "- Extra: " extra "`r`n"
        stack := AppErrorProp(thrown, "Stack")
        if (stack != "")
            text .= "`r`nStack:`r`n`r`n" AppIndentLogBlock(stack) "`r`n"
    } else {
        text .= "- Value: " thrown "`r`n"
    }

    try FileAppend(text, logPath, "UTF-8")

    ; Keep AutoHotkey's normal error dialog visible while also logging locally.
    return 0
}

AppIndentLogBlock(text) {
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    out := ""
    Loop Parse text, "`n" {
        out .= "    " A_LoopField "`r`n"
    }
    return out
}

AppGetLocalErrorLogPath() {
    return A_ScriptDir "\logs\errorlog.md"
}

AppErrorProp(obj, propName) {
    try {
        if HasProp(obj, propName)
            return obj.%propName% ""
    }
    return ""
}
