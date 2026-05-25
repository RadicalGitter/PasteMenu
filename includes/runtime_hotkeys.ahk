RegisterConfiguredHotkey() {
    global ConfiguredHotkey, _CurrentHotkeyRegistered

    if (ConfiguredHotkey = "")
        ConfiguredHotkey := "^F9"

    if (_CurrentHotkeyRegistered != "") {
        try Hotkey(_CurrentHotkeyRegistered, "Off")
    }

    try {
        Hotkey(ConfiguredHotkey, DispatchConfiguredHotkey, "On")
        _CurrentHotkeyRegistered := ConfiguredHotkey
        return true
    } catch {
        ConfiguredHotkey := "^F9"
        try Hotkey("^F9", DispatchConfiguredHotkey, "On")
        _CurrentHotkeyRegistered := "^F9"
        return false
    }
}

DispatchConfiguredHotkey(*) {
    global ConfiguredHotkey, HotwheelHoldThresholdMs

    triggerKey := GetHotkeyTriggerKey(ConfiguredHotkey)
    thresholdMs := NormalizeHotwheelHoldThresholdMs(HotwheelHoldThresholdMs)
    if (triggerKey = "") {
        ShowSnippetMenu()
        return
    }

    thresholdSeconds := Format("{:.3f}", thresholdMs / 1000)
    if KeyWait(triggerKey, "T" thresholdSeconds)
        ShowSnippetMenu()
    else
        ShowHotwheel()
}

GetHotkeyTriggerKey(hotkeyName) {
    hk := Trim(hotkeyName)
    if (hk = "")
        return ""

    ; Strip option prefixes and modifiers, leaving the physical trigger key.
    while (hk != "" && InStr("~*$", SubStr(hk, 1, 1)))
        hk := SubStr(hk, 2)
    while (hk != "" && InStr("^!+#", SubStr(hk, 1, 1)))
        hk := SubStr(hk, 2)

    return Trim(hk)
}

NormalizeHotwheelHoldThresholdMs(value) {
    try threshold := value + 0
    catch {
        threshold := 200
    }
    if (threshold < 100)
        threshold := 100
    if (threshold > 500)
        threshold := 500
    return Round(threshold)
}

; Sets or applies setup tray menu.
SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add(T("tray_open_editor"), TrayOpenEditorAction)
    A_TrayMenu.Add(T("tray_open_settings"), OpenSettingsWindow)
    A_TrayMenu.Add(T("menu_exit"), TrayExitAction)
    A_TrayMenu.Default := T("tray_open_editor")
    A_TrayMenu.ClickCount := 1
}

; Loads or deserializes load current snippet data.
LoadCurrentSnippetData(&errorMsg := "") {
    global SnippetFile, SnippetEncoding, DefaultCategory
    global _Categories, _EntriesByCategory, _EntryOrderByCategory

    EnsureSnippetFile(SnippetFile)

    categories := []
    entriesByCategory := Map()
    entryOrderByCategory := Map()
    if !LoadSnippetsFromFile(
        SnippetFile,
        SnippetEncoding,
        DefaultCategory,
        &categories,
        &entriesByCategory,
        &entryOrderByCategory
    ) {
        errorMsg := "Could not load entries from:`n" SnippetFile
        return false
    }

    _Categories := categories
    _EntriesByCategory := entriesByCategory
    _EntryOrderByCategory := entryOrderByCategory
    return true
}

; Handles tray open editor action.
TrayOpenEditorAction(*) {
    if !LoadCurrentSnippetData(&err) {
        MsgBox err
        return
    }
    if (_Categories.Length = 0) {
        MsgBox "No categories found."
        return
    }
    OpenCategoryEditor(_Categories[1], "", false)
}

; Handles tray exit action.
TrayExitAction(*) {
    ExitApp
}

; Checks whether is modifier key name.
IsModifierKeyName(keyName) {
    static mod := Map(
        "Ctrl", 1, "LControl", 1, "RControl", 1,
        "Alt", 1, "LAlt", 1, "RAlt", 1,
        "Shift", 1, "LShift", 1, "RShift", 1,
        "LWin", 1, "RWin", 1
    )
    return mod.Has(keyName)
}

