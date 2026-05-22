; ---------------------------------------------------------------------
; Snippet + backup core:
; - Parse/serialize snippet file format
; - Atomic writes and normalization helpers
; - Tiered backup retention and change metadata snapshots
; ---------------------------------------------------------------------

; Validates snippet structure and can rewrite a normalized file version.
ValidateAndFixSnippetFile(path, encoding, defaultCategory, promptIfDifferent := true) {
    raw := ReadTextFile(path, encoding)
    if (raw = "") {
        EnsureSnippetFile(path)
        return "Snippet file was missing or unreadable and has been recreated."
    }

    categories := []
    entriesByCategory := Map()
    entryOrderByCategory := Map()

    parsed := LoadSnippetsFromFile(path, encoding, defaultCategory, &categories, &entriesByCategory, &entryOrderByCategory)
    if !parsed {
        ; Hard recovery path: preserve original content in a single recovered entry.
        categories := [defaultCategory]
        entriesByCategory := Map()
        entryOrderByCategory := Map()
        entriesByCategory[defaultCategory] := Map()
        entryOrderByCategory[defaultCategory] := ["Recovered"]
        entriesByCategory[defaultCategory]["Recovered"] := raw
    }

    fixedText := BuildSnippetsText(categories, entriesByCategory, entryOrderByCategory)
    same := (NormalizeForCompare(raw) = NormalizeForCompare(fixedText))
    if same
        return T("msg_validate_ok")

    if promptIfDifferent {
        ans := MsgBox(
            T("msg_fix_prompt"),
            T("msg_fix_title"),
            "YesNo Icon?"
        )
        if (ans != "Yes")
            return T("msg_validate_skipped")
    }

    backupPath := path ".bak_" A_Now
    if !WriteTextFileAtomic(backupPath, raw, encoding)
        return "Validation found issues, but failed to create backup: " backupPath

    if !WriteTextFileAtomic(path, fixedText, encoding)
        return "Validation found issues, but failed to write fixed snippet file."

    return "Automatic fix complete.`nBackup created:`n" backupPath
}

; Creates or builds build snippets text.
BuildSnippetsText(categories, entriesByCategory, entryOrderByCategory) {
    out := ""
    for _, category in categories {
        if !entriesByCategory.Has(category)
            continue

        out .= "{" category "}:" "`r`n"
        order := entryOrderByCategory[category]
        for _, title in order {
            if !entriesByCategory[category].Has(title)
                continue

            content := entriesByCategory[category][title]
            out .= "[" title "]:" "`r`n"
            if (content != "")
                out .= content "`r`n"
            out .= "`r`n"
        }
        if (order.Length = 0)
            out .= "`r`n"
    }
    return out
}

; Handles normalize for compare.
NormalizeForCompare(text) {
    normalizedText := StrReplace(text, "`r`n", "`n")
    normalizedText := StrReplace(normalizedText, "`r", "`n")
    ; Ignore trailing whitespace at end of lines for comparison purposes.
    normalizedText := RegExReplace(normalizedText, "[ \t]+(?=`n)")
    ; Ignore trailing newlines.
    normalizedText := RegExReplace(normalizedText, "(?:`n)+\z")
    return normalizedText
}

; Saves or serializes write text file atomic.
WriteTextFileAtomic(path, text, encoding) {
    EnsureParentDirectory(path)

    tmp := path ".tmp"
    try FileDelete(tmp)
    try {
        FileAppend(text, tmp, encoding)
        FileMove(tmp, path, 1)
        return true
    } catch {
        try FileDelete(tmp)
        return false
    }
}

