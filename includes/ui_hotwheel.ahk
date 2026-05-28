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
    HotwheelDebugLog("ShowHotwheel opening at " mx "," my " direction=" state.layout.direction " outerR=" state.layout.config.outerRadius)
    for i, slice in state.layout.categorySlices
        HotwheelDebugLog("  slice[" i "] cat=" slice.category " start=" Round(slice.rawStartDeg,1) " end=" Round(slice.rawEndDeg,1))
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
    renderState.ignoreMouseUntil := A_TickCount + 400
    renderState.heldVKsAtOpen := HotwheelSnapshotHeldVKs(renderState.triggerKey)
    try Hotkey("*LButton", HotwheelInputLeftClick, "On")
    try Hotkey("*RButton", HotwheelInputRightClick, "On")
    try Hotkey("Esc", HotwheelInputEscape, "On")
    SetTimer(HotwheelInputHoverTick, 30)

    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := HotwheelInputKeyDown
    ih.OnKeyUp := HotwheelInputKeyUp
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

    ; Debug: log angle and hit target on every hover tick
    layout := state.layout
    dx := mx - layout.centerX
    dy := my - layout.centerY
    radius := Round(Sqrt(dx*dx + dy*dy), 1)
    angle  := HotwheelPointAngle(dx, dy)
    HotwheelDebugLog("hover mx=" mx " my=" my " cx=" layout.centerX " cy=" layout.centerY
        " dir=" layout.direction " dx=" dx " dy=" dy
        " r=" radius " a=" Round(angle, 1)
        " outerR=" layout.config.outerRadius
        " target.kind=" target.kind " target.cat=" (target.HasOwnProp("category") ? target.category : ""))

    HotwheelInputApplyHoverTarget(state, target)
    _HotwheelWindowState.lastHoverKind := target.kind

    ToolTip("a=" Round(angle,1) " r=" Round(radius) " → " target.kind " " (target.HasOwnProp("category") ? target.category : ""))

    if (state.hoveredCategory != oldCategory || state.viewModel.entrySlices.Length != oldEntryCount)
        HotwheelRenderRefresh(_HotwheelWindowState)
}

HotwheelInputLeftClick(*) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if (_HotwheelWindowState.HasOwnProp("ignoreMouseUntil") && A_TickCount < _HotwheelWindowState.ignoreMouseUntil) {
        HotwheelDebugLog("LButton suppressed by mouse grace window")
        return
    }

    MouseGetPos &mx, &my
    state := _HotwheelWindowState.hotwheelState
    target := HotwheelInputTargetAt(_HotwheelWindowState, mx, my)
    outcome := HotwheelStateResolveLeftClick(state, target)
    HotwheelDebugLog("LButton close at " mx "," my " target.kind=" target.kind " outcome.action=" (IsObject(outcome) ? outcome.action : "none"))
    HotwheelRenderClose()
    HotwheelExecuteOutcome(outcome)
}

HotwheelInputRightClick(*) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if (_HotwheelWindowState.HasOwnProp("ignoreMouseUntil") && A_TickCount < _HotwheelWindowState.ignoreMouseUntil) {
        HotwheelDebugLog("RButton suppressed by mouse grace window")
        return
    }
    HotwheelDebugLog("RButton close")
    if IsObject(_HotwheelWindowState.hotwheelState)
        HotwheelStateClose(_HotwheelWindowState.hotwheelState, HotwheelCloseReason("right_click"))
    HotwheelRenderClose()
}

HotwheelInputEscape(*) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    HotwheelDebugLog("Escape close")
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
    if (_HotwheelWindowState.HasOwnProp("heldVKsAtOpen") && _HotwheelWindowState.heldVKsAtOpen.Has(vk))
        return
    if HotwheelInputShouldIgnoreKey(_HotwheelWindowState, keyName)
        return
    HotwheelDebugLog("KeyDown close, key=" keyName " vk=" vk)
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

HotwheelSnapshotHeldVKs(triggerKey) {
    held := Map()
    ; Modifier VK codes + both generic and L/R variants
    vksToCheck := [0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]
    if (triggerKey != "") {
        try {
            tvk := GetKeyVK(triggerKey)
            if tvk
                vksToCheck.Push(tvk)
        }
    }
    for _, vk in vksToCheck {
        if GetKeyState(Format("vk{:02x}", vk), "P")
            held[vk] := true
    }
    return held
}

HotwheelInputKeyUp(ih, vk, sc) {
    global _HotwheelWindowState
    if IsObject(_HotwheelWindowState) && _HotwheelWindowState.HasOwnProp("heldVKsAtOpen")
        _HotwheelWindowState.heldVKsAtOpen.Delete(vk)
}

HotwheelDebugLog(msg) {
    ; Compiled exe lives in dist\; source lives at project root — resolve to project root either way.
    projectRoot := A_IsCompiled ? A_ScriptDir "\.." : A_ScriptDir
    logDir  := projectRoot "\debug"
    logPath := logDir "\hotwheel_debug.log"
    try DirCreate(logDir)
    try FileAppend(FormatTime(, "HH:mm:ss.") SubStr(A_TickCount, -2) " " msg "`n", logPath)
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
