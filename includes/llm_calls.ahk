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

LLMExamplesLoad() {
    global LLMExampleFile, _LLMExampleEntries

    _LLMExampleEntries := Map()
    EnsureParentDirectory(LLMExampleFile)
    if !FileExist(LLMExampleFile)
        return true

    text := ReadTextFile(LLMExampleFile, "UTF-8")
    Loop Parse text, "`n", "`r" {
        line := A_LoopField
        if (Trim(line) = "")
            continue
        parts := StrSplit(line, "`t", , 2)
        if (parts.Length < 2)
            continue
        category := parts[1]
        title := parts[2]
        if (category != "" && title != "")
            _LLMExampleEntries[LLMExampleKey(category, title)] := true
    }
    return true
}

LLMExamplesSave() {
    global LLMExampleFile, _LLMExampleEntries

    out := ""
    for key, _ in _LLMExampleEntries {
        out .= key "`r`n"
    }
    return WriteTextFileAtomic(LLMExampleFile, out, "UTF-8")
}

LLMExampleKey(category, title) {
    return category "`t" title
}

LLMExampleIsIncluded(category, title) {
    global _LLMExampleEntries
    if (category = "" || title = "")
        return false
    return _LLMExampleEntries.Has(LLMExampleKey(category, title))
}

LLMExampleSetIncluded(category, title, included, persist := true) {
    global _LLMExampleEntries
    if (category = "" || title = "")
        return

    key := LLMExampleKey(category, title)
    if included
        _LLMExampleEntries[key] := true
    else if _LLMExampleEntries.Has(key)
        _LLMExampleEntries.Delete(key)

    if persist
        LLMExamplesSave()
}

LLMExampleRenameEntry(oldCategory, oldTitle, newCategory, newTitle, persist := true) {
    included := LLMExampleIsIncluded(oldCategory, oldTitle)
    if (oldCategory != newCategory || oldTitle != newTitle)
        LLMExampleSetIncluded(oldCategory, oldTitle, false, false)
    if included
        LLMExampleSetIncluded(newCategory, newTitle, true, false)
    if persist
        LLMExamplesSave()
}

LLMExampleRemoveEntry(category, title, persist := true) {
    LLMExampleSetIncluded(category, title, false, persist)
}

LLMExampleRenameCategory(oldCategory, newCategory) {
    global _LLMExampleEntries

    changed := false
    replacements := []
    for key, _ in _LLMExampleEntries {
        parts := StrSplit(key, "`t", , 2)
        if (parts.Length < 2)
            continue
        if (parts[1] = oldCategory)
            replacements.Push({oldKey: key, newKey: LLMExampleKey(newCategory, parts[2])})
    }
    for _, item in replacements {
        _LLMExampleEntries.Delete(item.oldKey)
        _LLMExampleEntries[item.newKey] := true
        changed := true
    }
    if changed
        LLMExamplesSave()
}

LLMExampleRemoveCategory(category) {
    global _LLMExampleEntries

    removed := false
    keys := []
    for key, _ in _LLMExampleEntries {
        parts := StrSplit(key, "`t", , 2)
        if (parts.Length >= 2 && parts[1] = category)
            keys.Push(key)
    }
    for _, key in keys {
        _LLMExampleEntries.Delete(key)
        removed := true
    }
    if removed
        LLMExamplesSave()
}

LLMExampleCategoryHasIncluded(category) {
    global _LLMExampleEntries

    prefix := category "`t"
    for key, _ in _LLMExampleEntries {
        if (SubStr(key, 1, StrLen(prefix)) = prefix)
            return true
    }
    return false
}

