; ---------------------------------------------------------------------
; LLM Calls module:
; - Separate prompt library for LLM call presets
; - Anthropic Messages API requests
; - Confirmation/custom call windows and response logging
; ---------------------------------------------------------------------

LLMCallsInitDefaults() {
    global _LLMState

    if IsObject(_LLMState)
        return

    _LLMState := {
        provider: "anthropic",
        model: "claude-sonnet-4-20250514",
        maxTokens: 1024,
        timeoutSeconds: 60,
        examplePreface: LLMCallsDefaultExamplePreface(),
        confirmUntilTick: 0,
        promptEditor: 0,
        settingsWindow: 0,
        responseWindows: Map(),
        nextRequestId: 0
    }
}

LLMCallsLoadFromSettings() {
    global SettingsFile, _LLMState

    LLMCallsInitDefaults()
    if !FileExist(SettingsFile)
        return

    provider := StrLower(Trim(IniRead(SettingsFile, "llm", "provider", _LLMState.provider)))
    if (provider != "anthropic")
        provider := "anthropic"
    _LLMState.provider := provider

    model := Trim(IniRead(SettingsFile, "llm", "model", _LLMState.model))
    if (model != "")
        _LLMState.model := model

    maxRaw := Trim(IniRead(SettingsFile, "llm", "max_tokens", _LLMState.maxTokens ""))
    _LLMState.maxTokens := LLMCallsNormalizeMaxTokens(maxRaw)

    timeoutRaw := Trim(IniRead(SettingsFile, "llm", "timeout_seconds", _LLMState.timeoutSeconds ""))
    _LLMState.timeoutSeconds := LLMCallsNormalizeTimeoutSeconds(timeoutRaw)

    prefaceRaw := IniRead(SettingsFile, "llm", "example_preface", "__PASTEMENU_MISSING__")
    if (prefaceRaw != "__PASTEMENU_MISSING__")
        _LLMState.examplePreface := LLMCallsDecodeSettingsText(prefaceRaw)
}

LLMCallsSaveToSettings() {
    global SettingsFile, _LLMState

    LLMCallsInitDefaults()
    EnsureParentDirectory(SettingsFile)
    IniWrite(_LLMState.provider, SettingsFile, "llm", "provider")
    IniWrite(_LLMState.model, SettingsFile, "llm", "model")
    IniWrite(_LLMState.maxTokens "", SettingsFile, "llm", "max_tokens")
    IniWrite(_LLMState.timeoutSeconds "", SettingsFile, "llm", "timeout_seconds")
    IniWrite(LLMCallsEncodeSettingsText(_LLMState.examplePreface), SettingsFile, "llm", "example_preface")
}

LLMCallsDefaultExamplePreface() {
    return "Here are examples of the way I phrase my responses. Try to emulate my style of response, both in structure and language, and use similar pedagogical techniques as I do. Focus your response on finding structural improvement vectors rather than minutiae."
}

LLMCallsEncodeSettingsText(text) {
    return JsonEscape(text)
}

LLMCallsDecodeSettingsText(text) {
    return JsonUnescape(text)
}

LLMCallsNormalizeMaxTokens(value) {
    try n := value + 0
    catch {
        n := 1024
    }
    if (n < 128)
        n := 128
    if (n > 8192)
        n := 8192
    return Round(n)
}

LLMCallsResponseTokenBudget() {
    global _LLMState
    LLMCallsInitDefaults()
    return Max(1, _LLMState.maxTokens - 5)
}

LLMCallsResponseBudgetInstruction() {
    return "Your full response must fit within " LLMCallsResponseTokenBudget() " tokens."
}

LLMCallsNormalizeTimeoutSeconds(value) {
    try n := value + 0
    catch {
        n := 60
    }
    if (n < 5)
        n := 5
    if (n > 300)
        n := 300
    return Round(n)
}

LLMCallsEnsurePromptFile() {
    global LLMPromptFile

    EnsureParentDirectory(LLMPromptFile)
    if FileExist(LLMPromptFile)
        return

    tpl := "
(
{General}:
[Summarize]:
Summarize the highlighted text clearly and concisely.

[Improve writing]:
Rewrite the highlighted text for clarity, flow, and precision while preserving the original meaning.

[Explain]:
Explain the highlighted text in plain language.
)"
    FileAppend(tpl, LLMPromptFile, "UTF-8")
}

LLMCallsLoadPromptData() {
    global LLMPromptFile
    global _LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory

    LLMCallsEnsurePromptFile()

    categories := []
    entriesByCategory := Map()
    entryOrderByCategory := Map()

    ok := LoadSnippetsFromFile(LLMPromptFile, "UTF-8", "General", &categories, &entriesByCategory, &entryOrderByCategory)
    if !ok {
        categories := ["General"]
        entriesByCategory := Map("General", Map())
        entryOrderByCategory := Map("General", [])
    }

    _LLMCategories := categories
    _LLMEntriesByCategory := entriesByCategory
    _LLMEntryOrderByCategory := entryOrderByCategory
    return true
}

LLMCallsSavePromptData() {
    global LLMPromptFile
    global _LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory

    out := BuildSnippetsText(_LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory)
    return WriteTextFileAtomic(LLMPromptFile, out, "UTF-8")
}

LLMExampleLinksLoad() {
    global LLMExampleLinkFile, _LLMExampleLinks

    _LLMExampleLinks := Map()
    EnsureParentDirectory(LLMExampleLinkFile)
    if !FileExist(LLMExampleLinkFile)
        return true

    text := ReadTextFile(LLMExampleLinkFile, "UTF-8")
    Loop Parse text, "`n", "`r" {
        line := A_LoopField
        if (Trim(line) = "")
            continue
        parts := StrSplit(line, "`t")
        if (parts.Length < 4)
            continue
        llmCategory := parts[1]
        llmTitle := parts[2]
        snippetCategory := parts[3]
        snippetTitle := parts[4]
        if (llmCategory = "" || llmTitle = "" || snippetCategory = "" || snippetTitle = "")
            continue
        LLMExampleLinkSet(llmCategory, llmTitle, snippetCategory, snippetTitle, true, false)
    }
    return true
}

LLMExampleLinksSave() {
    global LLMExampleLinkFile, _LLMExampleLinks

    out := ""
    for llmKey, links in _LLMExampleLinks {
        llmParts := StrSplit(llmKey, "`t", , 2)
        if (llmParts.Length < 2)
            continue
        for snippetKey, _ in links {
            snippetParts := StrSplit(snippetKey, "`t", , 2)
            if (snippetParts.Length < 2)
                continue
            out .= llmParts[1] "`t" llmParts[2] "`t" snippetParts[1] "`t" snippetParts[2] "`r`n"
        }
    }
    return WriteTextFileAtomic(LLMExampleLinkFile, out, "UTF-8")
}

LLMExampleLinkKey(category, title) {
    return category "`t" title
}

LLMExampleLinkSet(llmCategory, llmTitle, snippetCategory, snippetTitle, included := true, persist := true) {
    global _LLMExampleLinks
    if (llmCategory = "" || llmTitle = "" || snippetCategory = "" || snippetTitle = "")
        return

    llmKey := LLMExampleLinkKey(llmCategory, llmTitle)
    snippetKey := LLMExampleLinkKey(snippetCategory, snippetTitle)
    if !_LLMExampleLinks.Has(llmKey)
        _LLMExampleLinks[llmKey] := Map()
    if included
        _LLMExampleLinks[llmKey][snippetKey] := true
    else if _LLMExampleLinks[llmKey].Has(snippetKey)
        _LLMExampleLinks[llmKey].Delete(snippetKey)
    if _LLMExampleLinks.Has(llmKey) && _LLMExampleLinks[llmKey].Count = 0
        _LLMExampleLinks.Delete(llmKey)

    if persist
        LLMExampleLinksSave()
}

LLMExampleLinksForCall(llmCategory, llmTitle) {
    global _LLMExampleLinks
    llmKey := LLMExampleLinkKey(llmCategory, llmTitle)
    if _LLMExampleLinks.Has(llmKey)
        return _LLMExampleLinks[llmKey]
    return Map()
}

LLMExampleRenameSnippet(oldCategory, oldTitle, newCategory, newTitle, persist := true) {
    global _LLMExampleLinks
    oldKey := LLMExampleLinkKey(oldCategory, oldTitle)
    newKey := LLMExampleLinkKey(newCategory, newTitle)
    changed := false

    for llmKey, links in _LLMExampleLinks {
        if links.Has(oldKey) {
            links.Delete(oldKey)
            if (newCategory != "" && newTitle != "")
                links[newKey] := true
            changed := true
        }
    }
    LLMExamplePruneEmptyLinks()
    if changed && persist
        LLMExampleLinksSave()
}

LLMExampleRemoveSnippet(category, title, persist := true) {
    LLMExampleRenameSnippet(category, title, "", "", persist)
}

LLMExampleRenameSnippetCategory(oldCategory, newCategory) {
    global _LLMExampleLinks
    changed := false
    for llmKey, links in _LLMExampleLinks {
        replacements := []
        for snippetKey, _ in links {
            parts := StrSplit(snippetKey, "`t", , 2)
            if (parts.Length >= 2 && parts[1] = oldCategory)
                replacements.Push({oldKey: snippetKey, newKey: LLMExampleLinkKey(newCategory, parts[2])})
        }
        for _, item in replacements {
            links.Delete(item.oldKey)
            links[item.newKey] := true
            changed := true
        }
    }
    if changed
        LLMExampleLinksSave()
}

