; ---------------------------------------------------------------------
; Hotwheel state:
; - Open/hover/close state
; - View model mapping for renderers
; - Target descriptors and click outcomes
; ---------------------------------------------------------------------

HotwheelCloseReason(name) {
    switch name {
        case "select": return "select"
        case "settings": return "settings"
        case "root_menu": return "root_menu"
        case "empty_click": return "empty_click"
        case "right_click": return "right_click"
        case "escape": return "escape"
        case "unrelated_key": return "unrelated_key"
        case "focus_lost": return "focus_lost"
        default: return "unknown"
    }
}

HotwheelStateCreate(cursorX, cursorY, categories, entriesByCategory, entryOrderByCategory, pasteTarget := 0, config := 0) {
    if !IsObject(config)
        config := HotwheelGeometryDefaultConfig()

    state := {
        isOpen: true,
        cursorX: cursorX,
        cursorY: cursorY,
        categories: categories,
        entriesByCategory: entriesByCategory,
        entryOrderByCategory: entryOrderByCategory,
        pasteTarget: pasteTarget,
        hoveredCategory: "",
        hoverTarget: {kind: "empty", enabled: false},
        selectedTarget: 0,
        closeReason: "",
        config: config,
        layout: 0,
        viewModel: 0
    }
    HotwheelStateRebuildView(state)
    return state
}

HotwheelStateRebuildView(state) {
    state.layout := HotwheelBuildLayout(
        state.cursorX,
        state.cursorY,
        state.categories,
        state.entriesByCategory,
        state.entryOrderByCategory,
        state.hoveredCategory,
        state.config
    )
    state.viewModel := HotwheelStateBuildViewModel(state)
}

HotwheelStateBuildViewModel(state) {
    return {
        isOpen: state.isOpen,
        closeReason: state.closeReason,
        centerX: state.layout.centerX,
        centerY: state.layout.centerY,
        direction: state.layout.direction,
        bounds: state.layout.bounds,
        centerActions: HotwheelStateBuildCenterActions(state.layout),
        categorySlices: HotwheelStateBuildCategoryViews(state.layout.categorySlices, state.hoveredCategory),
        entrySlices: HotwheelStateBuildEntryViews(state.layout.entrySlices),
        hoverTarget: state.hoverTarget
    }
}

HotwheelStateBuildCenterActions(layout) {
    UsageStatsGetLastAndMostUsed(&lastEntry, &mostEntry)

    actions := []
    for _, slot in layout.centerSlots {
        switch slot.slot {
            case "most_used":
                action := HotwheelStateBuildPasteCenterAction(slot, mostEntry)
            case "last_used":
                action := HotwheelStateBuildPasteCenterAction(slot, lastEntry)
            case "settings":
                action := {
                    kind: "settings",
                    slot: slot.slot,
                    label: T("menu_settings"),
                    enabled: true,
                    geometry: slot
                }
            default:
                action := HotwheelStateEmptyAction(slot.slot, slot)
        }
        actions.Push(action)
    }
    return actions
}

HotwheelStateBuildPasteCenterAction(slot, entry) {
    if !IsObject(entry)
        return HotwheelStateEmptyAction(slot.slot, slot)
    return {
        kind: "paste",
        slot: slot.slot,
        category: entry.category,
        title: entry.title,
        label: entry.title,
        enabled: true,
        geometry: slot
    }
}

HotwheelStateEmptyAction(slotName := "", geometry := 0) {
    return {
        kind: "empty",
        slot: slotName,
        label: "",
        enabled: false,
        geometry: geometry
    }
}

HotwheelStateBuildCategoryViews(categorySlices, hoveredCategory) {
    views := []
    for _, slice in categorySlices {
        views.Push({
            kind: slice.kind,
            category: slice.category,
            label: slice.label,
            enabled: true,
            hovered: slice.category != "" && slice.category = hoveredCategory,
            geometry: slice
        })
    }
    return views
}

