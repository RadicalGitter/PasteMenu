; ---------------------------------------------------------------------
; Hotwheel GDI+ fan renderer.
; Owns: layered window creation, GDI+ bitmap, draw loop.
; Consumes: view model + layout from state/geometry modules.
; Does NOT decide targets, usage scores, or actions.
; ---------------------------------------------------------------------

_HotwheelGdipToken := 0

HotwheelStyle() {
    return {
        sliceFill:      0xDD1E2430,
        sliceFillHover: 0xDD2A4F8A,
        entryFill:      0xDD172040,
        entryFillHover: 0xDD2868CC,
        centerFill:     0xDD101420,
        border:         0xFF2A3850,
        textNormal:     0xFFAAB4C4,
        textHover:      0xFFEEF2FF,
        borderWidth:    1.5
    }
}

; ---- GDI+ token (kept alive for the session) ----

HotwheelGdipEnsure() {
    global _HotwheelGdipToken
    if !_HotwheelGdipToken
        _HotwheelGdipToken := Gdip_Startup()
}

; ---- Open ----

HotwheelRenderOpen(state) {
    global _HotwheelWindowState
    HotwheelRenderClose()
    HotwheelGdipEnsure()

    ; config.scale is now always 1.0 (logical pixels); renderScale is the physical/logical ratio.
    config      := state.layout.config
    renderScale := A_ScreenDPI / 96
    r           := config.outerRadius + 24   ; logical px (outerRadius is logical, padding is logical)
    cx          := Round(state.layout.centerX)
    cy          := Round(state.layout.centerY)

    HotwheelGetWorkAreaForPoint(cx, cy, &waLeft, &waTop, &waRight, &waBottom)
    winW := r * 2   ; logical
    winH := r * 2
    winX := HotwheelClamp(cx - r, waLeft,  waRight  - winW)
    winY := HotwheelClamp(cy - r, waTop,   waBottom - winH)

    ; Physical bitmap dimensions for crisp GDI+ rendering
    bmpW := Round(winW * renderScale)
    bmpH := Round(winH * renderScale)
    ; Physical local center within the bitmap
    localCX := Round((cx - winX) * renderScale)
    localCY := Round((cy - winY) * renderScale)

    guiObj := Gui("+AlwaysOnTop -Caption +ToolWindow")
    guiObj.Show("x" winX " y" winY " w" winW " h" winH " NoActivate")
    hwnd := guiObj.Hwnd
    WinSetExStyle(WinGetExStyle(hwnd) | 0x80000, hwnd)  ; WS_EX_LAYERED

    renderState := {
        gui:           guiObj,
        hwnd:          hwnd,
        hotwheelState: state,
        winX:          winX,
        winY:          winY,
        winW:          winW,
        winH:          winH,
        bmpW:          bmpW,
        bmpH:          bmpH,
        localCX:       localCX,
        localCY:       localCY,
        renderScale:   renderScale,
        visualTargets: [],
        refreshing:    false,
        closing:       false,
        inputHook:     0,
        openedTick:    A_TickCount,
        focusLostCloseEnabled: false
    }
    _HotwheelWindowState := renderState
    HotwheelRenderDraw(renderState)

    guiObj.OnEvent("Escape", HotwheelRenderEscape.Bind(renderState))
    guiObj.OnEvent("Close",  HotwheelRenderCloseEvent.Bind(renderState))
    HotwheelInputStart(renderState)
}

; ---- Refresh: redraw in place, no window destroy ----

HotwheelRenderRefresh(renderState) {
    if !IsObject(renderState) || !IsObject(renderState.hotwheelState)
        return
    if renderState.refreshing || renderState.closing
        return
    renderState.refreshing := true
    try {
        HotwheelRenderDraw(renderState)
    } finally {
        renderState.refreshing := false
    }
}

; ---- Main draw ----