LLMExampleRemoveSnippetCategory(category) {
    global _LLMExampleLinks
    changed := false
    prefix := category "`t"
    for llmKey, links in _LLMExampleLinks {
        keys := []
        for snippetKey, _ in links {
            if (SubStr(snippetKey, 1, StrLen(prefix)) = prefix)
                keys.Push(snippetKey)
        }
        for _, key in keys {
            links.Delete(key)
            changed := true
        }
    }
    LLMExamplePruneEmptyLinks()
    if changed
        LLMExampleLinksSave()
}

LLMExampleRenameLLMEntry(oldCategory, oldTitle, newCategory, newTitle, persist := true) {
    global _LLMExampleLinks
    oldKey := LLMExampleLinkKey(oldCategory, oldTitle)
    if !_LLMExampleLinks.Has(oldKey)
        return
    links := _LLMExampleLinks[oldKey]
    _LLMExampleLinks.Delete(oldKey)
    if (newCategory != "" && newTitle != "") {
        newKey := LLMExampleLinkKey(newCategory, newTitle)
        if !_LLMExampleLinks.Has(newKey) {
            _LLMExampleLinks[newKey] := links
        } else {
            for snippetKey, _ in links
                _LLMExampleLinks[newKey][snippetKey] := true
        }
    }
    if persist
        LLMExampleLinksSave()
}

LLMExampleRemoveLLMEntry(category, title, persist := true) {
    LLMExampleRenameLLMEntry(category, title, "", "", persist)
}

LLMExampleRenameLLMCategory(oldCategory, newCategory) {
    global _LLMExampleLinks
    changed := false
    replacements := []
    for llmKey, links in _LLMExampleLinks {
        parts := StrSplit(llmKey, "`t", , 2)
        if (parts.Length >= 2 && parts[1] = oldCategory)
            replacements.Push({oldKey: llmKey, newKey: LLMExampleLinkKey(newCategory, parts[2]), links: links})
    }
    for _, item in replacements {
        _LLMExampleLinks.Delete(item.oldKey)
        _LLMExampleLinks[item.newKey] := item.links
        changed := true
    }
    if changed
        LLMExampleLinksSave()
}

LLMExampleRemoveLLMCategory(category) {
    global _LLMExampleLinks
    prefix := category "`t"
    changed := false
    keys := []
    for llmKey, _ in _LLMExampleLinks {
        if (SubStr(llmKey, 1, StrLen(prefix)) = prefix)
            keys.Push(llmKey)
    }
    for _, key in keys {
        _LLMExampleLinks.Delete(key)
        changed := true
    }
    if changed
        LLMExampleLinksSave()
}

LLMExamplePruneEmptyLinks() {
    global _LLMExampleLinks
    keys := []
    for llmKey, links in _LLMExampleLinks {
        if links.Count = 0
            keys.Push(llmKey)
    }
    for _, key in keys
        _LLMExampleLinks.Delete(key)
}

LLMExamplesBuildPromptSection(llmCategory, llmTitle) {
    global _EntriesByCategory, _LLMState

    LLMCallsInitDefaults()

    links := LLMExampleLinksForCall(llmCategory, llmTitle)
    if links.Count = 0
        return ""

    lines := []
    for key, _ in links {
        parts := StrSplit(key, "`t", , 2)
        if (parts.Length < 2)
            continue
        category := parts[1]
        title := parts[2]
        if !_EntriesByCategory.Has(category)
            continue
        if !_EntriesByCategory[category].Has(title)
            continue
        lines.Push("[" category " / " title "]`n" _EntriesByCategory[category][title])
    }

    if (lines.Length = 0)
        return ""

    out := Trim(_LLMState.examplePreface)
    for _, item in lines {
        if (out != "")
            out .= "`n`n" item
        else
            out := item
    }
    return out
}

AddLLMCallsRootSection(mainMenu) {
    mainMenu.Add(T("llm_calls"), LLMCallsBuildMenu())
}

LLMCallsBuildMenu() {
    global _LLMCategories, _LLMEntryOrderByCategory

    LLMCallsLoadPromptData()
    hasSelection := LLMCallsPendingTargetHasSelection()

    menuObj := Menu()
    menuObj.Add(T("llm_custom"), LLMCallsCustomMenuAction)
    if !hasSelection
        menuObj.Disable(T("llm_custom"))
    menuObj.Add()

    for _, category in _LLMCategories {
        sub := Menu()
        order := _LLMEntryOrderByCategory[category]
        if (order.Length = 0) {
            sub.Add(T("menu_empty_category"), NoOp)
        } else {
            for _, title in order {
                sub.Add(title, LLMCallsPromptMenuAction.Bind(category, title))
                if !hasSelection
                    sub.Disable(title)
            }
        }
        menuObj.Add(category, sub)
    }

    menuObj.Add()
    menuObj.Add(T("llm_edit_calls"), OpenLLMCallsEditor)
    menuObj.Add(T("llm_settings"), OpenLLMSettingsWindow)
    if !hasSelection
        menuObj.Disable(T("llm_settings"))
    return menuObj
}

LLMCallsPromptMenuAction(category, title, *) {
    global _PendingPasteTarget, _LLMEntriesByCategory

    target := _PendingPasteTarget
    _PendingPasteTarget := 0

    selectedText := ""
    if !LLMCallsResolveUserPayload(target, &selectedText) {
        ShowTransientToolTip(T("llm_no_selection"))
        return
    }

    if !_LLMEntriesByCategory.Has(category) || !_LLMEntriesByCategory[category].Has(title) {
        SoundBeep 1500
        return
    }

    systemPrompt := _LLMEntriesByCategory[category][title]
    if LLMCallsShouldSkipConfirm() {
        LLMCallsStartRequest(category, title, systemPrompt, selectedText, target)
        return
    }

    OpenLLMConfirmWindow(category, title, systemPrompt, selectedText, target)
}

LLMCallsCustomMenuAction(*) {
    global _PendingPasteTarget

    target := _PendingPasteTarget
    _PendingPasteTarget := 0

    selectedText := ""
    if !LLMCallsResolveUserPayload(target, &selectedText) {
        ShowTransientToolTip(T("llm_no_selection"))
        return
    }
    OpenLLMCustomWindow(selectedText, target)
}

; Resolve the user-message payload.
; PDF contexts prefer highlighted text first because browser PDF viewers often
; block or degrade full-document extraction.
LLMCallsResolveUserPayload(target, &payload) {
    payload := ""
    if IsObject(target) && target.HasOwnProp("docContext") && IsObject(target.docContext) {
        kind := target.docContext.HasOwnProp("kind") ? target.docContext.kind : ""
        if (kind = "pdf") {
            selectedText := ""
            if LLMCallsGetTargetSelectedText(target, &selectedText) {
                if (Trim(selectedText) != "" && !LLMDocLooksLikePdfUrl(selectedText)) {
                    payload := selectedText
                    return true
                }
            }
        }

        docText := LLMDocResolvePayload(target.docContext)
        if (Trim(docText) != "") {
            payload := docText
            return true
        }
        ; Doc process detected but extraction returned nothing (COM unavailable or empty doc).
        ; Skip the slow clipboard dance — it would just hang then fail anyway for doc windows.
        if (kind = "word" || kind = "pdf")
            return false
    }
    return LLMCallsGetTargetSelectedText(target, &payload)
}

LLMCallsPendingTargetHasSelection() {
    global _PendingPasteTarget
    if !IsObject(_PendingPasteTarget)
        return false
    if _PendingPasteTarget.HasOwnProp("docContext") && IsObject(_PendingPasteTarget.docContext)
        return true
    if _PendingPasteTarget.HasOwnProp("llmSelectionChecked")
        return _PendingPasteTarget.llmHasSelection

    if LLMCallsTryGetCheapSelectionState(_PendingPasteTarget, &hasSelection)
        return hasSelection

    ; For browsers/Electron/custom controls, detecting selection requires copying.
    ; Keep the menu fast and validate selection only when an LLM item is clicked.
    return true
}

LLMCallsTryGetCheapSelectionState(target, &hasSelection) {
    hasSelection := false
    if !IsObject(target)
        return true
    if !target.HasOwnProp("ctrlHwnd") || !target.ctrlHwnd
        return false

    className := ""
    try className := WinGetClass("ahk_id " target.ctrlHwnd)
    if !RegExMatch(className, "i)^(Edit|RICHEDIT\d*\w*|RichEdit\d*\w*|WindowsForms10\.EDIT.*)$")
        return false

    hasSelection := HasTextSelectionInControl(target.ctrlHwnd, className)
    return true
}

LLMCallsGetTargetSelectedText(target, &selectedText) {
    selectedText := ""
    if !IsObject(target)
        return false
    if target.HasOwnProp("llmSelectionChecked") {
        if target.llmHasSelection
            selectedText := target.llmSelectedText
        return target.llmHasSelection
    }

    ok := LLMCallsCaptureSelectedText(target, &selectedText)
    target.llmSelectionChecked := true
    target.llmHasSelection := ok
    target.llmSelectedText := ok ? selectedText : ""
    return ok
}