; Loads or deserializes load snippets from file.
LoadSnippetsFromFile(path, encoding, defaultCategory, &categories, &entriesByCategory, &entryOrderByCategory) {
    text := ReadTextFile(path, encoding)
    if (text = "")
        return false

    categories           := []
    entriesByCategory    := Map()
    entryOrderByCategory := Map()

    currentCategory := ""
    currentTitle    := ""
    textBuffer      := []
    lines := StrSplit(text, "`n")
    for _, raw in lines {
        line := RTrim(raw, "`r")

        if RegExMatch(line, "^\s*\{([^{}]+)\}\s*:\s*$", &catMatch) {
            CommitEntry(currentCategory, currentTitle, textBuffer, &entriesByCategory)
            currentTitle := ""
            textBuffer   := []

            currentCategory := Trim(catMatch[1])
            if (currentCategory = "")
                currentCategory := defaultCategory
            EnsureCategoryExists(currentCategory, &categories, &entriesByCategory, &entryOrderByCategory)
            continue
        }

        if RegExMatch(line, "^\s*\[([^\]]+)\]\s*:\s*(.*)$", &entryMatch) {
            CommitEntry(currentCategory, currentTitle, textBuffer, &entriesByCategory)
            textBuffer := []

            if (currentCategory = "") {
                currentCategory := defaultCategory
                EnsureCategoryExists(currentCategory, &categories, &entriesByCategory, &entryOrderByCategory)
            }

            baseTitle := Trim(entryMatch[1])
            if (baseTitle = "")
                baseTitle := "Untitled"

            title := MakeUniqueEntryTitle(baseTitle, entryOrderByCategory[currentCategory])
            currentTitle := title
            entryOrderByCategory[currentCategory].Push(title)

            inline := entryMatch[2]
            if (inline != "")
                textBuffer.Push(inline)
            continue
        }

        if (currentTitle != "") {
            textBuffer.Push(line)
            continue
        }

        ; Recover non-empty lines outside an entry by creating a placeholder entry.
        if (Trim(line) != "") {
            if (currentCategory = "") {
                currentCategory := defaultCategory
                EnsureCategoryExists(currentCategory, &categories, &entriesByCategory, &entryOrderByCategory)
            }

            recoveredTitle := MakeUniqueEntryTitle("Recovered", entryOrderByCategory[currentCategory])
            currentTitle := recoveredTitle
            entryOrderByCategory[currentCategory].Push(currentTitle)
            textBuffer := [line]
            continue
        }
    }

    CommitEntry(currentCategory, currentTitle, textBuffer, &entriesByCategory)
    return (categories.Length > 0)
}

; Handles commit entry.
CommitEntry(category, title, bufferArr, &entriesByCategory) {
    if (category = "" || title = "")
        return
    content := JoinLines(bufferArr)
    entriesByCategory[category][title] := content
}

; Creates or builds ensure category exists.
EnsureCategoryExists(category, &categories, &entriesByCategory, &entryOrderByCategory) {
    if entriesByCategory.Has(category)
        return
    categories.Push(category)
    entriesByCategory[category] := Map()
    entryOrderByCategory[category] := []
}

; Creates or builds make unique entry title.
MakeUniqueEntryTitle(baseTitle, orderArr) {
    if !FindIndexInArray(orderArr, baseTitle)
        return baseTitle

    n := 2
    while FindIndexInArray(orderArr, baseTitle " (" n ")")
        n += 1
    return baseTitle " (" n ")"
}

; Returns or computes find index in array.
FindIndexInArray(arr, needle) {
    for i, v in arr {
        if (v = needle)
            return i
    }
    return 0
}

; Returns or computes read text file.
ReadTextFile(path, encoding) {
    try {
        text := FileRead(path, encoding)
        if (encoding = "UTF-8" && InStr(text, "�")) {
            try return FileRead(path, "CP1252")
        }
        return text
    } catch {
        try return FileRead(path)
    }
    return ""
}

; Saves or serializes save snippets to file.
SaveSnippetsToFile(path, encoding, change := 0, includeChangeBackup := true) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory

    out := BuildSnippetsText(_Categories, _EntriesByCategory, _EntryOrderByCategory)
    if !WriteTextFileAtomic(path, out, encoding)
        return false

    if includeChangeBackup
        ClearUndoState()
    CreateTieredSnippetBackups(path, out, encoding, change, includeChangeBackup)
    return true
}

