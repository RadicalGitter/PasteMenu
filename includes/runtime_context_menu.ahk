ShowTransientToolTip(message, timeoutMs := 1400) {
    ToolTip message
    SetTimer(ClearTransientToolTip, -timeoutMs)
}

; Deletes or removes clear transient tool tip.
ClearTransientToolTip() {
    ToolTip
}

; Checks whether is text input context active.
IsTextInputContextActive(invocation := 0) {
    activeHwnd := IsObject(invocation) && invocation.HasOwnProp("activeHwnd") ? invocation.activeHwnd : WinActive("A")
    if !activeHwnd
        return false

    if IsCaretVisible() {
        RememberTextContext(activeHwnd)
        return true
    }

    ; LLM document capture is a valid menu context even without a caret.
    ; Keep this check cheap: no clipboard, no COM, no document parsing.
    if LLMDocIsActiveDocumentContext(activeHwnd) {
        RememberTextContext(activeHwnd)
        return true
    }

    focusedCtrl := ""
    try focusedCtrl := ControlGetFocus("ahk_id " activeHwnd)
    if (focusedCtrl != "") {
        ctrlHwnd := 0
        try ctrlHwnd := ControlGetHwnd(focusedCtrl, "ahk_id " activeHwnd)
        if ctrlHwnd {
            ctrlClass := ""
            try ctrlClass := WinGetClass("ahk_id " ctrlHwnd)

            if IsLikelyTextControlClass(ctrlClass) {
                RememberTextContext(activeHwnd)
                return true
            }
            if HasTextSelectionInControl(ctrlHwnd, ctrlClass) {
                RememberTextContext(activeHwnd)
                return true
            }
        }
    }

    ; If this window was recently confirmed as text context, allow mouse-bound hotkeys
    ; even when pointer is no longer above the text field.
    if IsRecentTextContextWindow(activeHwnd) {
        RememberTextContext(activeHwnd)
        return true
    }

    ; Fallback for custom-rendered text fields (browser/Electron/etc):
    ; if mouse is over the active window and cursor is/recently was IBeam, treat as text context.
    if IsObject(invocation) && invocation.HasOwnProp("mouseWin") {
        mouseWin := invocation.mouseWin
        mouseCtrl := invocation.HasOwnProp("mouseCtrl") ? invocation.mouseCtrl : 0
        cursor := invocation.HasOwnProp("cursor") ? invocation.cursor : A_Cursor
    } else {
        MouseGetPos ,, &mouseWin, &mouseCtrl, 2
        cursor := A_Cursor
    }
    if (mouseWin && WindowsShareRootWindow(activeHwnd, mouseWin)) {
        if (cursor = "IBeam") {
            RememberTextContext(activeHwnd)
            return true
        }
        if IsRecentIBeamOnWindow(activeHwnd) {
            RememberTextContext(activeHwnd)
            return true
        }

        if mouseCtrl {
            mouseClass := ""
            try mouseClass := WinGetClass("ahk_id " mouseCtrl)
            if IsLikelyTextControlClass(mouseClass) {
                RememberTextContext(activeHwnd)
                return true
            }
        }
    }

    return false
}

; Handles remember text context.
RememberTextContext(hwnd) {
    global _TextContextState
    if !hwnd
        return
    _TextContextState.lastTick := A_TickCount
    _TextContextState.lastRoot := GetRootWindow(hwnd)
}

; Checks whether is recent text context window.
IsRecentTextContextWindow(hwnd, maxAgeMs := 10000) {
    global _TextContextState
    if !IsObject(_TextContextState)
        return false
    if (_TextContextState.lastTick = 0)
        return false
    if (A_TickCount - _TextContextState.lastTick > maxAgeMs)
        return false
    return (_TextContextState.lastRoot = GetRootWindow(hwnd))
}

