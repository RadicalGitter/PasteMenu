; ---------------------------------------------------------------------
; Usage stats core:
; - Recent decayed usage scores for paste entries
; - Last-used tracking for hotwheel center actions
; - Persistence separate from pastemenu.txt
; ---------------------------------------------------------------------

UsageStatsInitState() {
    global _UsageStatsState
    _UsageStatsState := {
        loaded: false,
        filePath: "",
        entries: Map(),
        lastCategory: "",
        lastTitle: "",
        lastUsed: ""
    }
}

UsageStatsEnsureState() {
    global _UsageStatsState
    if !IsObject(_UsageStatsState)
        UsageStatsInitState()
}

UsageStatsGetFilePath() {
    global DataRootDir, UsageStatsFile
    if (UsageStatsFile = "")
        UsageStatsFile := DataRootDir "\usage.ini"
    return UsageStatsFile
}

UsageStatsMakeKey(category, title) {
    return category Chr(31) title
}

UsageStatsHalfLifeSeconds() {
    return 30 * 60
}

UsageStatsRecordSuccessfulPaste(category, title, now := "") {
    if (category = "" || title = "")
        return false

    if (now = "")
        now := A_Now

    if !UsageStatsLoad()
        return false

    global _UsageStatsState
    key := UsageStatsMakeKey(category, title)
    if _UsageStatsState.entries.Has(key) {
        entry := _UsageStatsState.entries[key]
        score := UsageStatsEffectiveScore(entry, now)
    } else {
        entry := {
            category: category,
            title: title,
            score: 0.0,
            lastUsed: now
        }
        score := 0.0
    }

    entry.category := category
    entry.title := title
    entry.score := score + 1.0
    entry.lastUsed := now
    _UsageStatsState.entries[key] := entry
    _UsageStatsState.lastCategory := category
    _UsageStatsState.lastTitle := title
    _UsageStatsState.lastUsed := now

    return UsageStatsSave()
}

UsageStatsLoad(force := false) {
    global _UsageStatsState
    UsageStatsEnsureState()
    path := UsageStatsGetFilePath()
    if (_UsageStatsState.loaded && _UsageStatsState.filePath = path && !force)
        return true

    UsageStatsInitState()
    UsageStatsEnsureState()
    _UsageStatsState.loaded := true
    _UsageStatsState.filePath := path

    if !FileExist(path)
        return true

    text := ReadTextFile(path, "UTF-8")
    if (text = "")
        return true

    sections := UsageStatsParseIniText(text)
    if sections.Has("last") {
        last := sections["last"]
        _UsageStatsState.lastCategory := Base64DecodeUtf8(UsageStatsMapGet(last, "category_b64", ""))
        _UsageStatsState.lastTitle := Base64DecodeUtf8(UsageStatsMapGet(last, "title_b64", ""))
        _UsageStatsState.lastUsed := UsageStatsMapGet(last, "timestamp", "")
    }

    for sectionName, values in sections {
        if !RegExMatch(sectionName, "^entry_\d+$")
            continue

        category := Base64DecodeUtf8(UsageStatsMapGet(values, "category_b64", ""))
        title := Base64DecodeUtf8(UsageStatsMapGet(values, "title_b64", ""))
        if (category = "" || title = "")
            continue

        scoreRaw := UsageStatsMapGet(values, "score", "0")
        lastUsed := UsageStatsMapGet(values, "last_used", "")
        key := UsageStatsMakeKey(category, title)
        _UsageStatsState.entries[key] := {
            category: category,
            title: title,
            score: scoreRaw + 0.0,
            lastUsed: lastUsed
        }
    }

    return true
}

UsageStatsSave() {
    global _UsageStatsState
    UsageStatsEnsureState()

    path := UsageStatsGetFilePath()
    _UsageStatsState.filePath := path
    out := "[meta]`r`n"
    out .= "version=1`r`n"
    out .= "half_life_minutes=30`r`n`r`n"

    out .= "[last]`r`n"
    out .= "category_b64=" Base64EncodeUtf8(_UsageStatsState.lastCategory) "`r`n"
    out .= "title_b64=" Base64EncodeUtf8(_UsageStatsState.lastTitle) "`r`n"
    out .= "timestamp=" _UsageStatsState.lastUsed "`r`n`r`n"

    index := 0
    for _, entry in _UsageStatsState.entries {
        if (entry.category = "" || entry.title = "")
            continue
        index += 1
        out .= "[entry_" Format("{:03}", index) "]`r`n"
        out .= "category_b64=" Base64EncodeUtf8(entry.category) "`r`n"
        out .= "title_b64=" Base64EncodeUtf8(entry.title) "`r`n"
        out .= "score=" Format("{:.8f}", entry.score + 0.0) "`r`n"
        out .= "last_used=" entry.lastUsed "`r`n`r`n"
    }

    return WriteTextFileAtomic(path, out, "UTF-8")
}