LLMCallsCaptureSelectedText(target, &selectedText) {
    selectedText := ""
    if !FocusPasteTarget(target)
        return false

    clipSaved := 0
    hasSavedClip := false
    try {
        clipSaved := ClipboardAll()
        hasSavedClip := true
    }

    sentinel := "__PASTEMENU_LLM_COPY_SENTINEL__" A_TickCount "__"
    if !LLMCallsSetClipboardSentinel(sentinel) {
        if hasSavedClip {
            try A_Clipboard := clipSaved
        }
        return false
    }

    useControlSend := false
    if IsObject(target) && target.HasOwnProp("ctrlName") && (target.ctrlName != "") {
        ctrlClass := ""
        if target.HasOwnProp("ctrlHwnd") && target.ctrlHwnd {
            try ctrlClass := WinGetClass("ahk_id " target.ctrlHwnd)
            useControlSend := IsLikelyTextControlClass(ctrlClass)
        }
    }

    copied := LLMCallsCopySelectionAttempt(target, useControlSend, sentinel, &selectedText)
    if !copied && !useControlSend {
        Sleep 80
        if LLMCallsSetClipboardSentinel(sentinel)
            copied := LLMCallsCopySelectionAttempt(target, false, sentinel, &selectedText)
    }

    if hasSavedClip {
        try A_Clipboard := clipSaved
    }

    if !copied || Trim(selectedText) = ""
        return false
    if LLMCallsLooksLikeSensitiveClipboardLeak(selectedText) {
        selectedText := ""
        return false
    }
    return true
}

LLMCallsSetClipboardSentinel(sentinel) {
    try A_Clipboard := sentinel
    catch {
        return false
    }

    deadline := A_TickCount + 250
    while (A_TickCount < deadline) {
        if (A_Clipboard = sentinel)
            return true
        Sleep 10
    }
    return false
}

LLMCallsCopySelectionAttempt(target, useControlSend, sentinel, &selectedText) {
    selectedText := ""
    if useControlSend {
        try ControlSend("^c", target.ctrlName, "ahk_id " target.win)
        catch
            Send "^c"
    } else {
        Send "^c"
    }

    deadline := A_TickCount + 1000
    while (A_TickCount < deadline) {
        currentClip := A_Clipboard
        if (currentClip != "" && currentClip != sentinel) {
            selectedText := currentClip
            return true
        }
        Sleep 20
    }
    return false
}

LLMCallsLooksLikeSensitiveClipboardLeak(text) {
    trimmed := Trim(text)
    if RegExMatch(trimmed, "im)^\s*api_key\s*=")
        return true
    if RegExMatch(trimmed, "i)sk-ant-api[0-9a-z_-]+")
        return true
    apiKey := LLMCallsReadApiKey()
    if (apiKey != "" && InStr(trimmed, apiKey))
        return true
    return false
}

LLMCallsShouldSkipConfirm() {
    global _LLMState
    LLMCallsInitDefaults()
    return (_LLMState.confirmUntilTick > A_TickCount)
}

OpenLLMConfirmWindow(category, title, systemPrompt, selectedText, pasteTarget := 0) {
    global _LLMState

    confirmGui := Gui("+AlwaysOnTop +Resize +MinSize520x190", T("llm_calls") " - " title)
    confirmGui.SetFont("s10", "Segoe UI")

    confirmGui.AddText("x12 y12 w496", category " / " title)
    chkSkip := confirmGui.AddCheckBox("x12 y44 w300 h24", T("llm_dont_ask_hour"))

    costText := confirmGui.AddText("x12 y76 w496 h20", "")

    nagVisible := LLMPricingShouldNag()
    nagText := 0
    btnUpdateNow := 0
    btnRowY := 108
    if nagVisible {
        nagText := confirmGui.AddText("x12 y104 w380 h22 +0x200", T("llm_pricing_stale_notice"))
        btnUpdateNow := confirmGui.AddButton("x396 y100 w112 h26", T("llm_pricing_update_now"))
        btnRowY := 140
    }

    btnSend := confirmGui.AddButton("x236 y" btnRowY " w82 h30", T("llm_send"))
    btnCancel := confirmGui.AddButton("x328 y" btnRowY " w82 h30", T("hotkey_dialog_cancel"))
    btnShow := confirmGui.AddButton("x420 y" btnRowY " w88 h30", T("llm_show_contents"))

    ; Content controls live below the button row; hidden until "Show contents" is clicked.
    contentStartY  := btnRowY + 44
    systemEditY    := contentStartY + 20   ; system-prompt label(20) + gap
    selectedLabelY := contentStartY + 148  ; + sysEdit(120) + gap(8) + label(20)
    textEditY      := contentStartY + 168  ; + selectedLabel(20)
    confirmGui.AddText("x12 y" contentStartY " w496 vContentsLabel Hidden", T("llm_system_prompt"))
    systemEdit := confirmGui.AddEdit("x12 y" systemEditY " w496 h120 Multi WantTab Hidden")
    systemEdit.Value := systemPrompt
    confirmGui.AddText("x12 y" selectedLabelY " w496 vSelectedLabel Hidden", T("llm_selected_text"))
    textEdit := confirmGui.AddEdit("x12 y" textEditY " w496 h150 Multi WantTab Hidden")
    textEdit.Value := selectedText

    state := {
        gui: confirmGui,
        category: category,
        title: title,
        systemEdit: systemEdit,
        textEdit: textEdit,
        pasteTarget: pasteTarget,
        chkSkip: chkSkip,
        btnSend: btnSend,
        btnCancel: btnCancel,
        btnShow: btnShow,
        costText: costText,
        nagText: nagText,
        btnUpdateNow: btnUpdateNow,
        nagVisible: nagVisible,
        userUpdatedPricing: false,
        btnRowY: btnRowY,
        expanded: false
    }

    btnSend.OnEvent("Click", LLMConfirmSend.Bind(state))
    btnCancel.OnEvent("Click", LLMConfirmClose.Bind(state))
    btnShow.OnEvent("Click", LLMConfirmToggleContents.Bind(state))
    if IsObject(btnUpdateNow)
        btnUpdateNow.OnEvent("Click", LLMConfirmUpdatePricing.Bind(state))
    confirmGui.OnEvent("Close", LLMConfirmClose.Bind(state))
    confirmGui.OnEvent("Escape", LLMConfirmClose.Bind(state))

    LLMConfirmRefreshCost(state)
    confirmGui.Show("w520 h" (btnRowY + 56))
}

LLMConfirmRefreshCost(state) {
    global _LLMState
    systemPrompt := state.systemEdit.Value
    selectedText := state.textEdit.Value
    finalSystemPrompt := LLMCallsBuildFinalSystemPrompt(state.category, state.title, systemPrompt)
    estTokens := LLMPricingEstimateInputTokens(finalSystemPrompt) + LLMPricingEstimateInputTokens(selectedText)
    costLine := LLMPricingFormatCostLine(_LLMState.model, estTokens, _LLMState.maxTokens)
    if (costLine = "")
        costLine := T("llm_pricing_unknown") " — " _LLMState.model
    state.costText.Text := T("llm_estimated_cost") ": " costLine
}

LLMConfirmUpdatePricing(state, *) {
    ShowTransientToolTip(T("llm_pricing_updating"))
    errMsg := ""
    if !LLMPricingUpdateAll(&errMsg) {
        MsgBox T("llm_pricing_update_failed") ".`r`n`r`n" errMsg, T("llm_response_title")
        return
    }
    state.userUpdatedPricing := true
    if IsObject(state.nagText)
        try state.nagText.Visible := false
    if IsObject(state.btnUpdateNow)
        try state.btnUpdateNow.Visible := false
    LLMConfirmRefreshCost(state)
    ShowTransientToolTip(T("llm_pricing_update_ok"))
}

LLMConfirmToggleContents(state, *) {
    state.expanded := !state.expanded
    visible := state.expanded
    state.systemEdit.Visible := visible
    state.textEdit.Visible := visible
    try state.gui["ContentsLabel"].Visible := visible
    try state.gui["SelectedLabel"].Visible := visible
    state.btnShow.Text := visible ? T("llm_hide_contents") : T("llm_show_contents")

    if visible {
        ; Measure how far the window can grow before hitting the screen edge.
        winX := 0
        winY := 0
        WinGetPos(&winX, &winY, , , "ahk_id " state.gui.Hwnd)

        ; Find the work-area bottom of whichever monitor the window is on.
        workBottom := A_ScreenHeight
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &mLeft, &mTop, &mRight, &mBottom)
            if (winX + 260 >= mLeft && winX + 260 < mRight && winY >= mTop && winY < mBottom) {
                workBottom := mBottom
                break
            }
        }

        ; Content sits below the button row:
        ;   btnRow(30) + gap(14) = contentStart
        ;   label(20) + sysEdit(120) + gap(8) + label(20) = 168 to selectedEdit
        contentStartY := state.btnRowY + 44
        selectedEditY := contentStartY + 168
        bottomPad     := 12
        screenMargin  := 16

        idealH  := selectedEditY + 150 + bottomPad          ; preferred: 150-px selected edit
        maxH    := workBottom - winY - screenMargin          ; hard cap: don't touch screen edge
        actualH := Max(Min(idealH, maxH), contentStartY + 60) ; always show at least a sliver

        ; Let the selected-text edit absorb whatever vertical space remains.
        selectedEditH := Max(40, actualH - selectedEditY - bottomPad)
        state.textEdit.Move(, , , selectedEditH)

        state.gui.Show("w520 h" actualH)
    } else {
        state.gui.Show("w520 h" (state.btnRowY + 56))
    }
}

LLMConfirmSend(state, *) {
    global _LLMState

    if (state.chkSkip.Value = 1)
        _LLMState.confirmUntilTick := A_TickCount + 3600000

    if (state.nagVisible && !state.userUpdatedPricing)
        LLMPricingSnoozeNag()

    systemPrompt := state.systemEdit.Value
    selectedText := state.textEdit.Value
    try state.gui.Destroy()
    LLMCallsStartRequest(state.category, state.title, systemPrompt, selectedText, state.pasteTarget)
}

LLMConfirmClose(state, *) {
    try state.gui.Destroy()
}

