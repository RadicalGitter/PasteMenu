; ---------------------------------------------------------------------
; Hotwheel geometry:
; - DPI-scaled fan sizing
; - Direction and slice layout
; - Polar/local hit testing
; ---------------------------------------------------------------------

HotwheelGeometryDefaultConfig() {
    scale := HotwheelDpiScale()
    centerDiameter := HotwheelScalePx(104, scale)
    outerRadius := HotwheelScalePx(300, scale)
    return {
        scale: scale,
        centerZoneDiameter: centerDiameter,
        centerRadius: centerDiameter / 2,
        outerRadius: outerRadius,
        fanSpanDeg: 180,
        hoveredCategoryShare: 0.60,
        maxCategories: 8,
        maxEntriesPerCategory: 6,
        entryRingInnerRadius: centerDiameter / 2 + ((outerRadius - (centerDiameter / 2)) * 0.36)
    }
}

HotwheelDpiScale() {
    return 1.0
}

HotwheelScalePx(px, scale := 0) {
    if (!scale)
        scale := HotwheelDpiScale()
    return Round(px * scale)
}

HotwheelBuildLayout(cursorX, cursorY, categories, entriesByCategory, entryOrderByCategory := 0, hoveredCategory := "", config := 0) {
    if !IsObject(config)
        config := HotwheelGeometryDefaultConfig()

    direction := HotwheelChooseFanDirection(cursorX, cursorY, config)
    categoryNames := HotwheelVisibleCategories(categories, entriesByCategory, config.maxCategories)
    categorySlices := HotwheelLayoutCategorySlices(categoryNames, direction, config, hoveredCategory)
    entrySlices := HotwheelLayoutEntrySlices(categorySlices, entriesByCategory, entryOrderByCategory, hoveredCategory, config)
    bounds := HotwheelComputeBounds(cursorX, cursorY, config.outerRadius)

    return {
        centerX: cursorX,
        centerY: cursorY,
        direction: direction,
        config: config,
        bounds: bounds,
        centerSlots: HotwheelBuildCenterSlots(direction, config),
        categorySlices: categorySlices,
        entrySlices: entrySlices
    }
}

HotwheelVisibleCategories(categories, entriesByCategory, maxCategories := 8) {
    visible := []
    for _, category in categories {
        if !entriesByCategory.Has(category)
            continue
        if (_HasEntries(entriesByCategory[category]))
            visible.Push(category)
    }

    if (maxCategories > 1 && visible.Length > maxCategories) {
        trimmed := []
        Loop maxCategories - 1
            trimmed.Push(visible[A_Index])
        trimmed.Push("__more__")
        return trimmed
    }
    return visible
}

_HasEntries(entryMap) {
    if !IsObject(entryMap)
        return false
    for _, _ in entryMap
        return true
    return false
}

HotwheelChooseFanDirection(cursorX, cursorY, config := 0) {
    if !IsObject(config)
        config := HotwheelGeometryDefaultConfig()

    HotwheelGetWorkAreaForPoint(cursorX, cursorY, &left, &top, &right, &bottom)
    radius := config.outerRadius

    spaces := Map(
        "up", cursorY - top,
        "down", bottom - cursorY,
        "right", right - cursorX,
        "left", cursorX - left
    )

    if (spaces["up"] >= radius)
        return "up"
    if (spaces["down"] >= radius)
        return "down"
    if (spaces["right"] >= radius)
        return "right"
    if (spaces["left"] >= radius)
        return "left"

    bestDirection := "up"
    bestSpace := spaces["up"]
    for direction, space in spaces {
        if (space > bestSpace) {
            bestDirection := direction
            bestSpace := space
        }
    }
    return bestDirection
}