; Returns or computes get snippet backup dir.
GetSnippetBackupDir(snippetPath) {
    SplitPath snippetPath, , &dir
    if (dir = "")
        return ""
    return dir "\backups"
}

; Creates or builds create tiered snippet backups.
CreateTieredSnippetBackups(snippetPath, text, encoding, change := 0, includeChangeBackup := true) {
    global _SettingsWindowState

    backupDir := GetSnippetBackupDir(snippetPath)
    if (backupDir = "")
        return
    if !EnsureDirectoryExists(backupDir)
        return

    now := A_Now
    if (includeChangeBackup && IsObject(change))
        CreateDetailedChangeBackup(backupDir, change, now)

    minuteKey := FormatTime(now, "yyyyMMdd_HHmm")
    tenMinKey := BuildTenMinuteBackupKey(now)
    hourKey := FormatTime(now, "yyyyMMdd_HH")
    dayKey := FormatTime(now, "yyyyMMdd")
    weekKey := FormatTime(now, "YWeek")
    if (weekKey = "")
        weekKey := A_YWeek
    monthKey := FormatTime(now, "yyyyMM")

    ; Bucketed snapshots provide coarse recovery without backup spam.
    ; Retention rules are enforced in PruneTierBackups().
    UpsertTierBackup(backupDir, "minute", minuteKey, text, encoding)
    UpsertTierBackup(backupDir, "tenmin", tenMinKey, text, encoding)
    UpsertTierBackup(backupDir, "hour", hourKey, text, encoding)
    UpsertTierBackup(backupDir, "day", dayKey, text, encoding)
    UpsertTierBackup(backupDir, "week", weekKey, text, encoding)
    UpsertTierBackup(backupDir, "month", monthKey, text, encoding)

    PruneTierBackups(backupDir)
    if IsObject(_SettingsWindowState)
        UpdateRestoreBackupButtonState(_SettingsWindowState)
}

; Creates or builds build ten minute backup key.
BuildTenMinuteBackupKey(yyyymmddhh24miss) {
    minuteNum := FormatTime(yyyymmddhh24miss, "mm") + 0
    bucketStart := Floor(minuteNum / 10) * 10
    return FormatTime(yyyymmddhh24miss, "yyyyMMdd_HH") Format("{:02}", bucketStart)
}

; Creates or builds create detailed change backup.
CreateDetailedChangeBackup(backupDir, change, yyyymmddhh24miss) {
    serialized := SerializeChangeBackup(change, yyyymmddhh24miss)
    if (serialized = "")
        return

    basePath := backupDir "\change_" FormatTime(yyyymmddhh24miss, "yyyyMMdd_HHmmss")
    backupPath := basePath ".pmc"
    n := 2
    while FileExist(backupPath) {
        backupPath := basePath "_" n ".pmc"
        n += 1
    }
    WriteTextFileAtomic(backupPath, serialized, "UTF-8")
}

; Handles upsert tier backup.
UpsertTierBackup(backupDir, tierName, bucketKey, text, encoding) {
    if (bucketKey = "")
        return

    backupPath := backupDir "\" tierName "_" bucketKey ".txt"
    if FileExist(backupPath) {
        existing := ReadTextFile(backupPath, encoding)
        if (NormalizeForCompare(existing) = NormalizeForCompare(text))
            return
    }
    WriteTextFileAtomic(backupPath, text, encoding)
}

