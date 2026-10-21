// An album's pictures laid out in one bubble, as Telegram lays them out (tdesktop's
// grouped_layout.cpp, which Telegram-iOS's ChatMessageBubbleMosaicLayout follows): two, three
// and four by their shapes, five to ten in the rows that come nearest a 4:3 block.
// layout([{ w, h }], maxWidth, minWidth, spacing) -> { width, height, items: [{ x, y, w, h, sides }] },
// `sides` the block's edges each touches: "t", "r", "b", "l" (its corners there are round).
.pragma library

function layout(sizes, maxWidth, minWidth, spacing) {
    const ratios = sizes.map((s) => s.w / Math.max(s.h, 1))
    const shapes = ratios.map((r) => r > 1.2 ? "w" : r < 0.8 ? "n" : "q").join("")
    const L = { ratios: ratios, shapes: shapes, count: ratios.length, maxWidth: maxWidth, maxHeight: maxWidth,
                minWidth: minWidth, spacing: spacing,
                average: ratios.reduce((a, r) => a + r, 1) / ratios.length }   // (from 1, as Telegram counts)
    L.maxRatio = L.maxWidth / L.maxHeight
    let items
    if (L.count === 1)
        items = [box(0, 0, maxWidth, Math.round(maxWidth / ratios[0]), "tlbr")]
    else if (L.count === 2)
        items = two(L)
    else if (L.count === 3)
        items = three(L)
    else if (L.count === 4)
        items = four(L)
    else
        items = complex(L)
    let width = 0, height = 0
    for (const it of items) {
        width = Math.max(width, it.x + it.w)
        height = Math.max(height, it.y + it.h)
    }
    return { width: width, height: height, items: items }
}

function box(x, y, w, h, sides) {
    return { x: x, y: y, w: Math.max(w, 1), h: Math.max(h, 1), sides: sides }
}

function two(L) {
    const r = L.ratios, sp = L.spacing
    if (L.shapes === "ww" && L.average > 1.4 * L.maxRatio && r[1] - r[0] < 0.2) {      // one over the other
        const w = L.maxWidth
        const h = Math.round(Math.min(w / r[0], w / r[1], (L.maxHeight - sp) / 2))
        return [box(0, 0, w, h, "tlr"), box(0, h + sp, w, h, "blr")]
    }
    if (L.shapes === "ww" || L.shapes === "qq") {                                    // side by side, even
        const w = (L.maxWidth - sp) / 2
        const h = Math.round(Math.min(w / r[0], w / r[1], L.maxHeight))
        return [box(0, 0, w, h, "tlb"), box(w + sp, 0, w, h, "trb")]
    }
    const least = Math.round(L.minWidth * 1.5)                                       // side by side, by their shapes
    const second = Math.min(Math.round(Math.max(0.4 * (L.maxWidth - sp), (L.maxWidth - sp) / r[0] / (1 / r[0] + 1 / r[1]))),
                            L.maxWidth - sp - least)
    const first = L.maxWidth - second - sp
    const h = Math.min(L.maxHeight, Math.round(Math.min(first / r[0], second / r[1])))
    return [box(0, 0, first, h, "tlb"), box(first + sp, 0, second, h, "trb")]
}

function three(L) {
    const r = L.ratios, sp = L.spacing
    if (L.shapes[0] === "n") {                  // a tall one on the left, two on the right
        const h0 = L.maxHeight
        const h2 = Math.round(Math.min((L.maxHeight - sp) / 2, r[1] * (L.maxWidth - sp) / (r[2] + r[1])))
        const h1 = h0 - h2 - sp
        const right = Math.max(L.minWidth, Math.round(Math.min((L.maxWidth - sp) / 2, h2 * r[2], h1 * r[1])))
        const left = Math.min(Math.round(h0 * r[0]), L.maxWidth - sp - right)
        return [box(0, 0, left, h0, "tlb"), box(left + sp, 0, right, h1, "tr"), box(left + sp, h1 + sp, right, h2, "br")]
    }
    const w = L.maxWidth                        // a wide one on top, two under it
    const h0 = Math.round(Math.min(w / r[0], (L.maxHeight - sp) * 0.66))
    const half = (L.maxWidth - sp) / 2
    const h1 = Math.min(L.maxHeight - h0 - sp, Math.round(Math.min(half / r[1], half / r[2])))
    return [box(0, 0, w, h0, "tlr"), box(0, h0 + sp, half, h1, "lb"), box(half + sp, h0 + sp, w - half - sp, h1, "rb")]
}