OpenLLMCustomWindow(selectedText, pasteTarget := 0) {
    global _LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory

    LLMCallsLoadPromptData()

    category := (_LLMCategories.Length > 0) ? _LLMCategories[1] : "General"
    customGui := Gui("+AlwaysOnTop +Resize +MinSize760x560", T("llm_custom"))
    customGui.SetFont("s10", "Segoe UI")

    customGui.AddGroupBox("x10 y8 w220 h500", T("llm_starting_point"))
    catList := customGui.AddListBox("x22 y30 w196 h180", _LLMCategories)
    promptList := customGui.AddListBox("x22 y222 w196 h240")

    customGui.AddGroupBox("x240 y8 w510 h500", T("llm_calls"))
    customGui.AddText("x254 y30 w480", T("llm_system_prompt"))
    systemEdit := AddStandardBorderEdit(customGui, 254, 48, 480, 180, "Multi WantTab")
    customGui.AddText("x254 y238 w480", T("llm_selected_text"))
    textEdit := AddStandardBorderEdit(customGui, 254, 256, 480, 210, "Multi WantTab")
    textEdit.Value := selectedText

    btnSave := customGui.AddButton("x254 y520 w130 h30", T("llm_save_new_entry"))
    btnSend := customGui.AddButton("x492 y520 w74 h30", T("llm_send"))
    btnCancel := customGui.AddButton("x576 y520 w74 h30", T("hotkey_dialog_cancel"))

    state := {
        gui: customGui,
        catList: catList,
        promptList: promptList,
        systemEdit: systemEdit,
        textEdit: textEdit,
        pasteTarget: pasteTarget,
        currentCategory: category,
        currentTitle: ""
    }

    catList.OnEvent("Change", LLMCustomCategoryChange.Bind(state))
    promptList.OnEvent("Change", LLMCustomPromptChange.Bind(state))
    btnSave.OnEvent("Click", LLMCustomSaveAsNewEntry.Bind(state))
    btnSend.OnEvent("Click", LLMCustomSend.Bind(state))
    btnCancel.OnEvent("Click", LLMCustomClose.Bind(state))
    customGui.OnEvent("Close", LLMCustomClose.Bind(state))
    customGui.OnEvent("Escape", LLMCustomClose.Bind(state))

    customGui.Show("w760 h562")
    catList.Choose(1)
    LLMCustomLoadCategory(state, category)
}

LLMCustomLoadCategory(state, category) {
    global _LLMEntryOrderByCategory

    state.currentCategory := category
    state.currentTitle := ""
    Loop LB_GetCount(state.promptList.Hwnd)
        state.promptList.Delete(1)

    if !_LLMEntryOrderByCategory.Has(category)
        return

    order := _LLMEntryOrderByCategory[category]
    if (order.Length > 0) {
        state.promptList.Add(order)
        state.promptList.Choose(1)
        LLMCustomPromptChange(state, state.promptList)
    }
}

LLMCustomCategoryChange(state, ctrl, *) {
    if (ctrl.Text != "")
        LLMCustomLoadCategory(state, ctrl.Text)
}

LLMCustomPromptChange(state, ctrl, *) {
    global _LLMEntriesByCategory
    title := ctrl.Text
    if (title = "")
        return
    state.currentTitle := title
    state.systemEdit.Value := _LLMEntriesByCategory[state.currentCategory][title]
}

LLMCustomSaveAsNewEntry(state, *) {
    global _LLMEntriesByCategory, _LLMEntryOrderByCategory

    category := state.currentCategory
    if (category = "")
        category := "General"

    result := InputBox("Name for new LLM entry:", T("llm_save_new_entry"))
    if (result.Result != "OK")
        return

    title := Trim(result.Value)
    if (title = "")
        return

    LLMEditorEnsureCategory(category)
    entries := _LLMEntriesByCategory[category]
    order := _LLMEntryOrderByCategory[category]

    if entries.Has(title) {
        ans := MsgBox("An LLM entry with this name exists. Overwrite?", T("llm_save_new_entry"), "YesNo Icon?")
        if (ans != "Yes")
            return
    } else {
        order.Push(title)
        if (category = state.currentCategory)
            state.promptList.Add([title])
    }

    entries[title] := state.systemEdit.Value
    if LLMCallsSavePromptData()
        ShowTransientToolTip(T("llm_entry_saved"))
}

LLMCustomSend(state, *) {
    title := state.currentTitle != "" ? state.currentTitle : T("llm_custom")
    systemPrompt := state.systemEdit.Value
    selectedText := state.textEdit.Value
    try state.gui.Destroy()
    LLMCallsStartRequest(state.currentCategory, title, systemPrompt, selectedText, state.pasteTarget)
}

LLMCustomClose(state, *) {
    try state.gui.Destroy()
}

LLMCallsStartRequest(category, title, systemPrompt, selectedText, pasteTarget := 0) {
    global _LLMState

    LLMCallsInitDefaults()

    if LLMCallsLooksLikeSensitiveClipboardLeak(selectedText) {
        MsgBox T("llm_sensitive_selection_blocked"), T("llm_response_title")
        return false
    }

    apiKey := LLMCallsReadApiKey()
    if (apiKey = "") {
        MsgBox T("llm_api_key_missing"), T("llm_settings_title")
        OpenLLMSettingsWindow()
        return false
    }

    finalSystemPrompt := ""
    body := LLMCallsBuildRequestBody(category, title, systemPrompt, selectedText, &finalSystemPrompt)
    callState := LLMCallsOpenResponseWindow(category, title, systemPrompt, finalSystemPrompt, selectedText, pasteTarget)

    req := 0
    try {
        req := LLMCallsCreateProviderRequest(apiKey)
        req.Send(body)
    } catch as err {
        LLMCallsCompleteResponse(callState, false, "Could not start " LLMCallsProviderDisplayName() " request.`r`n`r`n" err.Message)
        return false
    }

    callState.request := req
    callState.timerFn := LLMCallsPollRequest.Bind(callState)
    SetTimer(callState.timerFn, 250)
    return true
}

LLMCallsProviderDisplayName(provider := "") {
    global _LLMState
    if (provider = "") {
        LLMCallsInitDefaults()
        provider := _LLMState.provider
    }
    switch StrLower(provider) {
        case "anthropic": return "Anthropic"
    }
    return provider
}

LLMCallsCreateProviderRequest(apiKey) {
    global _LLMState

    switch _LLMState.provider {
        case "anthropic":
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.Open("POST", "https://api.anthropic.com/v1/messages", true)
            req.SetRequestHeader("x-api-key", apiKey)
            req.SetRequestHeader("anthropic-version", "2023-06-01")
            req.SetRequestHeader("content-type", "application/json")
            return req
    }
    throw Error("Unsupported LLM provider: " _LLMState.provider)
}

LLMCallsBuildRequestBody(category, title, systemPrompt, selectedText, &finalSystemPrompt := "") {
    global _LLMState
    switch _LLMState.provider {
        case "anthropic":
            return LLMCallsBuildAnthropicBody(category, title, systemPrompt, selectedText, &finalSystemPrompt)
    }
    throw Error("Unsupported LLM provider: " _LLMState.provider)
}

LLMCallsBuildAnthropicBody(category, title, systemPrompt, selectedText, &finalSystemPrompt := "") {
    global _LLMState
    finalSystemPrompt := LLMCallsBuildFinalSystemPrompt(category, title, systemPrompt)

    body := '{"model":"' JsonEscape(_LLMState.model) '","max_tokens":' _LLMState.maxTokens ','
    if (Trim(finalSystemPrompt) != "")
        body .= '"system":"' JsonEscape(finalSystemPrompt) '",'
    body .= '"messages":[{"role":"user","content":"' JsonEscape(selectedText) '"}]}'
    return body
}

; Build the system prompt that will actually be sent: raw prompt + examples + budget instruction.
LLMCallsBuildFinalSystemPrompt(category, title, systemPrompt) {
    examples := LLMExamplesBuildPromptSection(category, title)
    if (examples != "") {
        if (Trim(systemPrompt) != "")
            systemPrompt .= "`n`n"
        systemPrompt .= examples
    }
    budgetInstruction := LLMCallsResponseBudgetInstruction()
    if (Trim(budgetInstruction) != "") {
        if (Trim(systemPrompt) != "")
            systemPrompt .= "`n`n"
        systemPrompt .= budgetInstruction
    }
    return systemPrompt
}

LLMCallsPollRequest(callState) {
    if callState.completed
        return

    if (A_TickCount - callState.startedTick > callState.timeoutMs) {
        SetTimer(callState.timerFn, 0)
        LLMCallsAbortRequest(callState)
        LLMCallsCompleteResponse(callState, false, LLMCallsProviderDisplayName(callState.provider) " request timed out after " Round(callState.timeoutMs / 1000) " seconds.")
        return
    }

    req := callState.request
    done := false
    try done := req.WaitForResponse(0)
    catch as err {
        SetTimer(callState.timerFn, 0)
        LLMCallsCompleteResponse(callState, false, LLMCallsProviderDisplayName(callState.provider) " request failed.`r`n`r`n" err.Message)
        return
    }

    if !done
        return

    SetTimer(callState.timerFn, 0)
    status := 0
    responseText := ""
    try status := req.Status
    responseText := LLMCallsReadResponseUtf8(req)
    callState.httpStatus := status
    callState.rawResponseText := responseText

    if (status >= 200 && status < 300) {
        text := LLMCallsExtractProviderText(callState.provider, responseText)
        if (text = "")
            text := responseText
        LLMCallsCompleteResponse(callState, true, text)
        return
    }

    errText := LLMCallsExtractProviderError(callState.provider, responseText)
    if (errText = "")
        errText := responseText
    LLMCallsCompleteResponse(callState, false, LLMCallsProviderDisplayName(callState.provider) " returned HTTP " status ".`r`n`r`n" errText)
}

