ShowTransientToolTip(message, timeoutMs := 1400) {
    ToolTip message
    SetTimer(ClearTransientToolTip, -timeoutMs)
}

; Deletes or removes clear transient tool tip.
ClearTransientToolTip() {
    ToolTip
}

; Checks whether is text input context active.
IsTextInputContextActive() {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return false

    if IsCaretVisible() {
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
    MouseGetPos ,, &mouseWin, &mouseCtrl, 2
    if (mouseWin && WindowsShareRootWindow(activeHwnd, mouseWin)) {
        if (A_Cursor = "IBeam") {
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

; Handles capture paste target context.
CapturePasteTargetContext() {
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
        mDown: GetKeyState("MButton", "P")
    }
    try Hotkey("~*LButton", MenuOutsideLeftClickHotkey, "On")
    SetTimer(MenuOutsideClickWatcherTick, 25)
}

; Initializes or controls stop menu outside click watcher.
StopMenuOutsideClickWatcher() {
    global _MenuAutoCloseState
    SetTimer(MenuOutsideClickWatcherTick, 0)
    try Hotkey("~*LButton", MenuOutsideLeftClickHotkey, "Off")
    _MenuAutoCloseState := 0
}

; Handles menu outside left click hotkey.
MenuOutsideLeftClickHotkey(*) {
    if !WinExist("ahk_class #32768")
        return

    MouseGetPos ,, &targetHwnd
    if (targetHwnd && IsMenuWindowOrChild(targetHwnd))
        return

    DllCall("EndMenu")
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

; Adds root shortcut entries (pinned + last selected), with separator handling.
AddRootShortcutSection(mainMenu, nearTop, shortcutEntries) {
    if !IsObject(shortcutEntries) || (shortcutEntries.Length = 0)
        return false

    if nearTop {
        for _, item in shortcutEntries
            mainMenu.Add(item.label, PasteSnippet.Bind(item.category, item.title))
        mainMenu.Add()
    } else {
        mainMenu.Add()
        for _, item in shortcutEntries
            mainMenu.Add(item.label, PasteSnippet.Bind(item.category, item.title))
    }
    return true
}

; Handles add far root actions section.
AddFarRootActionsSection(mainMenu, openUpward, scriptActionMode := "run") {
    scriptLabel := (scriptActionMode = "paste") ? T("menu_paste_script_text") : T("menu_run_script")

    primaryActions := [
        [T("menu_close"), RootCloseMenuAction],
        [T("menu_open_settings"), OpenSettingsWindow]
    ]
    secondaryActions := []
    if (scriptActionMode != "paste" || ScriptRunnerIsEnabled())
        secondaryActions.Push([scriptLabel, ScriptRunnerBuildMenu(scriptActionMode, true)])
    secondaryActions.Push([T("menu_new_category"), RootNewCategoryMenuAction])
    secondaryActions.Push([T("menu_entry_editor"), RootEntryEditorMenuAction])

    if openUpward {
        AddRootActionItems(mainMenu, primaryActions)
        mainMenu.Add()
        AddRootActionItems(mainMenu, secondaryActions)
        mainMenu.Add()
    } else {
        mainMenu.Add()
        AddRootActionItems(mainMenu, secondaryActions)
        mainMenu.Add()
        AddRootActionItems(mainMenu, primaryActions)
    }
}

; Adds a list of `[label, handler]` action tuples to a menu.
AddRootActionItems(menuObj, actions) {
    for _, item in actions
        menuObj.Add(item[1], item[2])
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

; Handles estimate root menu height.
EstimateRootMenuHeight(categoryCount, shortcutCount := 0) {
    scriptRows := ScriptRunnerIsEnabled() ? 1 : 0
    rowCount := categoryCount + 6 + scriptRows ; Root actions + separators.
    if (shortcutCount > 0)
        rowCount += shortcutCount + 1 ; Shortcut rows + separator.
    return (rowCount * 24) + 14
}

; Handles menu likely opens upward.
MenuLikelyOpensUpward(mouseX, mouseY, categoryCount, shortcutCount := 0) {
    GetWorkAreaForPoint(mouseX, mouseY, &waLeft, &waTop, &waRight, &waBottom)
    neededHeight := EstimateRootMenuHeight(categoryCount, shortcutCount)
    spaceBelow := waBottom - mouseY
    spaceAbove := mouseY - waTop

    if (spaceBelow >= neededHeight)
        return false
    if (spaceAbove >= neededHeight)
        return true
    return (spaceAbove > spaceBelow)
}

; Opens or shows show snippet menu.
ShowSnippetMenu(*) {
    global SnippetFile, SnippetEncoding, DefaultCategory
    global _Categories, _EntriesByCategory, _EntryOrderByCategory
    global _PendingPasteTarget

    isTextContext := IsTextInputContextActive()
    isFolderContext := ScriptRunnerIsFolderContextActive(&folderContextPath)

    if !isTextContext && !isFolderContext {
        ShowTransientToolTip(T("msg_text_or_folder_context_required"))
        return
    }

    MouseGetPos &mx, &my

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
    _PendingPasteTarget := CapturePasteTargetContext()
    shortcutEntries := GetRootShortcutEntries()
    openUpward := MenuLikelyOpensUpward(mx, my, _Categories.Length, shortcutEntries.Length)

    mainMenu := Menu()
    if openUpward
        AddFarRootActionsSection(mainMenu, true, "paste")
    if !openUpward
        AddRootShortcutSection(mainMenu, true, shortcutEntries)

    for _, category in _Categories {
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
        mainMenu.Add(category, sub)
    }

    if openUpward
        AddRootShortcutSection(mainMenu, false, shortcutEntries)
    if !openUpward
        AddFarRootActionsSection(mainMenu, false, "paste")

    StartMenuOutsideClickWatcher()
    try {
        mainMenu.Show(mx, my)
    } finally {
        StopMenuOutsideClickWatcher()
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