HotwheelGetWorkAreaForPoint(x, y, &left, &top, &right, &bottom) {
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

HotwheelLayoutCategorySlices(categoryNames, direction, config, hoveredCategory := "") {
    slices := []
    count := categoryNames.Length
    if (count = 0)
        return slices

    fanSpan  := config.fanSpanDeg
    fanStart := HotwheelNormalizeAngle(HotwheelDirectionAngle(direction) - (fanSpan / 2))

    hoveredIndex := 0
    for i, cat in categoryNames {
        if (cat = hoveredCategory) {
            hoveredIndex := i
            break
        }
    }

    if (hoveredIndex && count > 1) {
        hoveredWidth := fanSpan * config.hoveredCategoryShare
        otherWidth := (fanSpan - hoveredWidth) / (count - 1)
        current := fanStart
        for i, category in categoryNames {
            width := (i = hoveredIndex) ? hoveredWidth : otherWidth
            slices.Push(HotwheelMakeCategorySlice(category, current, current + width, config, i))
            current += width
        }
        return slices
    }

    width   := fanSpan / count
    current := fanStart
    for i, category in categoryNames {
        slices.Push(HotwheelMakeCategorySlice(category, current, current + width, config, i))
        current += width
    }
    return slices
}

HotwheelMakeCategorySlice(category, startDeg, endDeg, config, index) {
    return {
        kind: category = "__more__" ? "more" : "category",
        category: category = "__more__" ? "" : category,
        label: category = "__more__" ? "More..." : category,
        index: index,
        startDeg: HotwheelNormalizeAngle(startDeg),
        endDeg: HotwheelNormalizeAngle(endDeg),
        rawStartDeg: startDeg,
        rawEndDeg: endDeg,
        innerRadius: config.centerRadius,
        outerRadius: config.outerRadius
    }
}

HotwheelLayoutEntrySlices(categorySlices, entriesByCategory, entryOrderByCategory, hoveredCategory, config) {
    slices := []
    if (hoveredCategory = "" || !entriesByCategory.Has(hoveredCategory))
        return slices

    hoveredSlice := 0
    for _, slice in categorySlices {
        if (slice.category = hoveredCategory) {
            hoveredSlice := slice
            break
        }
    }
    if !IsObject(hoveredSlice)
        return slices

    titles := []
    if IsObject(entryOrderByCategory) && entryOrderByCategory.Has(hoveredCategory) {
        for _, title in entryOrderByCategory[hoveredCategory] {
            if entriesByCategory[hoveredCategory].Has(title)
                titles.Push(title)
            if (titles.Length >= config.maxEntriesPerCategory)
                break
        }
    } else {
        for title, _ in entriesByCategory[hoveredCategory] {
            titles.Push(title)
            if (titles.Length >= config.maxEntriesPerCategory)
                break
        }
    }
    if (titles.Length = 0)
        return slices

    span := hoveredSlice.rawEndDeg - hoveredSlice.rawStartDeg
    width := span / titles.Length
    current := hoveredSlice.rawStartDeg
    for i, title in titles {
        slices.Push({
            kind: "entry",
            category: hoveredCategory,
            title: title,
            label: title,
            index: i,
            startDeg: HotwheelNormalizeAngle(current),
            endDeg: HotwheelNormalizeAngle(current + width),
            rawStartDeg: current,
            rawEndDeg: current + width,
            innerRadius: config.entryRingInnerRadius,
            outerRadius: config.outerRadius
        })
        current += width
    }
    return slices
}

HotwheelBuildCenterSlots(direction, config) {
    radius := config.centerRadius
    return [
        {kind: "center", slot: "most_used", label: "most_used", minTangent: -radius, maxTangent: -(radius * 0.25)},
        {kind: "center", slot: "last_used", label: "last_used", minTangent: -(radius * 0.25), maxTangent: radius * 0.25},
        {kind: "center", slot: "settings", label: "settings", minTangent: radius * 0.25, maxTangent: radius}
    ]
}

HotwheelComputeBounds(centerX, centerY, outerRadius) {
    return {
        left: centerX - outerRadius,
        top: centerY - outerRadius,
        right: centerX + outerRadius,
        bottom: centerY + outerRadius,
        width: outerRadius * 2,
        height: outerRadius * 2
    }
}

HotwheelHitTest(layout, x, y) {
    dx := x - layout.centerX
    dy := y - layout.centerY
    radius := Sqrt((dx * dx) + (dy * dy))

    if (radius <= layout.config.centerRadius)
        return HotwheelHitTestCenter(layout, dx, dy)

    if (radius > layout.config.outerRadius)
        return {kind: "empty"}

    angle := HotwheelPointAngle(dx, dy)
    for _, slice in layout.entrySlices {
        if (radius >= slice.innerRadius && radius <= slice.outerRadius && HotwheelAngleInSlice(angle, slice))
            return {
                kind: "entry",
                category: slice.category,
                title: slice.title,
                label: slice.label,
                slice: slice
            }
    }

    for _, slice in layout.categorySlices {
        if (radius >= slice.innerRadius && radius <= slice.outerRadius && HotwheelAngleInSlice(angle, slice)) {
            if (slice.kind = "more")
                return {kind: "more", label: slice.label, slice: slice}
            return {
                kind: "category",
                category: slice.category,
                label: slice.label,
                slice: slice
            }
        }
    }

    return {kind: "empty"}
}

HotwheelHitTestCenter(layout, dx, dy) {
    localAxes := HotwheelToLocalAxes(layout.direction, dx, dy)
    for _, slot in layout.centerSlots {
        if (localAxes.tangent >= slot.minTangent && localAxes.tangent < slot.maxTangent)
            return {kind: "center", slot: slot.slot}
    }
    return {kind: "center", slot: "last_used"}
}

HotwheelToLocalAxes(direction, dx, dy) {
    vector := HotwheelDirectionVector(direction)
    forward := (dx * vector.forwardX) + (dy * vector.forwardY)
    tangent := (dx * vector.rightX) + (dy * vector.rightY)
    return {forward: forward, tangent: tangent}
}

HotwheelDirectionVector(direction) {
    switch direction {
        case "down":
            forwardX := 0, forwardY := 1
        case "right":
            forwardX := 1, forwardY := 0
        case "left":
            forwardX := -1, forwardY := 0
        default:
            forwardX := 0, forwardY := -1
    }
    return {
        forwardX: forwardX,
        forwardY: forwardY,
        rightX: -forwardY,
        rightY: forwardX
    }
}

HotwheelDirectionAngle(direction) {
    switch direction {
        case "down": return 90
        case "right": return 0
        case "left": return 180
        default: return 270
    }
}

HotwheelPointAngle(dx, dy) {
    if (dx = 0) {
        if (dy < 0)
            return 270
        return 90
    }

    rad := ATan(dy / dx)
    deg := rad * 180 / 3.141592653589793
    if (dx < 0)
        deg += 180
    else if (dy < 0)
        deg += 360
    return HotwheelNormalizeAngle(deg)
}

HotwheelAngleInSlice(angle, slice) {
    return HotwheelAngleBetweenRaw(angle, slice.rawStartDeg, slice.rawEndDeg)
}

HotwheelAngleBetweenRaw(angle, rawStartDeg, rawEndDeg) {
    span := rawEndDeg - rawStartDeg
    offset := HotwheelNormalizeAngle(angle - rawStartDeg)
    return (offset >= 0 && offset < span)
}

HotwheelNormalizeAngle(angle) {
    while (angle < 0)
        angle += 360
    while (angle >= 360)
        angle -= 360
    return angle
}