LLMCallsAbortRequest(state) {
    if IsObject(state) && IsObject(state.request) {
        try state.request.Abort()
    }
}

; Read the HTTP response body as a properly decoded UTF-8 string.
; WinHttp.ResponseText defaults to the system code page (usually CP1252) when the
; Content-Type header omits an explicit charset — causing mojibake for em-dashes,
; curly quotes, and any other non-ASCII characters in the JSON payload.
; ADODB.Stream lets us hand it the raw bytes and decode as UTF-8 explicitly.
LLMCallsReadResponseUtf8(req) {
    try {
        stream := ComObject("ADODB.Stream")
        stream.Type := 1        ; adTypeBinary
        stream.Open()
        stream.Write(req.ResponseBody)
        stream.Position := 0
        stream.Type := 2        ; adTypeText
        stream.Charset := "UTF-8"
        txt := stream.ReadText()
        stream.Close()
        return txt
    }
    ; ADODB unavailable — fall back to ResponseText (may still mojibake on non-ASCII).
    txt := ""
    try txt := req.ResponseText
    return txt
}

LLMCallsExtractProviderText(provider, responseText) {
    switch StrLower(provider) {
        case "anthropic": return LLMCallsExtractAnthropicText(responseText)
    }
    return ""
}

LLMCallsExtractProviderError(provider, responseText) {
    switch StrLower(provider) {
        case "anthropic": return LLMCallsExtractAnthropicError(responseText)
    }
    return ""
}

LLMCallsOpenResponseWindow(category, title, systemPrompt, finalSystemPrompt, selectedText, pasteTarget := 0) {
    global _LLMState

    _LLMState.nextRequestId += 1
    requestId := _LLMState.nextRequestId

    responseGui := Gui("+Resize +MinSize660x420", T("llm_response_title") " - " title)
    responseGui.SetFont("s10", "Segoe UI")
    responseGui.AddText("x10 y10 w640", category " / " title)
    responseEdit := AddStandardBorderEdit(responseGui, 10, 34, 640, 300, "Multi ReadOnly WantTab")
    responseEdit.Value := T("llm_waiting")
    statusText := responseGui.AddText("x10 y342 w640 h20", T("llm_waiting"))
    btnCopy := responseGui.AddButton("x180 y370 w90 h30", T("llm_copy_response"))
    btnPaste := responseGui.AddButton("x280 y370 w90 h30", T("llm_paste_response"))
    btnSave := responseGui.AddButton("x380 y370 w110 h30", T("llm_save_to_log"))
    btnClose := responseGui.AddButton("x500 y370 w110 h30", T("hotkey_dialog_cancel"))
    btnCopy.Enabled := false
    btnPaste.Enabled := false
    btnSave.Enabled := false

    state := {
        id: requestId,
        gui: responseGui,
        provider: _LLMState.provider,
        model: _LLMState.model,
        category: category,
        title: title,
        systemPrompt: systemPrompt,
        finalSystemPrompt: finalSystemPrompt,
        selectedText: selectedText,
        pasteTarget: pasteTarget,
        ok: false,
        completed: false,
        startedTick: A_TickCount,
        completedTick: 0,
        timeoutMs: _LLMState.timeoutSeconds * 1000,
        httpStatus: 0,
        rawResponseText: "",
        responseText: "",
        responseEdit: responseEdit,
        statusText: statusText,
        btnCopy: btnCopy,
        btnPaste: btnPaste,
        btnSave: btnSave,
        btnClose: btnClose,
        request: 0,
        timerFn: 0
    }

    btnCopy.OnEvent("Click", LLMCallsResponseCopy.Bind(state))
    btnPaste.OnEvent("Click", LLMCallsResponsePaste.Bind(state))
    btnSave.OnEvent("Click", LLMCallsResponseSaveAndClose.Bind(state))
    btnClose.OnEvent("Click", LLMCallsResponseClose.Bind(state))
    responseGui.OnEvent("Close", LLMCallsResponseClose.Bind(state))
    responseGui.OnEvent("Escape", LLMCallsResponseClose.Bind(state))
    responseGui.Show("w660 h412")

    _LLMState.responseWindows[requestId] := state
    return state
}

LLMCallsCompleteResponse(state, ok, text) {
    if state.completed
        return
    state.completed := true
    state.completedTick := A_TickCount
    state.ok := ok
    state.responseText := text
    state.responseEdit.Value := text
    elapsed := Round((state.completedTick - state.startedTick) / 1000, 1)
    status := ok ? "OK" : "Error"
    state.statusText.Text := status " - " elapsed "s"
    state.btnCopy.Enabled := ok
    state.btnPaste.Enabled := ok && IsObject(state.pasteTarget)
    state.btnSave.Enabled := true
    state.btnClose.Text := T("menu_close")
}

LLMCallsResponseCopy(state, *) {
    if !state.ok
        return
    A_Clipboard := state.responseText
    ShowTransientToolTip(T("llm_response_copied"))
}

LLMCallsResponsePaste(state, *) {
    if !state.ok || !IsObject(state.pasteTarget)
        return
    if !FocusPasteTarget(state.pasteTarget) {
        ShowTransientToolTip(T("msg_paste_target_lost"))
        return
    }
    PastePlain(state.responseText, state.pasteTarget)
    ShowTransientToolTip(T("llm_response_pasted"))
}

LLMCallsResponseSaveAndClose(state, *) {
    if LLMCallsAppendResponseLog(state) {
        ShowTransientToolTip(T("llm_log_saved"))
        LLMCallsResponseClose(state)
    } else {
        MsgBox T("llm_log_failed"), T("llm_response_title")
    }
}

LLMCallsResponseClose(state, *) {
    global _LLMState
    if IsObject(state.timerFn)
        SetTimer(state.timerFn, 0)
    if IsObject(state) && !state.completed
        LLMCallsAbortRequest(state)
    if IsObject(_LLMState) && _LLMState.responseWindows.Has(state.id)
        _LLMState.responseWindows.Delete(state.id)
    try state.gui.Destroy()
}

LLMCallsAppendResponseLog(state) {
    global LLMResponseLogFile

    LLMResponseLogFile := LLMCallsGetResponseLogPath()
    EnsureParentDirectory(LLMResponseLogFile)
    stamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    elapsed := state.completedTick ? Round((state.completedTick - state.startedTick) / 1000, 1) : ""
    block := "`r`n## " stamp " - " state.title "`r`n`r`n"
    block .= "- Status: " (state.ok ? "OK" : "Error") "`r`n"
    block .= "- Provider: " LLMCallsProviderDisplayName(state.provider) "`r`n"
    block .= "- Model: " state.model "`r`n"
    block .= "- Prompt category: " state.category "`r`n"
    if (state.httpStatus)
        block .= "- HTTP status: " state.httpStatus "`r`n"
    if (elapsed != "")
        block .= "- Duration: " elapsed "s`r`n"
    block .= "`r`n### System prompt`r`n`r`n" state.systemPrompt "`r`n`r`n"
    if (state.finalSystemPrompt != state.systemPrompt)
        block .= "### Final system prompt`r`n`r`n" state.finalSystemPrompt "`r`n`r`n"
    block .= "### Highlighted text`r`n`r`n" state.selectedText "`r`n`r`n"
    block .= "### Response`r`n`r`n" state.responseText "`r`n"

    try {
        FileAppend(block, LLMResponseLogFile, "UTF-8")
        return true
    } catch {
        return false
    }
}

LLMCallsGetResponseLogPath() {
    return LLMCallsGetLocalRootDir() "\llmlogs\LLMresponselog.md"
}

LLMCallsReadApiKey() {
    apiKey := ""
    for _, keyPath in LLMCallsGetApiKeyPaths() {
        if FileExist(keyPath)
            apiKey := Trim(IniRead(keyPath, "anthropic", "api_key", ""))
        if (apiKey != "")
            break
    }
    if (apiKey = "")
        apiKey := Trim(EnvGet("ANTHROPIC_API_KEY"))
    return apiKey
}

LLMCallsGetApiKeyPath() {
    paths := LLMCallsGetApiKeyPaths()
    return paths[1]
}

LLMCallsGetApiKeyPaths() {
    paths := []
    rootPath := LLMCallsGetProjectRootApiKeyPath()
    if (rootPath != "")
        paths.Push(rootPath)
    scriptPath := A_ScriptDir "\apikey.ini"
    if (rootPath = "" || scriptPath != rootPath)
        paths.Push(scriptPath)
    return paths
}

LLMCallsGetProjectRootApiKeyPath() {
    rootDir := LLMCallsGetLocalRootDir()
    if (rootDir != "")
        return rootDir "\apikey.ini"
    return A_ScriptDir "\apikey.ini"
}

LLMCallsGetLocalRootDir() {
    scriptDirName := ""
    parentDir := ""
    SplitPath(A_ScriptDir, &scriptDirName, &parentDir)
    if (StrLower(scriptDirName) = "dist") {
        if FileExist(parentDir "\build_pastemenu.bat") || FileExist(parentDir "\PasteMenu.ahk")
            return parentDir
    }
    if FileExist(A_ScriptDir "\build_pastemenu.bat") || FileExist(A_ScriptDir "\PasteMenu.ahk")
        return A_ScriptDir
    return A_ScriptDir
}

LLMCallsEnsureApiKeyFile() {
    keyPath := LLMCallsGetApiKeyPath()
    if FileExist(keyPath)
        return keyPath

    tpl := "
(
; PasteMenu local API credentials.
; This file is ignored by git. Do not commit real API keys.
; Add your Anthropic API key below, or set ANTHROPIC_API_KEY in your environment.

[anthropic]
api_key=
)"
    FileAppend(tpl, keyPath, "UTF-8")
    return keyPath
}