HotwheelRenderDraw(renderState) {
    global _HotwheelGdipToken
    if !_HotwheelGdipToken
        return

    state  := renderState.hotwheelState
    layout := state.layout
    vm     := state.viewModel
    w      := renderState.bmpW        ; physical pixels
    h      := renderState.bmpH
    lcx    := renderState.localCX     ; physical local center
    lcy    := renderState.localCY
    rs     := renderState.renderScale ; physical/logical ratio
    style  := HotwheelStyle()

    ; Scale logical geometry radii to physical for GDI+ drawing
    outerR := Round(layout.config.outerRadius * rs)
    innerR := Round(layout.config.centerRadius * rs)

    pBitmap := Gdip_CreateBitmap(w, h)
    G       := Gdip_GraphicsFromImage(pBitmap)
    Gdip_SetSmoothingMode(G, 4)
    Gdip_SetTextRenderingHint(G, 4)
    Gdip_GraphicsClear(G, 0x00000000)

    ; Category slices: solid pies from center (center zone will cover inner area)
    for _, slice in layout.categorySlices {
        hovered   := (slice.kind = "category" || slice.kind = "more")
            && (slice.category = state.hoveredCategory)
        fillColor := hovered ? style.sliceFillHover : style.sliceFill
        HotwheelDrawPieSlice(G, lcx, lcy, Round(slice.outerRadius * rs),
            slice.rawStartDeg, slice.rawEndDeg, fillColor)
    }

    ; Entry slices: donut ring within hovered category
    for _, slice in layout.entrySlices {
        hovered := (state.hoverTarget.kind = "entry"
            && state.hoverTarget.HasOwnProp("title")
            && state.hoverTarget.title = slice.title)
        fillColor := hovered ? style.entryFillHover : style.entryFill
        HotwheelDrawDonutSlice(G, lcx, lcy,
            Round(slice.innerRadius * rs), Round(slice.outerRadius * rs),
            slice.rawStartDeg, slice.rawEndDeg, fillColor)
    }

    ; Borders: radial separators + outer arc
    pPen := Gdip_CreatePen(style.border, style.borderWidth)
    pi   := 3.141592653589793

    for _, slice in layout.categorySlices {
        rad := slice.rawStartDeg * pi / 180
        Gdip_DrawLine(G, pPen,
            lcx + Cos(rad) * innerR,  lcy + Sin(rad) * innerR,
            lcx + Cos(rad) * outerR,  lcy + Sin(rad) * outerR)
    }
    if layout.categorySlices.Length > 0 {
        last := layout.categorySlices[layout.categorySlices.Length]
        rad  := last.rawEndDeg * pi / 180
        Gdip_DrawLine(G, pPen,
            lcx + Cos(rad) * innerR,  lcy + Sin(rad) * innerR,
            lcx + Cos(rad) * outerR,  lcy + Sin(rad) * outerR)
    }
    if layout.categorySlices.Length > 0 {
        fanStart := layout.categorySlices[1].rawStartDeg
        fanSpan  := layout.categorySlices[layout.categorySlices.Length].rawEndDeg - fanStart
        Gdip_DrawArc(G, pPen, lcx - outerR, lcy - outerR, outerR * 2, outerR * 2, fanStart, fanSpan)
    }
    Gdip_DeletePen(pPen)

    ; Center zone (covers inner part of all pies)
    HotwheelDrawCenterZone(G, lcx, lcy, vm, layout, style, w, h, rs)

    ; Slice labels
    for _, slice in layout.categorySlices {
        hovered := (slice.kind = "category" || slice.kind = "more")
            && (slice.category = state.hoveredCategory)
        HotwheelDrawSliceLabel(G, lcx, lcy, slice, slice.label, hovered, style, w, h, rs)
    }
    for _, slice in layout.entrySlices {
        hovered := (state.hoverTarget.kind = "entry"
            && state.hoverTarget.HasOwnProp("title")
            && state.hoverTarget.title = slice.title)
        HotwheelDrawSliceLabel(G, lcx, lcy, slice, slice.label, hovered, style, w, h, rs)
    }

    HotwheelRenderApplyBitmap(renderState, pBitmap, G)
}

HotwheelRenderApplyBitmap(renderState, pBitmap, G) {
    Gdip_DeleteGraphics(G)
    hBitmap := Gdip_CreateHBITMAPFromBitmap(pBitmap, 0)
    Gdip_DisposeImage(pBitmap)

    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem    := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    old       := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap, "Ptr")

    ; No x/y — Gui.Show already positioned the window in logical coords.
    ; Pass physical bitmap dimensions so the layered content matches 1:1.
    UpdateLayeredWindow(renderState.hwnd, hdcMem,
        , , renderState.bmpW, renderState.bmpH)

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", old)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    DllCall("DeleteObject", "Ptr", hBitmap)
}

; ---- Drawing primitives ----

HotwheelDrawPieSlice(G, cx, cy, outerRadius, startDeg, endDeg, fillColor) {
    sweepDeg := endDeg - startDeg
    if (Abs(sweepDeg) < 0.1)
        return
    pBrush := Gdip_BrushCreateSolid(fillColor)
    Gdip_FillPie(G, pBrush, cx - outerRadius, cy - outerRadius,
        outerRadius * 2, outerRadius * 2, startDeg, sweepDeg)
    Gdip_DeleteBrush(pBrush)
}

HotwheelDrawDonutSlice(G, cx, cy, innerRadius, outerRadius, startDeg, endDeg, fillColor) {
    sweepDeg := endDeg - startDeg
    if (Abs(sweepDeg) < 0.1)
        return
    outerPts := HotwheelArcPoints(cx, cy, outerRadius, startDeg, endDeg)
    innerPts  := HotwheelArcPoints(cx, cy, innerRadius, endDeg, startDeg)
    pts := outerPts "|" innerPts

    pPath  := Gdip_CreatePath(0)
    Gdip_AddPathPolygon(pPath, pts)
    pBrush := Gdip_BrushCreateSolid(fillColor)
    Gdip_FillPath(G, pBrush, pPath)
    Gdip_DeleteBrush(pBrush)
    Gdip_DeletePath(pPath)
}