LLMExamplesBuildPromptSection() {
    global _LLMExampleEntries, _EntriesByCategory, _LLMState

    LLMCallsInitDefaults()

    if !IsObject(_LLMExampleEntries) || _LLMExampleEntries.Count = 0
        return ""

    lines := []
    for key, _ in _LLMExampleEntries {
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
    if !LLMCallsGetTargetSelectedText(target, &selectedText) {
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
    if !LLMCallsGetTargetSelectedText(target, &selectedText) {
        ShowTransientToolTip(T("llm_no_selection"))
        return
    }
    OpenLLMCustomWindow(selectedText, target)
}

LLMCallsPendingTargetHasSelection() {
    global _PendingPasteTarget
    if !IsObject(_PendingPasteTarget)
        return false
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
    confirmGui := Gui("+AlwaysOnTop +Resize +MinSize520x190", T("llm_calls") " - " title)
    confirmGui.SetFont("s10", "Segoe UI")

    confirmGui.AddText("x12 y12 w496", category " / " title)
    chkSkip := confirmGui.AddCheckBox("x12 y44 w300 h24", T("llm_dont_ask_hour"))

    confirmGui.AddText("x12 y84 w496 vContentsLabel Hidden", T("llm_system_prompt"))
    systemEdit := confirmGui.AddEdit("x12 y104 w496 h120 Multi WantTab Hidden")
    systemEdit.Value := systemPrompt
    confirmGui.AddText("x12 y236 w496 vSelectedLabel Hidden", T("llm_selected_text"))
    textEdit := confirmGui.AddEdit("x12 y256 w496 h150 Multi WantTab Hidden")
    textEdit.Value := selectedText

    btnSend := confirmGui.AddButton("x236 y120 w82 h30", T("llm_send"))
    btnCancel := confirmGui.AddButton("x328 y120 w82 h30", T("hotkey_dialog_cancel"))
    btnShow := confirmGui.AddButton("x420 y120 w88 h30", T("llm_show_contents"))

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
        expanded: false
    }

    btnSend.OnEvent("Click", LLMConfirmSend.Bind(state))
    btnCancel.OnEvent("Click", LLMConfirmClose.Bind(state))
    btnShow.OnEvent("Click", LLMConfirmToggleContents.Bind(state))
    confirmGui.OnEvent("Close", LLMConfirmClose.Bind(state))
    confirmGui.OnEvent("Escape", LLMConfirmClose.Bind(state))
    confirmGui.Show("w520 h164")
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
        state.btnSend.Move(236, 420)
        state.btnCancel.Move(328, 420)
        state.btnShow.Move(420, 420)
        state.gui.Show("w520 h464")
    } else {
        state.btnSend.Move(236, 120)
        state.btnCancel.Move(328, 120)
        state.btnShow.Move(420, 120)
        state.gui.Show("w520 h164")
    }
}