OpenLLMSettingsWindow(*) {
    global _LLMState

    LLMCallsInitDefaults()
    if IsObject(_LLMState.settingsWindow) {
        try {
            _LLMState.settingsWindow.gui.Show()
            _LLMState.settingsWindow.gui.Focus()
            return
        }
    }

    sGui := Gui("+AlwaysOnTop", T("llm_settings_title"))
    sGui.SetFont("s10", "Segoe UI")

    sGui.AddText("x12 y14 w120", T("llm_provider"))
    providerDDL := sGui.AddDropDownList("x140 y12 w180 Choose1", ["Anthropic"])
    providerDDL.Enabled := false

    sGui.AddText("x12 y52 w120", T("llm_model"))
    modelItems := LLMSettingsBuildModelComboItems(_LLMState.model)
    modelCombo := sGui.AddComboBox("x140 y50 w280 vModelCombo", modelItems)
    modelCombo.Text := _LLMState.model
    modelPriceText := sGui.AddText("x430 y52 w230 h20", "")

    btnUpdatePricing := sGui.AddButton("x140 y82 w170 h26", T("llm_update_pricing"))
    pricingUpdatedText := sGui.AddText("x320 y86 w340 h20", "")

    btnRefreshModels := sGui.AddButton("x140 y114 w170 h26", T("llm_refresh_models"))
    modelsUpdatedText := sGui.AddText("x320 y118 w340 h20", "")

    sGui.AddText("x12 y150 w120", T("llm_max_tokens"))
    maxTokensEdit := sGui.AddEdit("x140 y148 w90 h24 Number", _LLMState.maxTokens "")
    maxTokensHint := sGui.AddText("x240 y150 w420 h24", LLMSettingsMaxTokenHint())

    sGui.AddText("x12 y188 w120", T("llm_timeout_seconds"))
    timeoutEdit := sGui.AddEdit("x140 y186 w90 h24 Number", _LLMState.timeoutSeconds "")

    sGui.AddText("x12 y226 w120", T("llm_example_preface"))
    examplePrefaceEdit := AddStandardBorderEdit(sGui, 140, 224, 520, 86, "Multi WantTab")
    examplePrefaceEdit.Value := _LLMState.examplePreface

    btnApiKey := sGui.AddButton("x12 y330 w170 h30", T("llm_open_api_key"))
    btnSave := sGui.AddButton("x490 y330 w74 h30", T("hotkey_dialog_save"))
    btnClose := sGui.AddButton("x574 y330 w74 h30", T("settings_close"))

    state := {
        gui: sGui,
        providerDDL: providerDDL,
        modelCombo: modelCombo,
        modelPriceText: modelPriceText,
        pricingUpdatedText: pricingUpdatedText,
        modelsUpdatedText: modelsUpdatedText,
        btnUpdatePricing: btnUpdatePricing,
        btnRefreshModels: btnRefreshModels,
        maxTokensEdit: maxTokensEdit,
        maxTokensHint: maxTokensHint,
        timeoutEdit: timeoutEdit,
        examplePrefaceEdit: examplePrefaceEdit
    }
    _LLMState.settingsWindow := state

    LLMSettingsRefreshPricingLabels(state)

    btnApiKey.OnEvent("Click", LLMSettingsOpenApiKeyFile.Bind(state))
    btnSave.OnEvent("Click", LLMSettingsSave.Bind(state))
    btnClose.OnEvent("Click", LLMSettingsClose.Bind(state))
    btnUpdatePricing.OnEvent("Click", LLMSettingsUpdatePricing.Bind(state))
    btnRefreshModels.OnEvent("Click", LLMSettingsRefreshModels.Bind(state))
    modelCombo.OnEvent("Change", LLMSettingsModelChanged.Bind(state))
    sGui.OnEvent("Close", LLMSettingsClose.Bind(state))
    sGui.OnEvent("Escape", LLMSettingsClose.Bind(state))
    sGui.Show("w680 h372")
}

LLMSettingsBuildModelComboItems(currentModel) {
    items := []
    seen := Map()
    add(id) {
        id := Trim(id)
        if (id = "" || seen.Has(id))
            return
        seen[id] := true
        items.Push(id)
    }
    add(currentModel)
    for _, id in LLMPricingModelList()
        add(id)
    LLMPricingInit()
    global _LLMPricingState
    for id, _ in _LLMPricingState.prices
        add(id)
    return items
}

LLMSettingsRefreshPricingLabels(state) {
    LLMPricingInit()
    global _LLMPricingState
    state.pricingUpdatedText.Text := T("llm_pricing_last_updated") ": " LLMPricingFormatTimestamp(_LLMPricingState.pricingUpdated)
    state.modelsUpdatedText.Text := T("llm_models_last_updated") ": " LLMPricingFormatTimestamp(_LLMPricingState.modelsUpdated)
    LLMSettingsModelChanged(state, state.modelCombo)
}

LLMSettingsModelChanged(state, ctrl, *) {
    modelId := Trim(ctrl.Text)
    if (modelId = "") {
        state.modelPriceText.Text := ""
        return
    }
    p := LLMPricingForModel(modelId)
    if !IsObject(p) {
        state.modelPriceText.Text := T("llm_pricing_unknown")
        return
    }
    state.modelPriceText.Text := Format("${:.2f} in / ${:.2f} out per Mtok", p.input, p.output)
}

LLMSettingsUpdatePricing(state, *) {
    ShowTransientToolTip(T("llm_pricing_updating"))
    errMsg := ""
    ok := LLMPricingUpdateAll(&errMsg)
    if !ok {
        MsgBox T("llm_pricing_update_failed") ".`r`n`r`n" errMsg, T("llm_settings_title")
        return
    }

    ; Rebuild model combo with the freshly fetched list.
    currentText := Trim(state.modelCombo.Text)
    state.modelCombo.Delete()
    items := LLMSettingsBuildModelComboItems(currentText)
    state.modelCombo.Add(items)
    state.modelCombo.Text := currentText
    LLMSettingsRefreshPricingLabels(state)
    if (errMsg != "")
        ShowTransientToolTip(errMsg)
    else
        ShowTransientToolTip(T("llm_pricing_update_ok"))
}

LLMSettingsRefreshModels(state, *) {
    errMsg := ""
    models := LLMPricingFetchModels(&errMsg)
    if !IsObject(models) || models.Length = 0 {
        MsgBox T("llm_pricing_update_failed") ".`r`n`r`n" errMsg, T("llm_settings_title")
        return
    }
    global _LLMPricingState
    LLMPricingInit()
    _LLMPricingState.models := models
    _LLMPricingState.modelsUpdated := A_Now
    LLMPricingSave()

    currentText := Trim(state.modelCombo.Text)
    state.modelCombo.Delete()
    state.modelCombo.Add(LLMSettingsBuildModelComboItems(currentText))
    state.modelCombo.Text := currentText
    LLMSettingsRefreshPricingLabels(state)
    ShowTransientToolTip(T("llm_pricing_update_ok"))
}

LLMSettingsOpenApiKeyFile(state, *) {
    keyPath := LLMCallsEnsureApiKeyFile()
    try Run('notepad.exe "' keyPath '"')
    catch
        MsgBox keyPath, T("llm_settings_title")
}

LLMSettingsSave(state, *) {
    global _LLMState

    model := Trim(state.modelCombo.Text)
    if (model != "")
        _LLMState.model := model
    _LLMState.maxTokens := LLMCallsNormalizeMaxTokens(state.maxTokensEdit.Value)
    _LLMState.timeoutSeconds := LLMCallsNormalizeTimeoutSeconds(state.timeoutEdit.Value)
    _LLMState.examplePreface := state.examplePrefaceEdit.Value
    state.maxTokensEdit.Value := _LLMState.maxTokens ""
    state.maxTokensHint.Text := LLMSettingsMaxTokenHint()
    state.timeoutEdit.Value := _LLMState.timeoutSeconds ""
    LLMCallsSaveToSettings()
    ShowTransientToolTip(T("msg_settings_saved"))
}

LLMSettingsMaxTokenHint() {
    return T("llm_max_tokens_hint") " " LLMCallsResponseBudgetInstruction()
}

LLMSettingsClose(state, *) {
    global _LLMState
    try state.gui.Destroy()
    if IsObject(_LLMState)
        _LLMState.settingsWindow := 0
}