; Deletes or removes prune tier backups.
PruneTierBackups(backupDir) {
    limits := Map(
        "change", 80,
        "minute", 1,
        "tenmin", 1,
        "hour", 1,
        "day", 1,
        "week", 1,
        "month", 1
    )
    byTier := Map()

    ; Group files by tier, then keep only the newest N per tier.
    Loop Files, backupDir "\*.*", "F" {
        fileName := A_LoopFileName
        if !RegExMatch(fileName, "i)^(change|minute|tenmin|hour|day|week|month)_.*\.(txt|pmc)$", &m)
            continue

        tier := StrLower(m[1])
        if !byTier.Has(tier)
            byTier[tier] := []
        byTier[tier].Push({path: A_LoopFileFullPath, modified: A_LoopFileTimeModified})
    }

    for tier, arr in byTier {
        if !limits.Has(tier)
            continue
        SortBackupItemsByModifiedDesc(arr)
        keep := limits[tier]
        for i, item in arr {
            if (i > keep)
                try FileDelete(item.path)
        }
    }
}

; Handles compare backup items by modified desc.
CompareBackupItemsByModifiedDesc(a, b, *) {
    if (a.modified = b.modified)
        return 0
    return (a.modified > b.modified) ? -1 : 1
}

; Sorts backup item arrays in-place using CompareBackupItemsByModifiedDesc().
SortBackupItemsByModifiedDesc(arr) {
    len := arr.Length
    if (len < 2)
        return arr

    ; Keep compatibility with AHK builds lacking Array.Sort().
    Loop (len - 1) {
        i := A_Index + 1
        current := arr[i]
        j := i - 1
        while (j >= 1 && CompareBackupItemsByModifiedDesc(current, arr[j]) < 0) {
            arr[j + 1] := arr[j]
            j -= 1
        }
        arr[j + 1] := current
    }
    return arr
}

; Returns or computes get available backups.
GetAvailableBackups() {
    global SnippetFile

    backups := []
    backupDir := GetSnippetBackupDir(SnippetFile)
    if (backupDir = "" || !DirExist(backupDir))
        return backups

    Loop Files, backupDir "\*.*", "F" {
        fileName := A_LoopFileName
        if !RegExMatch(fileName, "i)^(change|minute|tenmin|hour|day|week|month)_.*\.(txt|pmc)$", &m)
            continue

        tier := StrLower(m[1])
        modified := A_LoopFileTimeModified
        ageLabel := FormatRelativeBackupAge(modified)
        tierLabel := T("backup_tier_" tier)
        display := ageLabel " - " tierLabel
        isChange := false
        changeObj := 0

        if (tier = "change") {
            changeText := ReadTextFile(A_LoopFileFullPath, "UTF-8")
            if ParseChangeBackup(changeText, &parsed) {
                isChange := true
                changeObj := parsed
                display := ageLabel " - " FormatChangeBackupDisplay(parsed)
            }
        }

        backups.Push({
            path: A_LoopFileFullPath,
            tier: tier,
            modified: modified,
            display: display,
            isChange: isChange,
            change: changeObj
        })
    }

    SortBackupItemsByModifiedDesc(backups)
    return backups
}

; Handles prompt select backup index.
PromptSelectBackupIndex(backups) {
    labels := []
    for _, b in backups
        labels.Push(b.display)

    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", T("restore_window_title"))
    dlg.SetFont("s10", "Segoe UI")
    list := dlg.AddListBox("x12 y12 w560 h220", labels)
    if (labels.Length > 0)
        list.Choose(1)

    btnRestore := dlg.AddButton("x394 y242 w84 h28", T("restore_action"))
    btnCancel := dlg.AddButton("x488 y242 w84 h28", T("hotkey_dialog_cancel"))

    selectedIdx := 0
    btnRestore.OnEvent("Click", (*) => (selectedIdx := list.Value, dlg.Destroy()))
    btnCancel.OnEvent("Click", (*) => dlg.Destroy())
    dlg.OnEvent("Escape", (*) => dlg.Destroy())

    dlg.Show("w584 h278")
    WinWaitClose("ahk_id " dlg.Hwnd)
    return selectedIdx
}