UsageStatsParseIniText(text) {
    sections := Map()
    currentSection := ""
    currentValues := Map()

    commit := (*) => (
        currentSection != ""
            ? sections[currentSection] := currentValues
            : ""
    )

    lines := StrSplit(StrReplace(text, "`r`n", "`n"), "`n")
    for _, rawLine in lines {
        line := Trim(rawLine, " `t`r")
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        if RegExMatch(line, "^\[([^\]]+)\]$", &sectionMatch) {
            commit()
            currentSection := Trim(sectionMatch[1])
            currentValues := Map()
            continue
        }

        eqPos := InStr(line, "=")
        if (currentSection = "" || eqPos < 1)
            continue

        key := Trim(SubStr(line, 1, eqPos - 1))
        value := Trim(SubStr(line, eqPos + 1), " `t`r")
        currentValues[key] := value
    }

    commit()
    return sections
}

UsageStatsMapGet(mapObj, key, defaultValue := "") {
    if IsObject(mapObj) && mapObj.Has(key)
        return mapObj[key]
    return defaultValue
}

UsageStatsEffectiveScore(entry, now := "") {
    if !IsObject(entry)
        return 0.0
    if (now = "")
        now := A_Now

    score := entry.score + 0.0
    if (score <= 0)
        return 0.0
    if (entry.lastUsed = "")
        return score

    ageSeconds := 0
    try ageSeconds := DateDiff(now, entry.lastUsed, "Seconds")
    catch {
        return score
    }
    if (ageSeconds < 0)
        ageSeconds := 0

    return score * (0.5 ** (ageSeconds / UsageStatsHalfLifeSeconds()))
}

UsageStatsEntryExists(category, title) {
    global _EntriesByCategory
    if (category = "" || title = "")
        return false
    if !_EntriesByCategory.Has(category)
        return false
    return _EntriesByCategory[category].Has(title)
}

UsageStatsGetLastUsed(&category, &title, requireExisting := true) {
    category := ""
    title := ""
    if !UsageStatsLoad()
        return false

    global _UsageStatsState
    category := _UsageStatsState.lastCategory
    title := _UsageStatsState.lastTitle
    if (category = "" || title = "")
        return false
    if requireExisting && !UsageStatsEntryExists(category, title) {
        category := ""
        title := ""
        return false
    }
    return true
}

UsageStatsGetMostUsed(&category, &title, excludeCategory := "", excludeTitle := "", requireExisting := true, now := "") {
    category := ""
    title := ""

    ranked := UsageStatsGetRankedEntries(0, now, requireExisting)
    for _, entry in ranked {
        if (excludeCategory != "" || excludeTitle != "") {
            if (entry.category = excludeCategory && entry.title = excludeTitle)
                continue
        }
        category := entry.category
        title := entry.title
        return true
    }
    return false
}

UsageStatsGetLastAndMostUsed(&lastEntry, &mostEntry, now := "") {
    lastEntry := 0
    mostEntry := 0

    excludeCategory := ""
    excludeTitle := ""
    if UsageStatsGetLastUsed(&lastCategory, &lastTitle, true) {
        lastEntry := {category: lastCategory, title: lastTitle}
        excludeCategory := lastCategory
        excludeTitle := lastTitle
    }

    if UsageStatsGetMostUsed(&mostCategory, &mostTitle, excludeCategory, excludeTitle, true, now)
        mostEntry := {category: mostCategory, title: mostTitle}

    return IsObject(lastEntry) || IsObject(mostEntry)
}

UsageStatsGetRankedEntries(limit := 0, now := "", requireExisting := true) {
    if (now = "")
        now := A_Now
    UsageStatsLoad()

    global _UsageStatsState
    ranked := []
    for _, entry in _UsageStatsState.entries {
        if requireExisting && !UsageStatsEntryExists(entry.category, entry.title)
            continue
        effective := UsageStatsEffectiveScore(entry, now)
        if (effective <= 0)
            continue
        ranked.Push({
            category: entry.category,
            title: entry.title,
            score: effective,
            lastUsed: entry.lastUsed
        })
    }

    UsageStatsSortRankedEntries(ranked)
    if (limit > 0 && ranked.Length > limit) {
        trimmed := []
        Loop limit
            trimmed.Push(ranked[A_Index])
        return trimmed
    }
    return ranked
}

UsageStatsSortRankedEntries(entries) {
    count := entries.Length
    if (count < 2)
        return

    Loop count - 1 {
        i := A_Index
        j := i + 1
        while (j <= count) {
            if (entries[j].score > entries[i].score) {
                tmp := entries[i]
                entries[i] := entries[j]
                entries[j] := tmp
            }
            j += 1
        }
    }
}