LLMConfirmSend(state, *) {
    global _LLMState

    if (state.chkSkip.Value = 1)
        _LLMState.confirmUntilTick := A_TickCount + 3600000

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
    body := LLMCallsBuildRequestBody(systemPrompt, selectedText, &finalSystemPrompt)
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

LLMCallsBuildRequestBody(systemPrompt, selectedText, &finalSystemPrompt := "") {
    global _LLMState
    switch _LLMState.provider {
        case "anthropic":
            return LLMCallsBuildAnthropicBody(systemPrompt, selectedText, &finalSystemPrompt)
    }
    throw Error("Unsupported LLM provider: " _LLMState.provider)
}

LLMCallsBuildAnthropicBody(systemPrompt, selectedText, &finalSystemPrompt := "") {
    global _LLMState

    examples := LLMExamplesBuildPromptSection()
    if (examples != "") {
        if (Trim(systemPrompt) != "")
            systemPrompt .= "`n`n"
        systemPrompt .= examples
    }
    finalSystemPrompt := systemPrompt

    body := '{"model":"' JsonEscape(_LLMState.model) '","max_tokens":' _LLMState.maxTokens ','
    if (Trim(systemPrompt) != "")
        body .= '"system":"' JsonEscape(systemPrompt) '",'
    body .= '"messages":[{"role":"user","content":"' JsonEscape(selectedText) '"}]}'
    return body
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
    try responseText := req.ResponseText
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
    modelEdit := sGui.AddEdit("x140 y50 w280 h24", _LLMState.model)

    sGui.AddText("x12 y90 w120", T("llm_max_tokens"))
    maxTokensEdit := sGui.AddEdit("x140 y88 w90 h24 Number", _LLMState.maxTokens "")

    sGui.AddText("x12 y128 w120", T("llm_timeout_seconds"))
    timeoutEdit := sGui.AddEdit("x140 y126 w90 h24 Number", _LLMState.timeoutSeconds "")

    sGui.AddText("x12 y166 w120", T("llm_example_preface"))
    examplePrefaceEdit := AddStandardBorderEdit(sGui, 140, 164, 520, 86, "Multi WantTab")
    examplePrefaceEdit.Value := _LLMState.examplePreface

    btnApiKey := sGui.AddButton("x12 y270 w170 h30", T("llm_open_api_key"))
    btnSave := sGui.AddButton("x490 y270 w74 h30", T("hotkey_dialog_save"))
    btnClose := sGui.AddButton("x574 y270 w74 h30", T("settings_close"))

    state := {
        gui: sGui,
        providerDDL: providerDDL,
        modelEdit: modelEdit,
        maxTokensEdit: maxTokensEdit,
        timeoutEdit: timeoutEdit,
        examplePrefaceEdit: examplePrefaceEdit
    }
    _LLMState.settingsWindow := state

    btnApiKey.OnEvent("Click", LLMSettingsOpenApiKeyFile.Bind(state))
    btnSave.OnEvent("Click", LLMSettingsSave.Bind(state))
    btnClose.OnEvent("Click", LLMSettingsClose.Bind(state))
    sGui.OnEvent("Close", LLMSettingsClose.Bind(state))
    sGui.OnEvent("Escape", LLMSettingsClose.Bind(state))
    sGui.Show("w680 h312")
}

LLMSettingsOpenApiKeyFile(state, *) {
    keyPath := LLMCallsEnsureApiKeyFile()
    try Run('notepad.exe "' keyPath '"')
    catch
        MsgBox keyPath, T("llm_settings_title")
}

LLMSettingsSave(state, *) {
    global _LLMState

    model := Trim(state.modelEdit.Value)
    if (model != "")
        _LLMState.model := model
    _LLMState.maxTokens := LLMCallsNormalizeMaxTokens(state.maxTokensEdit.Value)
    _LLMState.timeoutSeconds := LLMCallsNormalizeTimeoutSeconds(state.timeoutEdit.Value)
    _LLMState.examplePreface := state.examplePrefaceEdit.Value
    state.maxTokensEdit.Value := _LLMState.maxTokens ""
    state.timeoutEdit.Value := _LLMState.timeoutSeconds ""
    LLMCallsSaveToSettings()
    ShowTransientToolTip(T("msg_settings_saved"))
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
    btnCatDelete := editorGui.AddButton("x123 y418 w95 h30", T("menu_delete_category"))
    btnCatNew := editorGui.AddButton("x22 y454 w196 h30", T("menu_new_category"))

    editorGui.AddGroupBox("x240 y8 w250 h540", "Entries")
    entryList := editorGui.AddListBox("x252 y30 w226 h470")

    editorGui.AddGroupBox("x500 y8 w530 h540", "Entry Editor")
    editorGui.AddText("x514 y30 w500", "Title")
    titleEdit := AddStandardBorderEdit(editorGui, 514, 48, 500, 24)
    editorGui.AddText("x514 y80 w500", T("llm_system_prompt"))
    contentEdit := AddStandardBorderEdit(editorGui, 514, 98, 500, 390, "Multi WantTab")

    btnSave := editorGui.AddButton("x514 y514 w100 h28", "Save")
    btnNew := editorGui.AddButton("x622 y514 w110 h28", "New entry")
    btnDelete := editorGui.AddButton("x740 y514 w100 h28", "Delete")
    btnClose := editorGui.AddButton("x924 y514 w90 h28", "Close")

    state := {
        gui: editorGui,
        categoryList: categoryList,
        entryList: entryList,
        titleEdit: titleEdit,
        contentEdit: contentEdit,
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
}

LLMEditorNew(state, *) {
    state.currentTitle := ""
    try state.entryList.Value := 0
    state.titleEdit.Value := ""
    state.contentEdit.Value := ""
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
    } else if !entries.Has(newTitle) {
        order.Push(newTitle)
    }

    entries[newTitle] := state.contentEdit.Value
    if !LLMCallsSavePromptData() {
        MsgBox "Could not save LLM prompts.", T("llm_prompt_editor_title")
        return
    }
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

    LLMCallsSavePromptData()
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
