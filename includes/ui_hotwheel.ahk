; ---------------------------------------------------------------------
; Hotwheel public entry points.
; Rendering/state/geometry will be split behind this lifecycle boundary.
; ---------------------------------------------------------------------

ShowHotwheel(*) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global _PendingPasteTarget
    global _HotwheelWindowState

    if IsObject(_HotwheelWindowState)
        return

    if !IsTextInputContextActive() {
        ShowTransientToolTip(T("msg_text_context_required"))
        return
    }

    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }

    MouseGetPos &mx, &my
    _PendingPasteTarget := CapturePasteTargetContext()
    state := HotwheelStateCreate(mx, my, _Categories, _EntriesByCategory, _EntryOrderByCategory, _PendingPasteTarget)
    HotwheelRenderOpen(state)
}

HotwheelInputStart(renderState) {
    global ConfiguredHotkey
    if !IsObject(renderState)
        return

    renderState.lastHoveredCategory := renderState.hotwheelState.hoveredCategory
    renderState.lastHoverKind := ""
    renderState.triggerKey := GetHotkeyTriggerKey(ConfiguredHotkey)
    renderState.ignoreKeyboardUntil := A_TickCount + 350
    try Hotkey("*LButton", HotwheelInputLeftClick, "On")
    try Hotkey("*RButton", HotwheelInputRightClick, "On")
    try Hotkey("Esc", HotwheelInputEscape, "On")
    SetTimer(HotwheelInputHoverTick, 30)

    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := HotwheelInputKeyDown
    renderState.inputHook := ih
    try ih.Start()
}

HotwheelInputStop(renderState) {
    SetTimer(HotwheelInputHoverTick, 0)
    try Hotkey("*LButton", HotwheelInputLeftClick, "Off")
    try Hotkey("*RButton", HotwheelInputRightClick, "Off")
    try Hotkey("Esc", HotwheelInputEscape, "Off")

    if IsObject(renderState) && renderState.HasOwnProp("inputHook") && IsObject(renderState.inputHook) {
        try renderState.inputHook.Stop()
        renderState.inputHook := 0
    }
}

HotwheelInputHoverTick() {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if _HotwheelWindowState.refreshing || _HotwheelWindowState.closing
        return

    state := _HotwheelWindowState.hotwheelState
    if !IsObject(state) || !state.isOpen
        return

    oldCategory := state.hoveredCategory
    oldEntryCount := state.viewModel.entrySlices.Length
    MouseGetPos &mx, &my
    target := HotwheelInputTargetAt(_HotwheelWindowState, mx, my)
    HotwheelInputApplyHoverTarget(state, target)
    _HotwheelWindowState.lastHoverKind := target.kind

    if (state.hoveredCategory != oldCategory || state.viewModel.entrySlices.Length != oldEntryCount)
        HotwheelRenderRefresh(_HotwheelWindowState)
}

HotwheelInputLeftClick(*) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return

    MouseGetPos &mx, &my
    state := _HotwheelWindowState.hotwheelState
    target := HotwheelInputTargetAt(_HotwheelWindowState, mx, my)
    outcome := HotwheelStateResolveLeftClick(state, target)
    HotwheelRenderClose()
    HotwheelExecuteOutcome(outcome)
}

HotwheelInputRightClick(*) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if IsObject(_HotwheelWindowState.hotwheelState)
        HotwheelStateClose(_HotwheelWindowState.hotwheelState, HotwheelCloseReason("right_click"))
    HotwheelRenderClose()
}

HotwheelInputEscape(*) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if IsObject(_HotwheelWindowState.hotwheelState)
        HotwheelStateClose(_HotwheelWindowState.hotwheelState, HotwheelCloseReason("escape"))
    HotwheelRenderClose()
}

HotwheelInputKeyDown(ih, vk, sc) {
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (keyName = "Escape" || keyName = "Esc") {
        HotwheelInputEscape()
        return
    }

    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if HotwheelInputShouldIgnoreKey(_HotwheelWindowState, keyName)
        return
    if IsObject(_HotwheelWindowState.hotwheelState)
        HotwheelStateClose(_HotwheelWindowState.hotwheelState, HotwheelCloseReason("unrelated_key"))
    HotwheelRenderClose()
}

HotwheelInputShouldIgnoreKey(renderState, keyName) {
    if (keyName = "")
        return true
    if (A_TickCount < renderState.ignoreKeyboardUntil)
        return true
    if (renderState.HasOwnProp("triggerKey") && keyName = renderState.triggerKey)
        return true
    if IsModifierKeyName(keyName)
        return true
    return false
}

HotwheelExecuteOutcome(outcome) {
    global _PendingPasteTarget
    if !IsObject(outcome)
        return

    switch outcome.action {
        case "paste":
            _PendingPasteTarget := outcome.pasteTarget
            PasteSnippet(outcome.category, outcome.title)
        case "settings":
            OpenSettingsWindow()
        case "root_menu":
            ShowSnippetMenu()
    }
}

HotwheelInputTargetAt(renderState, x, y) {
    target := HotwheelRenderTargetFromPoint(renderState, x, y)
    if IsObject(target)
        return target
    return HotwheelStateTargetFromPoint(renderState.hotwheelState, x, y)
}

HotwheelInputApplyHoverTarget(state, target) {
    state.hoverTarget := target

    nextHovered := ""
    if (target.kind = "category")
        nextHovered := target.category
    else if (target.kind = "entry")
        nextHovered := target.category

    if (nextHovered != state.hoveredCategory) {
        state.hoveredCategory := nextHovered
        HotwheelStateRebuildView(state)
    } else {
        state.viewModel := HotwheelStateBuildViewModel(state)
    }
}
