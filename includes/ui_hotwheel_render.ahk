; ---------------------------------------------------------------------
; Plain hotwheel renderer:
; - Owns GUI/control creation only
; - Consumes prepared state/view-model data
; - Can be replaced by GDI+/layered rendering later
; ---------------------------------------------------------------------

HotwheelRenderOpen(state) {
    global _HotwheelWindowState

    HotwheelRenderClose()

    renderState := {
        gui: 0,
        hotwheelState: state,
        originX: 0,
        originY: 0,
        controls: [],
        visualTargets: [],
        refreshing: false,
        closing: false,
        inputHook: 0,
        openedTick: A_TickCount,
        focusLostCloseEnabled: false
    }
    _HotwheelWindowState := renderState
    HotwheelRenderCreateWindow(renderState)
    HotwheelInputStart(renderState)
}

HotwheelRenderCreateWindow(renderState) {
    state := renderState.hotwheelState
    vm := state.viewModel
    frame := HotwheelRenderCompactFrame(vm)
    guiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "PasteMenu Hotwheel")
    guiObj.BackColor := "F6F7F8"
    guiObj.MarginX := 0
    guiObj.MarginY := 0
    guiObj.SetFont("s9", "Segoe UI")

    renderState.gui := guiObj
    renderState.originX := frame.left
    renderState.originY := frame.top
    renderState.frame := frame
    renderState.controls := []
    renderState.visualTargets := []

    HotwheelRenderViewModel(renderState, vm)

    guiObj.OnEvent("Escape", HotwheelRenderEscape.Bind(renderState))
    guiObj.OnEvent("Close", HotwheelRenderCloseEvent.Bind(renderState))
    guiObj.Show(
        "x" frame.left
        " y" frame.top
        " w" frame.width
        " h" frame.height
        " NoActivate"
    )
}

HotwheelRenderRefresh(renderState) {
    if !IsObject(renderState)
        return
    if !IsObject(renderState.hotwheelState)
        return
    if renderState.refreshing || renderState.closing
        return

    renderState.refreshing := true
    try {
        try renderState.gui.Destroy()
        HotwheelRenderCreateWindow(renderState)
    } finally {
        renderState.refreshing := false
    }
}

HotwheelRenderViewModel(renderState, vm) {
    HotwheelRenderPanelBackground(renderState)

    for _, sliceView in vm.categorySlices
        HotwheelRenderCategoryLabel(renderState, vm, sliceView, A_Index)

    for _, entryView in vm.entrySlices
        HotwheelRenderEntryLabel(renderState, vm, entryView, A_Index)

    for _, action in vm.centerActions
        HotwheelRenderCenterAction(renderState, vm, action, A_Index)
}

HotwheelRenderCompactFrame(vm) {
    scale := HotwheelDpiScale()
    width := Round(380 * scale)
    categoryRows := Max(1, Ceil(vm.categorySlices.Length / 2))
    entryRows := vm.entrySlices.Length
    height := Round((112 + (categoryRows * 38) + (entryRows * 30)) * scale)
    if (height < Round(210 * scale))
        height := Round(210 * scale)
    if (height > Round(520 * scale))
        height := Round(520 * scale)

    left := Round(vm.centerX - (width / 2))
    top := Round(vm.centerY - (height / 2))
    HotwheelGetWorkAreaForPoint(vm.centerX, vm.centerY, &waLeft, &waTop, &waRight, &waBottom)
    left := HotwheelClamp(left, waLeft, waRight - width)
    top := HotwheelClamp(top, waTop, waBottom - height)

    return {left: left, top: top, width: width, height: height}
}

HotwheelClamp(value, minValue, maxValue) {
    if (maxValue < minValue)
        return minValue
    if (value < minValue)
        return minValue
    if (value > maxValue)
        return maxValue
    return value
}