; Captures the invocation surface before the tap/hold delay and before any menu exists.
CaptureMenuInvocationContext() {
    MouseGetPos &mx, &my, &mouseWin, &mouseCtrl, 2
    activeHwnd := WinActive("A")
    return {
        activeHwnd: activeHwnd,
        mouseX: mx,
        mouseY: my,
        mouseWin: mouseWin,
        mouseCtrl: mouseCtrl,
        cursor: A_Cursor,
        pasteTarget: CapturePasteTargetContext(activeHwnd)
    }
}

; Handles capture paste target context.
CapturePasteTargetContext(activeHwnd := 0) {
    if !activeHwnd
        activeHwnd := WinActive("A")
    if !activeHwnd
        return 0

    focusedCtrl := ""
    ctrlHwnd := 0
    try focusedCtrl := ControlGetFocus("ahk_id " activeHwnd)
    if (focusedCtrl != "") {
        try ctrlHwnd := ControlGetHwnd(focusedCtrl, "ahk_id " activeHwnd)
    }

    return {
        win: activeHwnd,
        ctrlName: focusedCtrl,
        ctrlHwnd: ctrlHwnd
    }
}

; Handles focus paste target.
FocusPasteTarget(target) {
    if !IsObject(target)
        return false
    if !target.HasOwnProp("win") || !target.win
        return false
    if !WinExist("ahk_id " target.win)
        return false

    try WinActivate("ahk_id " target.win)
    try WinWaitActive("ahk_id " target.win, , 0.35)

    if target.HasOwnProp("ctrlName") && (target.ctrlName != "") {
        try ControlFocus(target.ctrlName, "ahk_id " target.win)
    }

    Sleep 30
    return true
}

; Handles send paste to target.
SendPasteToTarget(target) {
    if IsObject(target) {
        if target.HasOwnProp("ctrlName") && (target.ctrlName != "") {
            try {
                ControlSend("^v", target.ctrlName, "ahk_id " target.win)
                return
            }
        }
    }
    Send "^v"
}

; Updates update pointer context.
UpdatePointerContext() {
    global _PointerContext
    MouseGetPos ,, &mouseWin
    if !mouseWin
        return
    if (A_Cursor != "IBeam")
        return

    _PointerContext.lastIBeamTick := A_TickCount
    _PointerContext.lastIBeamRoot := GetRootWindow(mouseWin)
    RememberTextContext(mouseWin)
}

; Checks whether is recent i beam on window.
IsRecentIBeamOnWindow(hwnd, maxAgeMs := 900) {
    global _PointerContext
    if !IsObject(_PointerContext)
        return false
    if (_PointerContext.lastIBeamTick = 0)
        return false
    if (A_TickCount - _PointerContext.lastIBeamTick > maxAgeMs)
        return false
    return (_PointerContext.lastIBeamRoot = GetRootWindow(hwnd))
}

; Handles windows share root window.
WindowsShareRootWindow(hwndA, hwndB) {
    if (!hwndA || !hwndB)
        return false
    return (GetRootWindow(hwndA) = GetRootWindow(hwndB))
}

; Returns or computes get root window.
GetRootWindow(hwnd) {
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") ; GA_ROOT
    return root ? root : hwnd
}

; Checks whether is caret visible.
IsCaretVisible() {
    x := 0
    y := 0
    try return CaretGetPos(&x, &y)
    return false
}

; Checks whether is likely text control class.
IsLikelyTextControlClass(className) {
    if (className = "")
        return false
    return RegExMatch(
        className,
        "i)^(Edit|RICHEDIT\d*\w*|RichEdit\d*\w*|Scintilla\d*|WindowsForms10\.EDIT.*|Chrome_AutocompleteEditView|TEdit|TMemo)$"
    )
}

; Checks whether has text selection in control.
HasTextSelectionInControl(ctrlHwnd, className := "") {
    if !ctrlHwnd
        return false

    if (className = "") {
        try className := WinGetClass("ahk_id " ctrlHwnd)
    }

    if !RegExMatch(className, "i)^(Edit|RICHEDIT\d*\w*|RichEdit\d*\w*|WindowsForms10\.EDIT.*)$")
        return false

    try {
        sel := SendMessage(0x00B0, 0, 0, , "ahk_id " ctrlHwnd) ; EM_GETSEL
        selStart := sel & 0xFFFF
        selEnd := (sel >> 16) & 0xFFFF
        return (selEnd > selStart)
    }
    return false
}