; Returns or computes format relative backup age.
FormatRelativeBackupAge(yyyymmddhh24miss) {
    diffSec := 0
    try diffSec := DateDiff(A_Now, yyyymmddhh24miss, "Seconds")
    if (diffSec < 0)
        diffSec := 0

    if (diffSec < 1)
        return T("time_just_now")
    if (diffSec < 60)
        return FormatRelativeCount(diffSec, "time_second_one", "time_second_many")

    minutes := Floor(diffSec / 60)
    if (minutes < 60)
        return FormatRelativeCount(minutes, "time_minute_one", "time_minute_many")

    hours := Floor(diffSec / 3600)
    if (hours < 24)
        return FormatRelativeCount(hours, "time_hour_one", "time_hour_many")

    days := Floor(diffSec / 86400)
    if (days < 7)
        return FormatRelativeCount(days, "time_day_one", "time_day_many")
    if (days < 30)
        return FormatRelativeCount(Floor(days / 7), "time_week_one", "time_week_many")
    if (days < 365)
        return FormatRelativeCount(Floor(days / 30), "time_month_one", "time_month_many")
    return FormatRelativeCount(Floor(days / 365), "time_year_one", "time_year_many")
}

; Returns or computes format relative count.
FormatRelativeCount(count, oneKey, manyKey) {
    if (count <= 1)
        return T(oneKey)

    displayCount := (count <= 12) ? SmallNumberWord(count) : count
    return StrReplace(T(manyKey), "{1}", displayCount)
}

; Handles small number word.
SmallNumberWord(n) {
    global AppLanguage
    if (AppLanguage = "sv") {
        static wordsSv := Map(
            2, "tva",
            3, "tre",
            4, "fyra",
            5, "fem",
            6, "sex",
            7, "sju",
            8, "atta",
            9, "nio",
            10, "tio",
            11, "elva",
            12, "tolv"
        )
        if wordsSv.Has(n)
            return wordsSv[n]
        return n
    }

    static wordsEn := Map(
        2, "two",
        3, "three",
        4, "four",
        5, "five",
        6, "six",
        7, "seven",
        8, "eight",
        9, "nine",
        10, "ten",
        11, "eleven",
        12, "twelve"
    )
    if wordsEn.Has(n)
        return wordsEn[n]
    return n
}

; Saves or serializes serialize change backup.
SerializeChangeBackup(change, createdStamp) {
    if !IsObject(change)
        return ""

    out := "PM_CHANGE_V1`n"
    out .= "created=" createdStamp "`n"
    out .= "type=" StrLower(Trim(change.type)) "`n"
    out .= "before_category_b64=" Base64EncodeUtf8(change.beforeCategory) "`n"
    out .= "before_title_b64=" Base64EncodeUtf8(change.beforeTitle) "`n"
    out .= "before_exists=" (change.beforeExists ? "1" : "0") "`n"
    out .= "before_text_b64=" Base64EncodeUtf8(change.beforeText) "`n"
    out .= "after_category_b64=" Base64EncodeUtf8(change.afterCategory) "`n"
    out .= "after_title_b64=" Base64EncodeUtf8(change.afterTitle) "`n"
    out .= "after_exists=" (change.afterExists ? "1" : "0") "`n"
    out .= "after_text_b64=" Base64EncodeUtf8(change.afterText) "`n"
    return out
}

; Returns or computes parse change backup.
ParseChangeBackup(text, &change) {
    change := 0
    if (text = "")
        return false

    lines := StrSplit(StrReplace(text, "`r", ""), "`n")
    if (lines.Length < 2)
        return false
    if (Trim(lines[1]) != "PM_CHANGE_V1")
        return false

    ; Lightweight key=value format is easier to inspect and recover manually.
    meta := Map()
    for i, line in lines {
        if (i = 1 || Trim(line) = "")
            continue
        pos := InStr(line, "=")
        if (pos <= 1)
            continue
        key := Trim(SubStr(line, 1, pos - 1))
        val := SubStr(line, pos + 1)
        meta[key] := val
    }

    if !meta.Has("type")
        return false

    change := {
        type: meta["type"],
        created: meta.Has("created") ? meta["created"] : "",
        beforeCategory: Base64DecodeUtf8(meta.Has("before_category_b64") ? meta["before_category_b64"] : ""),
        beforeTitle: Base64DecodeUtf8(meta.Has("before_title_b64") ? meta["before_title_b64"] : ""),
        beforeExists: (meta.Has("before_exists") && meta["before_exists"] = "1"),
        beforeText: Base64DecodeUtf8(meta.Has("before_text_b64") ? meta["before_text_b64"] : ""),
        afterCategory: Base64DecodeUtf8(meta.Has("after_category_b64") ? meta["after_category_b64"] : ""),
        afterTitle: Base64DecodeUtf8(meta.Has("after_title_b64") ? meta["after_title_b64"] : ""),
        afterExists: (meta.Has("after_exists") && meta["after_exists"] = "1"),
        afterText: Base64DecodeUtf8(meta.Has("after_text_b64") ? meta["after_text_b64"] : "")
    }
    return true
}