HotwheelRenderPanelBackground(renderState) {
    frame := renderState.frame
    ctrl := renderState.gui.AddText(
        "x0 y0 w" frame.width " h" frame.height " BackgroundF6F7F8",
        ""
    )
    renderState.controls.Push(ctrl)
}

HotwheelRenderCategoryLabel(renderState, vm, sliceView, index) {
    frame := renderState.frame
    scale := HotwheelDpiScale()
    padding := Round(12 * scale)
    gap := Round(8 * scale)
    top := Round(60 * scale)
    cellW := Floor((frame.width - (padding * 2) - gap) / 2)
    cellH := Round(30 * scale)
    col := Mod(index - 1, 2)
    row := Floor((index - 1) / 2)
    x := padding + (col * (cellW + gap))
    y := top + (row * (cellH + gap))

    bg := sliceView.hovered ? "DCEBFF" : "FFFFFF"
    text := HotwheelRenderClipLabel(sliceView.label, 22)
    ctrl := renderState.gui.AddText(
        "x" x " y" y " w" cellW " h" cellH " +Center +Border Background" bg,
        text
    )
    ctrl.SetFont("s9 c1F2933")
    renderState.controls.Push(ctrl)
    HotwheelRenderAddVisualTarget(renderState, x, y, cellW, cellH, {
        kind: sliceView.kind,
        action: sliceView.kind = "more" ? "root_menu" : "hover",
        category: sliceView.category,
        label: sliceView.label,
        enabled: true
    })
}

HotwheelRenderEntryLabel(renderState, vm, entryView, index) {
    frame := renderState.frame
    scale := HotwheelDpiScale()
    padding := Round(12 * scale)
    categoryRows := Max(1, Ceil(vm.categorySlices.Length / 2))
    yBase := Round(60 * scale) + (categoryRows * Round(38 * scale)) + Round(8 * scale)
    rowH := Round(26 * scale)
    x := padding
    y := yBase + ((index - 1) * (rowH + Round(4 * scale)))
    width := frame.width - (padding * 2)
    text := HotwheelRenderClipLabel(entryView.label, 34)

    ctrl := renderState.gui.AddText(
        "x" x " y" y " w" width " h" rowH " +Center +Border BackgroundEAF7EF",
        text
    )
    ctrl.SetFont("s9 c1F2933")
    renderState.controls.Push(ctrl)
    HotwheelRenderAddVisualTarget(renderState, x, y, width, rowH, {
        kind: "entry",
        action: "paste",
        category: entryView.category,
        title: entryView.title,
        label: entryView.label,
        enabled: true
    })
}

HotwheelRenderCenterAction(renderState, vm, action, index) {
    frame := renderState.frame
    scale := HotwheelDpiScale()
    padding := Round(12 * scale)
    gap := Round(8 * scale)
    width := Floor((frame.width - (padding * 2) - (gap * 2)) / 3)
    height := Round(34 * scale)
    label := action.enabled ? HotwheelRenderClipLabel(action.label, 16) : ""
    x := padding + ((index - 1) * (width + gap))
    y := Round(12 * scale)

    bg := action.enabled ? "FFFFFF" : "EBECEE"
    if (action.kind = "settings")
        bg := "F7F2E8"

    ctrl := renderState.gui.AddText(
        "x" x " y" y " w" width " h" height " +Center +Border Background" bg,
        label
    )
    ctrl.SetFont("s9 c111827")
    renderState.controls.Push(ctrl)
    HotwheelRenderAddVisualTarget(renderState, x, y, width, height, HotwheelRenderCenterActionTarget(action))
}

HotwheelRenderCenterActionTarget(action) {
    if !action.enabled
        return {kind: "empty", action: "none", slot: action.slot, label: "", enabled: false}
    if (action.kind = "settings")
        return {kind: "center", action: "settings", slot: action.slot, label: action.label, enabled: true}
    if (action.kind = "paste") {
        return {
            kind: "center",
            action: "paste",
            slot: action.slot,
            category: action.category,
            title: action.title,
            label: action.label,
            enabled: true
        }
    }
    return {kind: "empty", action: "none", slot: action.slot, label: "", enabled: false}
}