; Initializes or controls start menu outside click watcher.
StartMenuOutsideClickWatcher() {
    global _MenuAutoCloseState
    _MenuAutoCloseState := {
        rDown: GetKeyState("RButton", "P"),
        mDown: GetKeyState("MButton", "P"),
        mouseHotkeys: Map(),
        keyHook: 0
    }
    MenuRegisterOutsideMouseHotkeys()
    MenuStartKeyboardCloseHook()
    SetTimer(MenuOutsideClickWatcherTick, 25)
}

; Initializes or controls stop menu outside click watcher.
StopMenuOutsideClickWatcher() {
    global _MenuAutoCloseState
    SetTimer(MenuOutsideClickWatcherTick, 0)
    MenuUnregisterOutsideMouseHotkeys()
    if IsObject(_MenuAutoCloseState) && IsObject(_MenuAutoCloseState.keyHook) {
        try _MenuAutoCloseState.keyHook.Stop()
        _MenuAutoCloseState.keyHook := 0
    }
    _MenuAutoCloseState := 0
}

; Registers mouse buttons that should close an open menu when clicked outside it.
MenuRegisterOutsideMouseHotkeys() {
    global _MenuAutoCloseState
    if !IsObject(_MenuAutoCloseState)
        return

    hooks := Map()
    mouseKeys := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelUp", "WheelDown"]
    for _, keyName in mouseKeys {
        hkName := "~*" keyName
        fn := MenuOutsideMouseClickHotkey.Bind(keyName)
        try {
            Hotkey(hkName, fn, "On")
            hooks[hkName] := fn
        }
    }
    _MenuAutoCloseState.mouseHotkeys := hooks
}

; Removes temporary menu mouse close hotkeys.
MenuUnregisterOutsideMouseHotkeys() {
    global _MenuAutoCloseState
    if !IsObject(_MenuAutoCloseState)
        return
    if !IsObject(_MenuAutoCloseState.mouseHotkeys)
        return

    for hkName, _ in _MenuAutoCloseState.mouseHotkeys {
        try Hotkey(hkName, "Off")
    }
    _MenuAutoCloseState.mouseHotkeys := Map()
}

; Starts a temporary keyboard hook that closes menus on non-modifier keys.
MenuStartKeyboardCloseHook() {
    global _MenuAutoCloseState
    if !IsObject(_MenuAutoCloseState)
        return

    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := MenuOutsideKeyDown
    _MenuAutoCloseState.keyHook := ih
    try ih.Start()
}

; Handles menu outside mouse click hotkey.
MenuOutsideMouseClickHotkey(keyName, *) {
    if !WinExist("ahk_class #32768")
        return

    MouseGetPos ,, &targetHwnd
    if (targetHwnd && IsMenuWindowOrChild(targetHwnd))
        return

    DllCall("EndMenu")
}

; Handles keyboard input while a native menu is open.
MenuOutsideKeyDown(ih, vk, sc) {
    if !WinExist("ahk_class #32768")
        return

    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if IsMenuCloseIgnoredKey(keyName)
        return

    DllCall("EndMenu")
}

; Returns true for modifiers that should not close the menu by themselves.
IsMenuCloseIgnoredKey(keyName) {
    if IsModifierKeyName(keyName)
        return true
    return (keyName = "LWin" || keyName = "RWin")
}

; Handles menu outside click watcher tick.
MenuOutsideClickWatcherTick() {
    global _MenuAutoCloseState
    if !IsObject(_MenuAutoCloseState)
        return

    if !WinExist("ahk_class #32768")
        return

    rNow := GetKeyState("RButton", "P")
    mNow := GetKeyState("MButton", "P")

    newClick := (rNow && !_MenuAutoCloseState.rDown)
        || (mNow && !_MenuAutoCloseState.mDown)

    _MenuAutoCloseState.rDown := rNow
    _MenuAutoCloseState.mDown := mNow

    if !newClick
        return

    MouseGetPos ,, &targetHwnd
    if (targetHwnd && IsMenuWindowOrChild(targetHwnd))
        return

    DllCall("EndMenu")
}