OpenLLMCallsEditor(category := "", *) {
    global _LLMState, _LLMCategories, _LLMEntryOrderByCategory

    LLMCallsInitDefaults()
    LLMCallsLoadPromptData()
    if IsObject(_LLMState.promptEditor) {
        try {
            _LLMState.promptEditor.gui.Show()
            _LLMState.promptEditor.gui.Focus()
            return
        }
    }

    if (category = "")
        category := (_LLMCategories.Length > 0) ? _LLMCategories[1] : "General"

    editorGui := Gui("+Resize +MinSize1040x560", T("llm_prompt_editor_title") " - " category)
    editorGui.SetFont("s10", "Segoe UI")

    editorGui.AddGroupBox("x10 y8 w220 h540", "Categories")
    categoryList := editorGui.AddListBox("x22 y30 w196 h380", _LLMCategories)
    btnCatRename := editorGui.AddButton("x22 y418 w95 h30", T("menu_rename"))
    btnCatDelete := editorGui.AddButton("x123 y418 w95 h30", "Delete")
    btnCatNew := editorGui.AddButton("x22 y454 w196 h30", T("menu_new_category"))

    editorGui.AddGroupBox("x240 y8 w250 h540", "Entries")
    entryList := editorGui.AddListBox("x252 y30 w226 h470")

    editorGui.AddGroupBox("x500 y8 w530 h540", "Entry Editor")
    editorGui.AddText("x514 y30 w500", "Title")
    titleEdit := AddStandardBorderEdit(editorGui, 514, 48, 500, 24)
    editorGui.AddText("x514 y80 w500", T("llm_system_prompt"))
    contentEdit := AddStandardBorderEdit(editorGui, 514, 98, 500, 390, "Multi WantTab")

    btnSave := editorGui.AddButton("x514 y514 w100 h28", "Save")
    btnNew := editorGui.AddButton("x614 y514 w110 h28", "New entry")
    btnDelete := editorGui.AddButton("x724 y514 w100 h28", "Delete")
    btnExamples := editorGui.AddButton("x824 y514 w100 h28", T("llm_examples"))
    btnClose := editorGui.AddButton("x924 y514 w90 h28", "Close")

    state := {
        gui: editorGui,
        categoryList: categoryList,
        entryList: entryList,
        titleEdit: titleEdit,
        contentEdit: contentEdit,
        btnExamples: btnExamples,
        currentCategory: category,
        currentTitle: "",
        suppressCategoryChange: false
    }
    _LLMState.promptEditor := state

    categoryList.OnEvent("Change", LLMEditorCategoryChange.Bind(state))
    entryList.OnEvent("Change", LLMEditorSelectEntry.Bind(state))
    btnCatRename.OnEvent("Click", LLMEditorRenameCategory.Bind(state))
    btnCatDelete.OnEvent("Click", LLMEditorDeleteCategory.Bind(state))
    btnCatNew.OnEvent("Click", LLMEditorNewCategory.Bind(state))
    btnSave.OnEvent("Click", LLMEditorSave.Bind(state))
    btnNew.OnEvent("Click", LLMEditorNew.Bind(state))
    btnDelete.OnEvent("Click", LLMEditorDelete.Bind(state))
    btnExamples.OnEvent("Click", OpenLLMExampleManager.Bind(state))
    btnClose.OnEvent("Click", LLMEditorClose.Bind(state))
    editorGui.OnEvent("Close", LLMEditorClose.Bind(state))
    editorGui.OnEvent("Escape", LLMEditorClose.Bind(state))

    editorGui.Show("w1040 h560")
    LLMEditorLoadCategory(state, category)
}

LLMEditorLoadCategory(state, category, selectTitle := "", startNew := false) {
    global _LLMCategories, _LLMEntryOrderByCategory

    if !_LLMEntryOrderByCategory.Has(category)
        return false

    state.currentCategory := category
    state.currentTitle := ""
    try state.gui.Title := T("llm_prompt_editor_title") " - " category

    state.suppressCategoryChange := true
    try {
        catIdx := FindIndexInArray(_LLMCategories, category)
        if catIdx
            state.categoryList.Choose(catIdx)
    } finally {
        state.suppressCategoryChange := false
    }

    Loop LB_GetCount(state.entryList.Hwnd)
        state.entryList.Delete(1)

    order := _LLMEntryOrderByCategory[category]
    if (order.Length > 0)
        state.entryList.Add(order)

    if (startNew || order.Length = 0) {
        LLMEditorNew(state)
        return true
    }

    idx := 1
    if (selectTitle != "") {
        found := FindIndexInArray(order, selectTitle)
        if found
            idx := found
    }
    state.entryList.Choose(idx)
    LLMEditorSelectEntry(state, state.entryList)
    return true
}

LLMEditorCategoryChange(state, ctrl, *) {
    if state.suppressCategoryChange
        return
    if (ctrl.Text != "")
        LLMEditorLoadCategory(state, ctrl.Text)
}

LLMEditorSelectEntry(state, ctrl, *) {
    global _LLMEntriesByCategory
    title := ctrl.Text
    if (title = "")
        return
    state.currentTitle := title
    state.titleEdit.Value := title
    state.contentEdit.Value := _LLMEntriesByCategory[state.currentCategory][title]
    state.btnExamples.Enabled := true
}

LLMEditorNew(state, *) {
    state.currentTitle := ""
    try state.entryList.Value := 0
    state.titleEdit.Value := ""
    state.contentEdit.Value := ""
    state.btnExamples.Enabled := false
    state.titleEdit.Focus()
}

LLMEditorSave(state, *) {
    global _LLMEntriesByCategory, _LLMEntryOrderByCategory

    category := state.currentCategory
    oldTitle := state.currentTitle
    newTitle := Trim(state.titleEdit.Value)
    if (newTitle = "") {
        SoundBeep 1200
        return
    }

    entries := _LLMEntriesByCategory[category]
    order := _LLMEntryOrderByCategory[category]

    if (oldTitle != "" && oldTitle != newTitle) {
        if entries.Has(newTitle) {
            ans := MsgBox("An LLM entry with this title exists. Overwrite?", T("llm_prompt_editor_title"), "YesNo Icon?")
            if (ans != "Yes")
                return
            idxExisting := FindIndexInArray(order, newTitle)
            if idxExisting
                order.RemoveAt(idxExisting)
        }
        idxOld := FindIndexInArray(order, oldTitle)
        if idxOld
            order[idxOld] := newTitle
        entries.Delete(oldTitle)
        LLMExampleRenameLLMEntry(category, oldTitle, category, newTitle, false)
    } else if !entries.Has(newTitle) {
        order.Push(newTitle)
    }

    entries[newTitle] := state.contentEdit.Value
    if !LLMCallsSavePromptData() {
        MsgBox "Could not save LLM prompts.", T("llm_prompt_editor_title")
        return
    }
    if (oldTitle != "" && oldTitle != newTitle)
        LLMExampleLinksSave()
    LLMEditorLoadCategory(state, category, newTitle)
}

LLMEditorDelete(state, *) {
    global _LLMEntriesByCategory, _LLMEntryOrderByCategory

    title := state.currentTitle
    if (title = "")
        return
    ans := MsgBox("Delete LLM entry '" title "'?", T("llm_prompt_editor_title"), "YesNo Icon!")
    if (ans != "Yes")
        return

    category := state.currentCategory
    entries := _LLMEntriesByCategory[category]
    order := _LLMEntryOrderByCategory[category]
    if entries.Has(title)
        entries.Delete(title)
    idx := FindIndexInArray(order, title)
    if idx
        order.RemoveAt(idx)

    LLMExampleRemoveLLMEntry(category, title, false)
    LLMCallsSavePromptData()
    LLMExampleLinksSave()
    LLMEditorLoadCategory(state, category, "", order.Length = 0)
}

LLMEditorRenameCategory(state, *) {
    global _LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory

    oldName := state.currentCategory
    result := InputBox("New name for category '" oldName "':", T("menu_rename"),, oldName)
    if (result.Result != "OK")
        return
    newName := Trim(result.Value)
    if (newName = "" || newName = oldName)
        return
    if _LLMEntriesByCategory.Has(newName) {
        MsgBox "Category exists: " newName, T("llm_prompt_editor_title")
        return
    }

    idx := FindIndexInArray(_LLMCategories, oldName)
    if idx
        _LLMCategories[idx] := newName
    _LLMEntriesByCategory[newName] := _LLMEntriesByCategory[oldName]
    _LLMEntryOrderByCategory[newName] := _LLMEntryOrderByCategory[oldName]
    _LLMEntriesByCategory.Delete(oldName)
    _LLMEntryOrderByCategory.Delete(oldName)
    LLMExampleRenameLLMCategory(oldName, newName)
    LLMCallsSavePromptData()
    LLMEditorRefreshCategoryList(state)
    LLMEditorLoadCategory(state, newName)
}

LLMEditorDeleteCategory(state, *) {
    global _LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory

    category := state.currentCategory
    ans := MsgBox("Delete LLM category '" category "'?", T("llm_prompt_editor_title"), "YesNo Icon!")
    if (ans != "Yes")
        return

    idx := FindIndexInArray(_LLMCategories, category)
    if idx
        _LLMCategories.RemoveAt(idx)
    _LLMEntriesByCategory.Delete(category)
    _LLMEntryOrderByCategory.Delete(category)
    LLMExampleRemoveLLMCategory(category)

    if (_LLMCategories.Length = 0)
        LLMEditorEnsureCategory("General")

    LLMCallsSavePromptData()
    LLMEditorRefreshCategoryList(state)
    LLMEditorLoadCategory(state, _LLMCategories[1])
}

LLMEditorNewCategory(state, *) {
    result := InputBox("Name for new LLM category:", T("menu_new_category"))
    if (result.Result != "OK")
        return
    name := Trim(result.Value)
    if (name = "")
        return
    if !LLMEditorEnsureCategory(name) {
        MsgBox "Category exists: " name, T("llm_prompt_editor_title")
        return
    }
    LLMCallsSavePromptData()
    LLMEditorRefreshCategoryList(state)
    LLMEditorLoadCategory(state, name, "", true)
}

LLMEditorEnsureCategory(category) {
    global _LLMCategories, _LLMEntriesByCategory, _LLMEntryOrderByCategory
    if _LLMEntriesByCategory.Has(category)
        return false
    _LLMCategories.Push(category)
    _LLMEntriesByCategory[category] := Map()
    _LLMEntryOrderByCategory[category] := []
    return true
}

LLMEditorRefreshCategoryList(state) {
    global _LLMCategories
    Loop LB_GetCount(state.categoryList.Hwnd)
        state.categoryList.Delete(1)
    if (_LLMCategories.Length > 0)
        state.categoryList.Add(_LLMCategories)
}