HotwheelRenderAddVisualTarget(renderState, x, y, width, height, target) {
    renderState.visualTargets.Push({
        x: x,
        y: y,
        width: width,
        height: height,
        target: target
    })
}

HotwheelRenderTargetFromPoint(renderState, screenX, screenY) {
    if !IsObject(renderState) || !renderState.HasOwnProp("visualTargets")
        return 0

    localX := screenX - renderState.originX
    localY := screenY - renderState.originY
    for _, item in renderState.visualTargets {
        if (localX >= item.x && localX < item.x + item.width
            && localY >= item.y && localY < item.y + item.height)
            return item.target
    }
    return 0
}

HotwheelRenderPolarPosition(renderState, vm, angleDeg, radius) {
    rad := angleDeg * 3.141592653589793 / 180
    return {
        x: (vm.centerX - renderState.originX) + (Cos(rad) * radius),
        y: (vm.centerY - renderState.originY) + (Sin(rad) * radius)
    }
}

HotwheelRenderCenterSlotPosition(renderState, vm, slotGeometry) {
    vector := HotwheelDirectionVector(vm.direction)
    tangent := (slotGeometry.minTangent + slotGeometry.maxTangent) / 2
    return {
        x: (vm.centerX - renderState.originX) + (vector.rightX * tangent),
        y: (vm.centerY - renderState.originY) + (vector.rightY * tangent)
    }
}

HotwheelRenderClipLabel(label, maxChars) {
    text := Trim(label)
    if (StrLen(text) <= maxChars)
        return text
    if (maxChars <= 3)
        return SubStr(text, 1, maxChars)
    return SubStr(text, 1, maxChars - 3) "..."
}

HotwheelRenderEscape(renderState, *) {
    if renderState.refreshing || renderState.closing
        return
    if IsObject(renderState.hotwheelState)
        HotwheelStateClose(renderState.hotwheelState, HotwheelCloseReason("escape"))
    HotwheelRenderClose()
}

HotwheelRenderCloseEvent(renderState, *) {
    if renderState.refreshing || renderState.closing
        return
    if IsObject(renderState.hotwheelState) && renderState.hotwheelState.isOpen
        HotwheelStateClose(renderState.hotwheelState, HotwheelCloseReason("focus_lost"))
    HotwheelRenderClose()
}

HotwheelRenderClose(*) {
    global _HotwheelWindowState
    if IsObject(_HotwheelWindowState) {
        _HotwheelWindowState.closing := true
        HotwheelInputStop(_HotwheelWindowState)
        try _HotwheelWindowState.gui.Destroy()
    }
    _HotwheelWindowState := 0
}

HotwheelRenderOnActivate(wParam, lParam, msg, hwnd) {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if !_HotwheelWindowState.focusLostCloseEnabled
        return
    if _HotwheelWindowState.refreshing || _HotwheelWindowState.closing
        return
    if !IsObject(_HotwheelWindowState.gui)
        return
    if (hwnd != _HotwheelWindowState.gui.Hwnd)
        return

    isInactive := ((wParam & 0xFFFF) = 0)
    if isInactive
        SetTimer(HotwheelRenderFocusLostClose, -1)
}

HotwheelRenderFocusLostClose() {
    global _HotwheelWindowState
    if !IsObject(_HotwheelWindowState)
        return
    if !_HotwheelWindowState.focusLostCloseEnabled
        return
    if (A_TickCount - _HotwheelWindowState.openedTick < 1000)
        return
    if _HotwheelWindowState.refreshing || _HotwheelWindowState.closing
        return
    if IsObject(_HotwheelWindowState.hotwheelState)
        HotwheelStateClose(_HotwheelWindowState.hotwheelState, HotwheelCloseReason("focus_lost"))
    HotwheelRenderClose()
}