; Checks whether is menu window or child.
IsMenuWindowOrChild(hwnd) {
    current := hwnd
    while current {
        className := ""
        try className := WinGetClass("ahk_id " current)
        if (className = "#32768")
            return true
        current := DllCall("GetParent", "Ptr", current, "Ptr")
    }
    return false
}

; Sets or applies set selected menu entry.
SetSelectedMenuEntry(category, title) {
    global _SelectedMenuCategory, _SelectedMenuTitle
    _SelectedMenuCategory := category
    _SelectedMenuTitle := title
}

; Sets the most recently pasted entry.
SetLastSelectedMenuEntry(category, title) {
    global _LastSelectedMenuCategory, _LastSelectedMenuTitle
    _LastSelectedMenuCategory := category
    _LastSelectedMenuTitle := title
}

; Checks whether is entry pinned.
IsEntryPinned(category, title) {
    global ShowSelectedNearClick, _SelectedMenuCategory, _SelectedMenuTitle
    if !ShowSelectedNearClick
        return false
    if (category = "" || title = "")
        return false
    return (_SelectedMenuCategory = category && _SelectedMenuTitle = title)
}

; Returns or computes get selected entry for menu.
GetSelectedEntryForMenu(&category, &title) {
    global ShowSelectedNearClick, _SelectedMenuCategory, _SelectedMenuTitle
    global _EntriesByCategory

    if !ShowSelectedNearClick
        return false

    category := _SelectedMenuCategory
    title := _SelectedMenuTitle
    if (category = "" || title = "")
        return false
    if !_EntriesByCategory.Has(category)
        return false
    if !_EntriesByCategory[category].Has(title)
        return false
    return true
}

; Returns the most recently pasted entry for root-menu shortcuts.
GetLastSelectedEntryForMenu(&category, &title) {
    global _LastSelectedMenuCategory, _LastSelectedMenuTitle
    global _EntriesByCategory

    category := _LastSelectedMenuCategory
    title := _LastSelectedMenuTitle
    if (category = "" || title = "")
        return false
    if !_EntriesByCategory.Has(category) || !_EntriesByCategory[category].Has(title) {
        _LastSelectedMenuCategory := ""
        _LastSelectedMenuTitle := ""
        return false
    }
    return true
}

; Builds pinned + last-selected shortcuts for the root menu.
GetRootShortcutEntries() {
    entries := []

    if GetSelectedEntryForMenu(&pinnedCategory, &pinnedTitle) {
        entries.Push({
            category: pinnedCategory,
            title: pinnedTitle,
            label: T("menu_selected_entry") ": " pinnedTitle
        })
    }

    if GetLastSelectedEntryForMenu(&lastCategory, &lastTitle) {
        isDuplicate := false
        for _, item in entries {
            if (item.category = lastCategory && item.title = lastTitle) {
                isDuplicate := true
                break
            }
        }
        if !isDuplicate {
            entries.Push({
                category: lastCategory,
                title: lastTitle,
                label: T("menu_last_selected_entry") ": " lastTitle
            })
        }
    }

    return entries
}

; Adds root shortcut entries (pinned + last selected).
AddRootShortcutSection(mainMenu, shortcutEntries) {
    if !IsObject(shortcutEntries) || (shortcutEntries.Length = 0)
        return false

    for _, item in shortcutEntries
        mainMenu.Add(item.label, PasteSnippet.Bind(item.category, item.title))
    return true
}