; Returns or computes format change backup display.
FormatChangeBackupDisplay(change) {
    typeKey := "change_" StrLower(change.type)
    typeLabel := T(typeKey)
    if (typeLabel = typeKey)
        typeLabel := T("change_unknown")

    category := change.afterExists ? change.afterCategory : change.beforeCategory
    title := change.afterExists ? change.afterTitle : change.beforeTitle
    if (category = "")
        category := "?"
    if (title = "")
        title := "?"
    return typeLabel ": " category " / " title
}

; Creates or builds make entry change.
MakeEntryChange(type, beforeCategory, beforeTitle, beforeExists, beforeText, afterCategory, afterTitle, afterExists, afterText) {
    return {
        type: StrLower(type),
        beforeCategory: beforeCategory,
        beforeTitle: beforeTitle,
        beforeExists: !!beforeExists,
        beforeText: beforeText,
        afterCategory: afterCategory,
        afterTitle: afterTitle,
        afterExists: !!afterExists,
        afterText: afterText
    }
}

; Handles base 64 encode utf 8.
Base64EncodeUtf8(text) {
    if (text = "")
        return ""

    byteLen := StrPut(text, "UTF-8") - 1
    if (byteLen < 1)
        return ""

    inBuf := Buffer(byteLen, 0)
    StrPut(text, inBuf, "UTF-8")

    needed := 0
    DllCall(
        "Crypt32\CryptBinaryToStringW",
        "Ptr", inBuf,
        "UInt", byteLen,
        "UInt", 0x40000001, ; BASE64 + NOCRLF
        "Ptr", 0,
        "UInt*", &needed
    )
    outBuf := Buffer(needed * 2, 0)
    if !DllCall(
        "Crypt32\CryptBinaryToStringW",
        "Ptr", inBuf,
        "UInt", byteLen,
        "UInt", 0x40000001,
        "Ptr", outBuf,
        "UInt*", &needed
    )
        return ""
    return StrGet(outBuf, "UTF-16")
}

; Handles base 64 decode utf 8.
Base64DecodeUtf8(b64) {
    if (b64 = "")
        return ""

    byteLen := 0
    if !DllCall(
        "Crypt32\CryptStringToBinaryW",
        "Str", b64,
        "UInt", 0,
        "UInt", 0x1, ; BASE64
        "Ptr", 0,
        "UInt*", &byteLen,
        "Ptr", 0,
        "Ptr", 0
    )
        return ""

    outBuf := Buffer(byteLen, 0)
    if !DllCall(
        "Crypt32\CryptStringToBinaryW",
        "Str", b64,
        "UInt", 0,
        "UInt", 0x1,
        "Ptr", outBuf,
        "UInt*", &byteLen,
        "Ptr", 0,
        "Ptr", 0
    )
        return ""

    return StrGet(outBuf, byteLen, "UTF-8")
}

; Handles join lines.
JoinLines(arr) {
    out := ""
    for i, l in arr {
        if (i > 1)
            out .= "`r`n"
        out .= l
    }
    out := RegExReplace(out, "(?:\R)+\z", "")
    return out
}

; Opens or shows show transient tool tip.