function four(L) {
    const r = L.ratios, sp = L.spacing
    if (L.shapes[0] === "w") {                  // a wide one on top, three under it
        const w = L.maxWidth
        const h0 = Math.round(Math.min(w / r[0], (L.maxHeight - sp) * 0.66))
        let h = Math.round((L.maxWidth - 2 * sp) / (r[1] + r[2] + r[3]))
        const w0 = Math.max(L.minWidth, Math.round(Math.min((L.maxWidth - 2 * sp) * 0.4, h * r[1])))
        const w2 = Math.round(Math.max(L.minWidth, (L.maxWidth - 2 * sp) * 0.33, h * r[3]))
        const w1 = w - w0 - w2 - 2 * sp
        h = Math.min(L.maxHeight - h0 - sp, h)
        return [box(0, 0, w, h0, "tlr"), box(0, h0 + sp, w0, h, "lb"), box(w0 + sp, h0 + sp, w1, h, "b"),
                box(w0 + w1 + 2 * sp, h0 + sp, w2, h, "rb")]
    }
    const h = L.maxHeight                       // a tall one on the left, three on the right
    const w0 = Math.round(Math.min(h * r[0], (L.maxWidth - sp) * 0.6))
    let w = Math.round((L.maxHeight - 2 * sp) / (1 / r[1] + 1 / r[2] + 1 / r[3]))
    const h0 = Math.round(w / r[1])
    const h1 = Math.round(w / r[2])
    const h2 = h - h0 - h1 - 2 * sp
    w = Math.max(L.minWidth, Math.min(L.maxWidth - w0 - sp, w))
    return [box(0, 0, w0, h, "tlb"), box(w0 + sp, 0, w, h0, "tr"), box(w0 + sp, h0 + sp, w, h1, "r"),
            box(w0 + sp, h0 + h1 + 2 * sp, w, h2, "rb")]
}

// five and more: every way to put them in two, three or four rows (no more than three in a row,
// four in the middle one when they are tall), the one whose height comes nearest 4:3 taken
function complex(L) {
    const sp = L.spacing, maxW = L.maxWidth, maxH = maxW * 4 / 3, n = L.count
    const ratios = L.ratios.map((r) => L.average > 1.1 ? Math.min(Math.max(r, 1), 2.75) : Math.min(Math.max(r, 0.6667), 1))
    const rowHeight = (from, k) => {
        let sum = 0
        for (let i = from; i < from + k; i++)
            sum += ratios[i]
        return (maxW - (k - 1) * sp) / sum
    }
    const tries = []
    const attempt = (counts) => {
        let from = 0
        const heights = counts.map((k) => { const h = rowHeight(from, k); from += k; return h })
        tries.push({ counts: counts, heights: heights })
    }
    for (let a = 1; a < n; a++)
        if (a <= 3 && n - a <= 3)
            attempt([a, n - a])
    for (let a = 1; a < n - 1; a++)
        for (let b = 1; b < n - a; b++) {
            const c = n - a - b
            if (a <= 3 && b <= (L.average < 0.85 ? 4 : 3) && c <= 3)
                attempt([a, b, c])
        }
    for (let a = 1; a < n - 2; a++)
        for (let b = 1; b < n - a - 1; b++)
            for (let c = 1; c < n - a - b; c++) {
                const d = n - a - b - c
                if (a <= 3 && b <= 3 && c <= 3 && d <= 3)
                    attempt([a, b, c, d])
            }
    let best = null, bestDiff = 0
    for (const t of tries) {
        const total = sp * (t.heights.length - 1) + t.heights.reduce((s, h) => s + h, 0)
        const low = Math.min.apply(null, t.heights)
        const thin = low < L.minWidth ? 1.5 : 1
        const narrowing = t.counts.some((k, i) => i > 0 && t.counts[i - 1] > k) ? 1.5 : 1
        const diff = Math.abs(total - maxH) * thin * narrowing
        if (!best || diff < bestDiff) {
            best = t
            bestDiff = diff
        }
    }
    const items = []
    let y = 0, i = 0
    best.counts.forEach((k, row) => {
        const h = Math.round(best.heights[row])
        let x = 0
        for (let c = 0; c < k; c++, i++) {
            const w = c === k - 1 ? maxW - x : Math.round(ratios[i] * best.heights[row])
            const sides = (row === 0 ? "t" : "") + (row === best.counts.length - 1 ? "b" : "") +
                          (c === 0 ? "l" : "") + (c === k - 1 ? "r" : "")
            items.push(box(x, y, w, h, sides))
            x += w + sp
        }
        y += h + sp
    })
    return items
}