; Adds secondary root actions such as script tools and editors.
AddRootSecondaryActionsSection(mainMenu, scriptActionMode := "run") {
    scriptLabel := (scriptActionMode = "paste") ? T("menu_paste_script_text") : T("menu_run_script")

    secondaryActions := []
    if (scriptActionMode != "paste" || ScriptRunnerIsEnabled())
        secondaryActions.Push([scriptLabel, ScriptRunnerBuildMenu(scriptActionMode, true)])
    secondaryActions.Push([T("menu_new_category"), RootNewCategoryMenuAction])
    secondaryActions.Push([T("menu_entry_editor"), RootEntryEditorMenuAction])
    AddRootActionItems(mainMenu, secondaryActions)
    return true
}

; Adds primary root actions.
AddRootPrimaryActionsSection(mainMenu) {
    primaryActions := [
        [T("menu_close"), RootCloseMenuAction],
        [T("menu_open_settings"), OpenSettingsWindow]
    ]
    AddRootActionItems(mainMenu, primaryActions)
    return true
}

; Adds a list of `[label, handler]` action tuples to a menu.
AddRootActionItems(menuObj, actions) {
    for _, item in actions
        menuObj.Add(item[1], item[2])
}

; Adds root menu sections with separators only between visible sections.
AddRootMenuSections(mainMenu, openUpward, shortcutEntries, scriptActionMode := "paste") {
    sections := ["shortcuts", "categories", "llm", "secondary_actions", "primary_actions"]
    if openUpward
        sections := ReverseArray(sections)

    hasAnySection := false
    for _, sectionName in sections {
        if !IsRootMenuSectionVisible(sectionName, shortcutEntries, scriptActionMode)
            continue

        if hasAnySection
            mainMenu.Add()
        AddRootMenuNamedSection(mainMenu, sectionName, shortcutEntries, scriptActionMode)
        hasAnySection := true
    }
}

; Returns whether a root menu section should be rendered.
IsRootMenuSectionVisible(sectionName, shortcutEntries, scriptActionMode := "paste") {
    switch sectionName {
        case "shortcuts":
            return IsObject(shortcutEntries) && shortcutEntries.Length > 0
        default:
            return true
    }
}

; Adds one named root menu section.
AddRootMenuNamedSection(mainMenu, sectionName, shortcutEntries, scriptActionMode := "paste") {
    switch sectionName {
        case "shortcuts":
            AddRootShortcutSection(mainMenu, shortcutEntries)
        case "categories":
            AddRootCategorySections(mainMenu)
        case "llm":
            AddLLMCallsRootSection(mainMenu)
        case "secondary_actions":
            AddRootSecondaryActionsSection(mainMenu, scriptActionMode)
        case "primary_actions":
            AddRootPrimaryActionsSection(mainMenu)
    }
}

; Returns a reversed shallow copy of an array.
ReverseArray(arr) {
    out := []
    idx := arr.Length
    while (idx >= 1) {
        out.Push(arr[idx])
        idx -= 1
    }
    return out
}

; Adds all normal paste categories as one root menu section.
AddRootCategorySections(mainMenu) {
    global _Categories, _EntryOrderByCategory

    for _, category in _Categories
        mainMenu.Add(category, BuildPasteCategorySubmenu(category))
}

; Builds the submenu for a normal paste category.
BuildPasteCategorySubmenu(category) {
    global _EntryOrderByCategory

    sub := Menu()
    order := _EntryOrderByCategory[category]

    if (order.Length = 0) {
        sub.Add(T("menu_empty_category"), NoOp)
    } else {
        for _, title in order
            sub.Add(title, PasteSnippet.Bind(category, title))
    }

    sub.Add()
    sub.Add(T("menu_quick_new_entry"), QuickNewEntryMenuAction.Bind(category))

    editSub := Menu()
    editSub.Add(T("menu_new_entry"), NewEntryMenuAction.Bind(category))
    editSub.Add(T("menu_rename"), RenameCategoryMenuAction.Bind(category))
    editSub.Add(T("menu_delete_category"), DeleteCategoryMenuAction.Bind(category))
    sub.Add(T("menu_edit_category"), editSub)
    return sub
}