; Returns "x1,y1|x2,y2|..." arc points from fromDeg to toDeg
HotwheelArcPoints(cx, cy, radius, fromDeg, toDeg) {
    pi    := 3.141592653589793
    span  := Abs(toDeg - fromDeg)
    count := Max(2, Ceil(span / 2) + 1)
    step  := (toDeg - fromDeg) / (count - 1)
    pts   := ""
    Loop count {
        d   := fromDeg + (A_Index - 1) * step
        rad := d * pi / 180
        pts .= (A_Index > 1 ? "|" : "")
            . Round(cx + Cos(rad) * radius, 1) "," Round(cy + Sin(rad) * radius, 1)
    }
    return pts
}

HotwheelDrawCenterZone(G, cx, cy, vm, layout, style, winW, winH, rs) {
    r      := Round(layout.config.centerRadius * rs)   ; physical
    vector := HotwheelDirectionVector(layout.direction)

    pBrush := Gdip_BrushCreateSolid(style.centerFill)
    Gdip_FillEllipse(G, pBrush, cx - r, cy - r, r * 2, r * 2)
    Gdip_DeleteBrush(pBrush)

    pPen := Gdip_CreatePen(style.border, style.borderWidth)
    Gdip_DrawEllipse(G, pPen, cx - r, cy - r, r * 2, r * 2)

    for _, dividerOffset in [-(r * 0.25), r * 0.25] {
        halfChord := Sqrt(Max(0, r * r - dividerOffset * dividerOffset))
        Gdip_DrawLine(G, pPen,
            cx + vector.rightX * dividerOffset + vector.forwardX * halfChord,
            cy + vector.rightY * dividerOffset + vector.forwardY * halfChord,
            cx + vector.rightX * dividerOffset - vector.forwardX * halfChord,
            cy + vector.rightY * dividerOffset - vector.forwardY * halfChord)
    }
    Gdip_DeletePen(pPen)

    fSize := Max(8, Round(9 * rs))
    boxH  := Round(22 * rs)
    for _, action in vm.centerActions {
        if !action.enabled || !IsObject(action.geometry)
            continue
        geom := action.geometry
        midT := (geom.minTangent + geom.maxTangent) / 2 * rs   ; scale tangent to physical
        ax   := cx + vector.rightX * midT
        ay   := cy + vector.rightY * midT
        boxW := Round(Abs(geom.maxTangent - geom.minTangent) * rs * 0.88)
        colorStr := Format("{:08X}", style.textNormal)
        clipped  := HotwheelRenderClipLabel(action.label, 10)
        Gdip_TextToGraphics(G, clipped,
            "x" Round(ax - boxW / 2) " y" Round(ay - boxH / 2)
            " w" boxW " h" boxH " c" colorStr " s" fSize " Center vCenter",
            "Segoe UI", winW, winH)
    }
}

HotwheelDrawSliceLabel(G, lcx, lcy, slice, label, hovered, style, winW, winH, rs) {
    if (label = "")
        return
    pi        := 3.141592653589793
    midAngle  := (slice.rawStartDeg + slice.rawEndDeg) / 2
    midRadius := (slice.innerRadius + slice.outerRadius) / 2 * rs   ; scale to physical
    midRad    := midAngle * pi / 180
    lx        := lcx + Cos(midRad) * midRadius
    ly        := lcy + Sin(midRad) * midRadius

    fSize    := Max(8, Round(9 * rs))
    boxW     := Round(88 * rs)
    boxH     := Round(22 * rs)
    colorStr := Format("{:08X}", hovered ? style.textHover : style.textNormal)
    clipped  := HotwheelRenderClipLabel(label, 14)
    Gdip_TextToGraphics(G, clipped,
        "x" Round(lx - boxW / 2) " y" Round(ly - boxH / 2)
        " w" boxW " h" boxH " c" colorStr " s" fSize " Center vCenter",
        "Segoe UI", winW, winH)
}

; ---- Hit testing: delegate to polar geometry ----

HotwheelRenderTargetFromPoint(renderState, screenX, screenY) {
    return 0  ; no rect targets — polar hit-testing via HotwheelStateTargetFromPoint
}

; ---- Utilities ----

HotwheelClamp(value, minValue, maxValue) {
    if (maxValue < minValue)
        return minValue
    if (value < minValue)
        return minValue
    if (value > maxValue)
        return maxValue
    return value
}

HotwheelRenderClipLabel(label, maxChars) {
    text := Trim(label)
    if (StrLen(text) <= maxChars)
        return text
    if (maxChars <= 3)
        return SubStr(text, 1, maxChars)
    return SubStr(text, 1, maxChars - 3) "..."
}

; ---- Event handlers ----

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
    HotwheelDebugLog("GUI Close event (WM_CLOSE or X button)")
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
    if ((wParam & 0xFFFF) = 0)
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
    HotwheelDebugLog("Focus lost close")
    if IsObject(_HotwheelWindowState.hotwheelState)
        HotwheelStateClose(_HotwheelWindowState.hotwheelState, HotwheelCloseReason("focus_lost"))
    HotwheelRenderClose()
}