HotwheelStateBuildEntryViews(entrySlices) {
    views := []
    for _, slice in entrySlices {
        views.Push({
            kind: "paste",
            category: slice.category,
            title: slice.title,
            label: slice.label,
            enabled: true,
            geometry: slice
        })
    }
    return views
}

HotwheelStateSetHoverAt(state, x, y) {
    target := HotwheelStateTargetFromPoint(state, x, y)
    state.hoverTarget := target

    nextHovered := ""
    if (target.kind = "category")
        nextHovered := target.category
    else if (target.kind = "entry")
        nextHovered := target.category

    if (nextHovered != state.hoveredCategory) {
        state.hoveredCategory := nextHovered
        HotwheelStateRebuildView(state)
        state.hoverTarget := HotwheelStateTargetFromPoint(state, x, y)
    } else {
        state.viewModel := HotwheelStateBuildViewModel(state)
    }

    return state.hoverTarget
}

HotwheelStateTargetFromPoint(state, x, y) {
    hit := HotwheelHitTest(state.layout, x, y)
    return HotwheelStateTargetFromHit(state, hit)
}

HotwheelStateTargetFromHit(state, hit) {
    switch hit.kind {
        case "center":
            return HotwheelStateCenterTargetBySlot(state.viewModel.centerActions, hit.slot)
        case "entry":
            return {
                kind: "entry",
                action: "paste",
                category: hit.category,
                title: hit.title,
                label: hit.label,
                enabled: true
            }
        case "category":
            return {
                kind: "category",
                action: "hover",
                category: hit.category,
                label: hit.label,
                enabled: true
            }
        case "more":
            return {
                kind: "more",
                action: "root_menu",
                label: hit.label,
                enabled: true
            }
        default:
            return {kind: "empty", action: "none", label: "", enabled: false}
    }
}

HotwheelStateCenterTargetBySlot(centerActions, slotName) {
    for _, action in centerActions {
        if (action.slot != slotName)
            continue

        if !action.enabled
            return {kind: "empty", action: "none", slot: slotName, label: "", enabled: false}

        if (action.kind = "settings") {
            return {
                kind: "center",
                action: "settings",
                slot: slotName,
                label: action.label,
                enabled: true
            }
        }

        if (action.kind = "paste") {
            return {
                kind: "center",
                action: "paste",
                slot: slotName,
                category: action.category,
                title: action.title,
                label: action.label,
                enabled: true
            }
        }
    }
    return {kind: "empty", action: "none", slot: slotName, label: "", enabled: false}
}

HotwheelStateResolveLeftClick(state, target) {
    if !IsObject(target) || !target.enabled {
        HotwheelStateClose(state, HotwheelCloseReason("empty_click"))
        return {close: true, closeReason: state.closeReason, action: "none"}
    }

    switch target.action {
        case "paste":
            state.selectedTarget := target
            HotwheelStateClose(state, HotwheelCloseReason("select"))
            return {
                close: true,
                closeReason: state.closeReason,
                action: "paste",
                category: target.category,
                title: target.title,
                pasteTarget: state.pasteTarget
            }
        case "settings":
            state.selectedTarget := target
            HotwheelStateClose(state, HotwheelCloseReason("settings"))
            return {close: true, closeReason: state.closeReason, action: "settings"}
        case "root_menu":
            state.selectedTarget := target
            HotwheelStateClose(state, HotwheelCloseReason("root_menu"))
            return {close: true, closeReason: state.closeReason, action: "root_menu"}
        default:
            HotwheelStateClose(state, HotwheelCloseReason("empty_click"))
            return {close: true, closeReason: state.closeReason, action: "none"}
    }
}

HotwheelStateClose(state, reason) {
    state.isOpen := false
    state.closeReason := reason
    if IsObject(state.viewModel) {
        state.viewModel.isOpen := false
        state.viewModel.closeReason := reason
    }
}