; Returns or computes get work area for point.
GetWorkAreaForPoint(x, y, &left, &top, &right, &bottom) {
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
        if (x >= mLeft && x < mRight && y >= mTop && y < mBottom) {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            return
        }
    }
    left := 0
    top := 0
    right := A_ScreenWidth
    bottom := A_ScreenHeight
}

; Builds menu layout counts used by placement heuristics.
BuildRootMenuLayoutMetrics(categoryCount, shortcutCount := 0, scriptActionMode := "paste") {
    return {
        categoryCount: categoryCount,
        shortcutCount: shortcutCount,
        scriptRows: EstimateRootScriptRows(scriptActionMode),
        actionRows: EstimateRootActionRows(scriptActionMode),
        llmRows: 1,
        baseSeparators: 3,
        shortcutSeparators: shortcutCount > 0 ? 1 : 0
    }
}

; Counts script-runner root rows in the current menu mode.
EstimateRootScriptRows(scriptActionMode := "paste") {
    return (scriptActionMode != "paste" || ScriptRunnerIsEnabled()) ? 1 : 0
}

; Counts non-category action rows added by root action sections.
EstimateRootActionRows(scriptActionMode := "paste") {
    ; Close, settings, new category, and entry editor are always present.
    return 4 + EstimateRootScriptRows(scriptActionMode)
}

; Estimates root menu rows from explicit layout metrics.
EstimateRootMenuRows(metrics) {
    rows := metrics.categoryCount
    rows += metrics.shortcutCount
    rows += metrics.actionRows
    rows += metrics.llmRows
    rows += metrics.baseSeparators
    rows += metrics.shortcutSeparators
    return rows
}

; Estimates native root menu height in pixels.
EstimateRootMenuHeight(metrics) {
    rowHeight := GetEstimatedMenuRowHeight()
    borderPadding := GetEstimatedMenuVerticalPadding()
    return (EstimateRootMenuRows(metrics) * rowHeight) + borderPadding
}

; Returns the estimated native menu row height for the active DPI.
GetEstimatedMenuRowHeight() {
    h := DllCall("GetSystemMetrics", "Int", 15, "Int") ; SM_CYMENU
    if (h < 18 || h > 60)
        h := 24
    return h
}

; Returns a conservative vertical padding estimate for native popup menus.
GetEstimatedMenuVerticalPadding() {
    edge := DllCall("GetSystemMetrics", "Int", 46, "Int") ; SM_CYEDGE
    if (edge < 1 || edge > 8)
        edge := 2
    return (edge * 2) + 10
}

; Returns minimum gap to keep between estimated menu bounds and work-area edges.
GetMenuEdgePaddingPx() {
    return 12
}

; Returns how much better the upward fit must be before flipping direction.
GetMenuDirectionHysteresisPx() {
    return Max(GetEstimatedMenuRowHeight(), 24)
}

; Builds all placement facts for a menu opened at a screen point.
GetRootMenuPlacementInfo(mouseX, mouseY, metrics) {
    GetWorkAreaForPoint(mouseX, mouseY, &waLeft, &waTop, &waRight, &waBottom)
    padding := GetMenuEdgePaddingPx()
    neededHeight := EstimateRootMenuHeight(metrics)
    spaceBelow := Max(0, waBottom - padding - mouseY)
    spaceAbove := Max(0, mouseY - (waTop + padding))

    return {
        workLeft: waLeft,
        workTop: waTop,
        workRight: waRight,
        workBottom: waBottom,
        neededHeight: neededHeight,
        spaceBelow: spaceBelow,
        spaceAbove: spaceAbove,
        fitsBelow: spaceBelow >= neededHeight,
        fitsAbove: spaceAbove >= neededHeight
    }
}

; Decides whether the root menu should be assembled for upward opening.
ShouldOpenRootMenuUpward(mouseX, mouseY, metrics) {
    info := GetRootMenuPlacementInfo(mouseX, mouseY, metrics)

    if info.fitsBelow && !info.fitsAbove
        return false
    if info.fitsAbove && !info.fitsBelow
        return true
    if info.fitsBelow && info.fitsAbove
        return false

    return (info.spaceAbove - info.spaceBelow) > GetMenuDirectionHysteresisPx()
}