; Creates or builds build hotkey from current state.
BuildHotkeyFromCurrentState(vk, sc) {
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (keyName = "" || IsModifierKeyName(keyName))
        return ""

    return BuildHotkeyWithModifiers(keyName)
}

; Creates or builds build hotkey with modifiers.
BuildHotkeyWithModifiers(keyName) {
    mods := ""
    if GetKeyState("Ctrl", "P")
        mods .= "^"
    if GetKeyState("Alt", "P")
        mods .= "!"
    if GetKeyState("Shift", "P")
        mods .= "+"
    if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        mods .= "#"

    return mods keyName
}

; Checks whether is recommended hotkey.
IsRecommendedHotkey(hk) {
    if RegExMatch(hk, "[\^\!\+\#]")
        return true
    return RegExMatch(hk, "i)F(?:[1-9]|1\d|2[0-4])$")
}

; Handles hotkey to display.
HotkeyToDisplay(hk) {
    hk := Trim(hk)
    if (hk = "")
        return ""

    mods := []
    Loop Parse hk {
        ch := A_LoopField
        if (ch = "^")
            mods.Push("Ctrl")
        else if (ch = "!")
            mods.Push("Alt")
        else if (ch = "+")
            mods.Push("Shift")
        else if (ch = "#")
            mods.Push("Win")
        else
            break
    }

    idx := mods.Length + 1
    key := SubStr(hk, idx)
    if (key = "")
        return ""

    ; Friendly names for common non-character keys.
    if (key = "LButton")
        key := "MouseLeft"
    else if (key = "RButton")
        key := "MouseRight"
    else if (key = "MButton")
        key := "MouseMiddle"
    else if (key = "XButton1")
        key := "Mouse4"
    else if (key = "XButton2")
        key := "Mouse5"
    else if (key = "WheelUp")
        key := "WheelUp"
    else if (key = "WheelDown")
        key := "WheelDown"

    out := ""
    for i, m in mods {
        if (i > 1)
            out .= "+"
        out .= m
    }
    if (out != "")
        out .= "+"
    out .= key
    return out
}

; Handles hotkey stop capture.
HotkeyStopCapture(state) {
    state.isCapturing := false
    if IsObject(state.captureHook) {
        try state.captureHook.Stop()
        state.captureHook := 0
    }
    if IsObject(state.mouseHotkeys) {
        for hotkeyName, _ in state.mouseHotkeys {
            try Hotkey(hotkeyName, "Off")
        }
        state.mouseHotkeys := 0
    }
}

; Handles hotkey start capture.
HotkeyStartCapture(state, *) {
    HotkeyStopCapture(state)
    state.captureStartHotkey := state.selectedHotkey
    state.captureIgnoreMouseUntil := A_TickCount + 250
    state.statusText.Value := T("hotkey_dialog_listening")
    state.isCapturing := true

    ih := InputHook("V")
    ih.KeyOpt("{All}", "N")
    ih.OnKeyDown := HotkeyCaptureKeyDown.Bind(state)
    state.captureHook := ih
    ih.Start()
    HotkeyRegisterCaptureMouseHotkeys(state)
}

; Handles hotkey capture cancel.
HotkeyCaptureCancel(state) {
    if (state.captureStartHotkey != "")
        state.selectedHotkey := state.captureStartHotkey
    state.hotkeyDisplay.Text := HotkeyToDisplay(state.selectedHotkey)
    HotkeyStopCapture(state)
    state.statusText.Value := T("hotkey_dialog_capture_cancelled")
    try state.btnSave.Focus()
}

; Handles hotkey register capture mouse hotkeys.
HotkeyRegisterCaptureMouseHotkeys(state) {
    hooks := Map()
    mouseKeys := ["RButton", "MButton", "XButton1", "XButton2"]
    for _, keyName in mouseKeys {
        hkName := "~*" keyName
        fn := HotkeyCaptureMouse.Bind(state, keyName)
        try {
            Hotkey(hkName, fn, "On")
            hooks[hkName] := fn
        }
    }
    state.mouseHotkeys := hooks
}

; Handles hotkey apply captured value.
HotkeyApplyCapturedValue(state, hk) {
    state.selectedHotkey := hk
    state.hotkeyDisplay.Text := HotkeyToDisplay(hk)
    HotkeyStopCapture(state)
    if IsRecommendedHotkey(hk)
        state.statusText.Value := ""
    else
        state.statusText.Value := T("msg_hotkey_recommend")
    try state.btnSave.Focus()
}