LLMEditorClose(state, *) {
    global _LLMState
    try state.gui.Destroy()
    if IsObject(_LLMState)
        _LLMState.promptEditor := 0
}

OpenLLMExampleManager(editorState, *) {
    if !IsObject(editorState) || editorState.currentTitle = "" {
        SoundBeep 1200
        return
    }
    if !LoadCurrentSnippetData(&err) {
        MsgBox err, T("llm_examples")
        return
    }

    llmCategory := editorState.currentCategory
    llmTitle := editorState.currentTitle
    exGui := Gui("+AlwaysOnTop +Resize +MinSize760x460", T("llm_examples") " - " llmTitle)
    exGui.SetFont("s10", "Segoe UI")
    exGui.AddText("x12 y12 w736", llmCategory " / " llmTitle)
    exGui.AddText("x12 y42 w250", T("llm_linked_examples"))
    linkList := exGui.AddListBox("x12 y62 w260 h330")
    exGui.AddText("x292 y42 w450", T("llm_example_preview"))
    previewEdit := AddStandardBorderEdit(exGui, 292, 62, 450, 330, "Multi ReadOnly WantTab")
    btnAdd := exGui.AddButton("x12 y410 w82 h30", T("llm_add_example"))
    btnRemove := exGui.AddButton("x104 y410 w82 h30", T("llm_remove_example"))
    btnClose := exGui.AddButton("x660 y410 w82 h30", T("menu_close"))

    state := {
        gui: exGui,
        editorState: editorState,
        llmCategory: llmCategory,
        llmTitle: llmTitle,
        linkList: linkList,
        previewEdit: previewEdit,
        linkRows: []
    }

    linkList.OnEvent("Change", LLMExampleManagerSelect.Bind(state))
    btnAdd.OnEvent("Click", OpenLLMExamplePicker.Bind(state))
    btnRemove.OnEvent("Click", LLMExampleManagerRemove.Bind(state))
    btnClose.OnEvent("Click", LLMExampleManagerClose.Bind(state))
    exGui.OnEvent("Close", LLMExampleManagerClose.Bind(state))
    exGui.OnEvent("Escape", LLMExampleManagerClose.Bind(state))
    LLMExampleManagerRefresh(state)
    exGui.Show("w760 h454")
}

LLMExampleManagerRefresh(state) {
    global _EntriesByCategory

    state.linkRows := []
    LLMListBoxClear(state.linkList)
    links := LLMExampleLinksForCall(state.llmCategory, state.llmTitle)
    labels := []
    for key, _ in links {
        parts := StrSplit(key, "`t", , 2)
        if (parts.Length < 2)
            continue
        category := parts[1]
        title := parts[2]
        if !_EntriesByCategory.Has(category) || !_EntriesByCategory[category].Has(title)
            continue
        state.linkRows.Push({category: category, title: title})
        labels.Push(category " / " title)
    }
    if (labels.Length > 0) {
        state.linkList.Add(labels)
        state.linkList.Choose(1)
        LLMExampleManagerSelect(state, state.linkList)
    } else {
        state.previewEdit.Value := ""
    }
}

LLMExampleManagerSelect(state, ctrl, *) {
    global _EntriesByCategory
    idx := ctrl.Value
    if (idx < 1 || idx > state.linkRows.Length) {
        state.previewEdit.Value := ""
        return
    }
    item := state.linkRows[idx]
    if _EntriesByCategory.Has(item.category) && _EntriesByCategory[item.category].Has(item.title)
        state.previewEdit.Value := _EntriesByCategory[item.category][item.title]
    else
        state.previewEdit.Value := ""
}

LLMExampleManagerRemove(state, *) {
    idx := state.linkList.Value
    if (idx < 1 || idx > state.linkRows.Length)
        return
    item := state.linkRows[idx]
    LLMExampleLinkSet(state.llmCategory, state.llmTitle, item.category, item.title, false, true)
    LLMExampleManagerRefresh(state)
}

LLMExampleManagerClose(state, *) {
    try state.gui.Destroy()
}

OpenLLMExamplePicker(managerState, *) {
    global _Categories

    if !LoadCurrentSnippetData(&err) {
        MsgBox err, T("llm_examples")
        return
    }

    pickGui := Gui("+AlwaysOnTop +Resize +MinSize680x430", T("llm_add_example"))
    pickGui.SetFont("s10", "Segoe UI")
    pickGui.AddText("x12 y12 w180", "Categories")
    categoryList := pickGui.AddListBox("x12 y32 w190 h310", _Categories)
    pickGui.AddText("x222 y12 w190", "Entries")
    entryList := pickGui.AddListBox("x222 y32 w190 h310")
    pickGui.AddText("x432 y12 w230", T("llm_example_preview"))
    previewEdit := AddStandardBorderEdit(pickGui, 432, 32, 230, 310, "Multi ReadOnly WantTab")
    btnAdd := pickGui.AddButton("x500 y360 w74 h30", T("llm_add_example"))
    btnCancel := pickGui.AddButton("x584 y360 w74 h30", T("hotkey_dialog_cancel"))

    state := {
        gui: pickGui,
        managerState: managerState,
        categoryList: categoryList,
        entryList: entryList,
        previewEdit: previewEdit,
        currentCategory: ""
    }

    categoryList.OnEvent("Change", LLMExamplePickerCategoryChange.Bind(state))
    entryList.OnEvent("Change", LLMExamplePickerEntryChange.Bind(state))
    btnAdd.OnEvent("Click", LLMExamplePickerAdd.Bind(state))
    btnCancel.OnEvent("Click", LLMExamplePickerClose.Bind(state))
    pickGui.OnEvent("Close", LLMExamplePickerClose.Bind(state))
    pickGui.OnEvent("Escape", LLMExamplePickerClose.Bind(state))

    pickGui.Show("w680 h404")
    if (_Categories.Length > 0) {
        categoryList.Choose(1)
        LLMExamplePickerCategoryChange(state, categoryList)
    }
}

LLMExamplePickerCategoryChange(state, ctrl, *) {
    global _EntryOrderByCategory
    category := ctrl.Text
    state.currentCategory := category
    LLMListBoxClear(state.entryList)
    state.previewEdit.Value := ""
    if (category = "" || !_EntryOrderByCategory.Has(category))
        return
    order := _EntryOrderByCategory[category]
    if (order.Length > 0) {
        state.entryList.Add(order)
        state.entryList.Choose(1)
        LLMExamplePickerEntryChange(state, state.entryList)
    }
}

LLMExamplePickerEntryChange(state, ctrl, *) {
    global _EntriesByCategory
    title := ctrl.Text
    if (state.currentCategory != "" && title != "" && _EntriesByCategory.Has(state.currentCategory) && _EntriesByCategory[state.currentCategory].Has(title))
        state.previewEdit.Value := _EntriesByCategory[state.currentCategory][title]
    else
        state.previewEdit.Value := ""
}

LLMExamplePickerAdd(state, *) {
    title := state.entryList.Text
    if (state.currentCategory = "" || title = "") {
        SoundBeep 1200
        return
    }
    managerState := state.managerState
    LLMExampleLinkSet(managerState.llmCategory, managerState.llmTitle, state.currentCategory, title, true, true)
    LLMExampleManagerRefresh(managerState)
    try state.gui.Destroy()
}

LLMExamplePickerClose(state, *) {
    try state.gui.Destroy()
}

LLMListBoxClear(ctrl) {
    Loop SendMessage(0x018B, 0, 0, , "ahk_id " ctrl.Hwnd) ; LB_GETCOUNT
        ctrl.Delete(1)
}

LLMCallsExtractAnthropicText(json) {
    out := ""
    pos := 1
    pattern := '"text"\s*:\s*"((?:\\.|[^"\\])*)"'
    while (matchPos := RegExMatch(json, pattern, &m, pos)) {
        if (out != "")
            out .= "`r`n"
        out .= JsonUnescape(m[1])
        pos := matchPos + StrLen(m[0])
    }
    return out
}

LLMCallsExtractAnthropicError(json) {
    if RegExMatch(json, '"message"\s*:\s*"((?:\\.|[^"\\])*)"', &m)
        return JsonUnescape(m[1])
    return ""
}

JsonEscape(text) {
    out := ""
    Loop Parse text {
        ch := A_LoopField
        code := Ord(ch)
        if (ch = '"')
            out .= '\"'
        else if (ch = "\")
            out .= "\\"
        else if (ch = "`n")
            out .= "\n"
        else if (ch = "`r")
            out .= "\r"
        else if (ch = "`t")
            out .= "\t"
        else if (code < 32)
            out .= Format("\u{:04X}", code)
        else
            out .= ch
    }
    return out
}

JsonUnescape(text) {
    out := ""
    i := 1
    len := StrLen(text)
    while (i <= len) {
        ch := SubStr(text, i, 1)
        if (ch != "\") {
            out .= ch
            i += 1
            continue
        }

        i += 1
        if (i > len) {
            out .= "\"
            break
        }

        esc := SubStr(text, i, 1)
        switch esc {
            case '"': out .= '"'
            case "\": out .= "\"
            case "/": out .= "/"
            case "b": out .= Chr(8)
            case "f": out .= Chr(12)
            case "n": out .= "`n"
            case "r": out .= "`r"
            case "t": out .= "`t"
            case "u":
                hex := SubStr(text, i + 1, 4)
                if RegExMatch(hex, "i)^[0-9a-f]{4}$") {
                    out .= Chr(("0x" hex) + 0)
                    i += 4
                } else {
                    out .= "\u"
                }
            default:
                out .= esc
        }
        i += 1
    }
    return out
}