; Backward-compatible wrapper for older call sites/tests.
MenuLikelyOpensUpward(mouseX, mouseY, categoryCount, shortcutCount := 0) {
    metrics := BuildRootMenuLayoutMetrics(categoryCount, shortcutCount, "paste")
    return ShouldOpenRootMenuUpward(mouseX, mouseY, metrics)
}

; Opens or shows show snippet menu.
ShowSnippetMenu(invocation := 0, *) {
    global SnippetFile, SnippetEncoding, DefaultCategory
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global _PendingPasteTarget

    isTextContext := IsTextInputContextActive(invocation)
    isFolderContext := ScriptRunnerIsFolderContextActive(&folderContextPath)

    if !isTextContext && !isFolderContext {
        ShowTransientToolTip(T("msg_text_or_folder_context_required"))
        return
    }

    if IsObject(invocation) && invocation.HasOwnProp("mouseX") {
        mx := invocation.mouseX
        my := invocation.mouseY
    } else {
        MouseGetPos &mx, &my
    }

    if (isFolderContext && !isTextContext) {
        _PendingPasteTarget := 0
        ScriptRunnerSetInvocationFolder(folderContextPath)
        mainMenu := ScriptRunnerBuildMenu("run", false)
        StartMenuOutsideClickWatcher()
        try {
            mainMenu.Show(mx, my)
        } finally {
            StopMenuOutsideClickWatcher()
        }
        return
    }

    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }

    ScriptRunnerSetInvocationFolder("")
    _PendingPasteTarget := IsObject(invocation) && invocation.HasOwnProp("pasteTarget") ? invocation.pasteTarget : CapturePasteTargetContext()
    if IsObject(_PendingPasteTarget)
        _PendingPasteTarget.docContext := LLMDocDetectContext(_PendingPasteTarget)
    shortcutEntries := GetRootShortcutEntries()
    placementMetrics := BuildRootMenuLayoutMetrics(_Categories.Length, shortcutEntries.Length, "paste")
    openUpward := ShouldOpenRootMenuUpward(mx, my, placementMetrics)

    mainMenu := Menu()
    AddRootMenuSections(mainMenu, openUpward, shortcutEntries, "paste")

    if IsObject(_PendingPasteTarget) && _PendingPasteTarget.HasOwnProp("docContext") && IsObject(_PendingPasteTarget.docContext)
        LLMDocIndicatorShow(_PendingPasteTarget.docContext, mx, my)

    StartMenuOutsideClickWatcher()
    try {
        mainMenu.Show(mx, my)
    } finally {
        StopMenuOutsideClickWatcher()
        LLMDocIndicatorHide()
    }
}

; Handles no op.
NoOp(*) {
}

; Handles root new category menu action.
RootNewCategoryMenuAction(*) {
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global SnippetFile, SnippetEncoding

    result := InputBox("Name for new category:", "New Category")
    if (result.Result != "OK")
        return

    name := Trim(result.Value)
    if (name = "") {
        MsgBox "Category name kan inte vara tomt."
        return
    }

    if _EntriesByCategory.Has(name) {
        MsgBox "Category finns redan: " name
        OpenCategoryEditor(name)
        return
    }

    _Categories.Push(name)
    _EntriesByCategory[name] := Map()
    _EntryOrderByCategory[name] := []

    if !SaveSnippetsToFile(SnippetFile, SnippetEncoding) {
        MsgBox "Kunde inte spara till fil:`n" SnippetFile
        return
    }

    OpenCategoryEditor(name, "", true)
}

; Handles root entry editor menu action.
RootEntryEditorMenuAction(*) {
    TrayOpenEditorAction()
}

; Handles root close menu action.
RootCloseMenuAction(*) {
    ; Menyn stangs automatiskt nar en item klickas.
    return
}

; Handles quick new entry menu action.
QuickNewEntryMenuAction(category, *) {
    OpenQuickNewEntryDialog(category)
}

; Opens or shows open quick new entry dialog.