; Handles hotkey capture key down.
HotkeyCaptureKeyDown(state, ih, vk, sc) {
    if !state.isCapturing
        return

    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (keyName = "Escape" || keyName = "Esc") {
        HotkeyCaptureCancel(state)
        return
    }

    hk := BuildHotkeyFromCurrentState(vk, sc)
    if (hk = "")
        return

    HotkeyApplyCapturedValue(state, hk)
}

; Handles hotkey capture mouse.
HotkeyCaptureMouse(state, keyName, *) {
    if !state.isCapturing
        return
    if (A_TickCount < state.captureIgnoreMouseUntil)
        return

    hk := BuildHotkeyWithModifiers(keyName)
    if (hk = "")
        return

    HotkeyApplyCapturedValue(state, hk)
}

; Handles hotkey dialog save.
HotkeyDialogSave(state, *) {
    global ConfiguredHotkey

    HotkeyStopCapture(state)

    chosen := state.selectedHotkey
    if (chosen = "")
        chosen := ConfiguredHotkey
    if (chosen = "")
        chosen := "^F9"

    ConfiguredHotkey := chosen
    ok := RegisterConfiguredHotkey()
    SaveSettings()

    if !ok
        MsgBox T("msg_hotkey_invalid"), T("hotkey_dialog_title")
    else if !IsRecommendedHotkey(chosen)
        MsgBox T("msg_hotkey_recommend"), T("hotkey_dialog_title")

    try state.gui.Destroy()
}

; Handles hotkey dialog cancel.
HotkeyDialogCancel(state, *) {
    global ConfiguredHotkey

    HotkeyStopCapture(state)

    if (state.forceMode && ConfiguredHotkey = "") {
        ConfiguredHotkey := "^F9"
        RegisterConfiguredHotkey()
        SaveSettings()
    }
    try state.gui.Destroy()
}

; Handles hotkey dialog escape.
HotkeyDialogEscape(state, *) {
    if (state.isCapturing) {
        HotkeyCaptureCancel(state)
        return
    }
    HotkeyDialogCancel(state)
}

; Opens or shows open hotkey config dialog.
OpenHotkeyConfigDialog(forceMode := false, *) {
    global ConfiguredHotkey

    hkGui := Gui("+AlwaysOnTop", T("hotkey_dialog_title"))
    hkGui.SetFont("s10", "Segoe UI")

    currentHotkey := ConfiguredHotkey != "" ? ConfiguredHotkey : "^F9"

    hkGui.AddText("x10 y10 w420", T("hotkey_dialog_current"))
    hotkeyDisplay := hkGui.AddText("x10 y30 w420 h28 +Border +0x100", HotkeyToDisplay(currentHotkey))
    statusText := hkGui.AddText("x10 y66 w420 h32", T("hotkey_dialog_click"))

    btnSave := hkGui.AddButton("x280 y108 w70 h30", T("hotkey_dialog_save"))
    btnCancel := hkGui.AddButton("x360 y108 w70 h30", T("hotkey_dialog_cancel"))

    state := {
        gui: hkGui,
        hotkeyDisplay: hotkeyDisplay,
        statusText: statusText,
        selectedHotkey: currentHotkey,
        forceMode: forceMode,
        isCapturing: false,
        captureHook: 0,
        mouseHotkeys: 0,
        captureStartHotkey: currentHotkey,
        captureIgnoreMouseUntil: 0,
        btnSave: btnSave
    }

    hotkeyDisplay.OnEvent("Click", HotkeyStartCapture.Bind(state))
    hotkeyDisplay.OnEvent("DoubleClick", HotkeyStartCapture.Bind(state))
    btnSave.OnEvent("Click", HotkeyDialogSave.Bind(state))
    btnCancel.OnEvent("Click", HotkeyDialogCancel.Bind(state))
    hkGui.OnEvent("Close", HotkeyDialogCancel.Bind(state))
    hkGui.OnEvent("Escape", HotkeyDialogEscape.Bind(state))

    hkGui.Show("w440 h148")
    if forceMode
        WinWaitClose("ahk_id " hkGui.Hwnd)
}

; Sets or applies settings configure hotkey action.
