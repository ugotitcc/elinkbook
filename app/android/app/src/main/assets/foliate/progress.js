// assign a unique ID for each TOC item
const assignIDs = toc => {
    let id = 0
    const assignID = item => {
        item.id = id++
        if (item.subitems) for (const subitem of item.subitems) assignID(subitem)
    }
    for (const item of toc) assignID(item)
    return toc
}

const flatten = items => items
    .map(item => item.subitems?.length
        ? [item, flatten(item.subitems)].flat()
        : item)
    .flat()

export class TOCProgress {
    async init({ toc, ids, splitHref, getFragment }) {
        assignIDs(toc)
        const items = flatten(toc)
        const grouped = new Map()
        for (const [i, item] of items.entries()) {
            const [id, fragment] = await splitHref(item?.href) ?? []
            const value = { fragment, item }
            if (grouped.has(id)) grouped.get(id).items.push(value)
            else grouped.set(id, { prev: items[i - 1], items: [value] })
        }
        const map = new Map()
        for (const [i, id] of ids.entries()) {
            if (grouped.has(id)) map.set(id, grouped.get(id))
            else map.set(id, map.get(ids[i - 1]))
        }
        this.ids = ids
        this.map = map
        this.getFragment = getFragment
    }
    getProgress(index, range) {
        if (!this.ids) return
        const id = this.ids[index]
        const obj = this.map.get(id)
        if (!obj) return null
        const { prev, items } = obj
        if (!items) return prev
        if (!range || items.length === 1 && !items[0].fragment) return items[0].item

        const doc = range.startContainer.getRootNode()
        for (const [i, { fragment }] of items.entries()) {
            const el = this.getFragment(doc, fragment)
            if (!el) continue
            if (range.comparePoint(el, 0) > 0)
                return (items[i - 1]?.item ?? prev)
        }
        return items[items.length - 1].item
    }
}

export class PageProgress {
    #book
    #cache = new Map()
    #resolveNavigation

    constructor(book, resolveNavigation) {
        this.#book = book
        this.#resolveNavigation = resolveNavigation
    }

    async #getCache(index) {
        let cached = this.#cache.get(index)
        if (cached) return cached

        const section = this.#book.sections[index]
        if (!section?.createDocument) return null

        const doc = await section.createDocument()
        const root = doc.body ?? doc.documentElement
        const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT)
        const nodes = []
        const offsets = []
        let total = 0
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const len = node.nodeValue?.length ?? 0
            nodes.push(node)
            offsets.push(total)
            total += len
        }

        cached = { doc, nodes, offsets, total }
        this.#cache.set(index, cached)
        return cached
    }

    async getProgress(cfi) {
        try {
            const nav = this.#resolveNavigation(cfi)
            if (!nav) return null

            const { index, anchor } = nav
            if (index == null || !anchor) return null

            const cached = await this.#getCache(index)
            if (!cached) return null

            const { doc, nodes, offsets, total } = cached
            const frag = anchor(doc)
            if (!frag) return null

            const isRange = frag instanceof Range
            const range = isRange ? frag : doc.createRange()
            if (!isRange) range.selectNodeContents(frag)

            const offset = this.#findOffset(range, nodes, offsets, total)
            return {
                fraction: total > 0 ? offset / total : 0,
                index,
            }
        } catch (e) {
            console.error(e)
            return null
        }
    }

    #findOffset(range, nodes, offsets, total) {
        if (!nodes.length) return 0
        const container = range.startContainer
        // fast path: startContainer is a text node in the index
        if (container.nodeType === Node.TEXT_NODE) {
            const i = this.#bsearchNode(container, nodes)
            if (i >= 0) return offsets[i] + range.startOffset
        }
        // element container: collapse to start and binary search
        const collapsed = range.cloneRange()
        collapsed.collapse(true)
        const i = this.#bsearchCollapsed(collapsed, nodes)
        return i >= 0 ? offsets[i] : total
    }

    // binary search for an exact text node by document position
    #bsearchNode(target, nodes) {
        let low = 0, high = nodes.length - 1
        while (low <= high) {
            const mid = (low + high) >> 1
            const node = nodes[mid]
            if (node === target) return mid
            const pos = node.compareDocumentPosition(target)
            if (pos & Node.DOCUMENT_POSITION_FOLLOWING) low = mid + 1
            else high = mid - 1
        }
        return -1
    }

    // binary search for the first text node at or after a collapsed range point
    // collapsed.comparePoint returns: -1 = node is before, 1 = node is at/after
    #bsearchCollapsed(collapsed, nodes) {
        let low = 0, high = nodes.length - 1, result = -1
        while (low <= high) {
            const mid = (low + high) >> 1
            if (collapsed.comparePoint(nodes[mid], 0) > 0) {
                result = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return result
    }
}

export class SectionProgress {
    #density = new Map()
    #pagesForSection
    #cumulativePagesBefore
    #pagesTotal

    constructor(sections, sizePerLoc, sizePerTimeUnit) {
        this.sizes = sections.map(s => s.linear != 'no' && s.size > 0 ? s.size : 0)
        this.sizePerLoc = sizePerLoc
        this.sizePerTimeUnit = sizePerTimeUnit
        this.sizeTotal = this.sizes.reduce((a, b) => a + b, 0)
        this.sectionFractions = this.#getSectionFractions()
        this.#recomputePages()
    }
    #getSectionFractions() {
        const { sizeTotal } = this
        const results = [0]
        let sum = 0
        for (const size of this.sizes) results.push((sum += size) / sizeTotal)
        return results
    }
    // epic-26-architecture-hardening Issue 11：某個 section 完成渲染、量到
    // 真實視覺頁數（View.expand() 的 contentPages）時記錄下來，取代該
    // section 原本「位元組數 / sizePerLoc」的估計值。非線性
    // （linear='no'，sizes[index] 恆為 0）section 忽略，避免外插公式
    // 除以 0（見 plans/plan-issue-11.md 規劃階段查證第 5 點）。
    recordDensity(index, contentPages) {
        if (!(this.sizes[index] > 0)) return
        if (this.#density.get(index) === contentPages) return
        this.#density.set(index, contentPages)
        this.#recomputePages()
    }
    // 排版設定變更（字級/行距/邊距/欄數/螢幕方向/直橫排）時，已記錄的密度
    // 全數失真，整包清空、退回統一常數估計，等使用者繼續翻頁重新累積。
    clearDensity() {
        if (this.#density.size === 0) return
        this.#density.clear()
        this.#recomputePages()
    }
    #nearestKnownIndex(index) {
        let nearest = null, nearestDist = Infinity
        for (const known of this.#density.keys()) {
            const dist = Math.abs(known - index)
            if (dist < nearestDist || (dist === nearestDist && known < nearest)) {
                nearest = known
                nearestDist = dist
            }
        }
        return nearest
    }
    // 依目前已知密度重新算出「每個 section 換算後的頁數」與其累積和：
    // 已知 section 直接採用實測值；未知 section 套用「章節索引距離最近的
    // 已知 section」之密度比例外插；完全沒有任何已知密度時，逐 section
    // 退回原本「位元組數 / sizePerLoc」的估計值（與 Issue 11 之前的行為
    // 逐位元組等價，見 plans/plan-issue-11.md 規劃階段查證第 4 點）。
    #recomputePages() {
        const { sizes, sizePerLoc } = this
        const pagesForSection = sizes.map((size, index) => {
            if (size <= 0) return 0
            if (this.#density.has(index)) return this.#density.get(index)
            if (this.#density.size === 0) return size / sizePerLoc
            const nearest = this.#nearestKnownIndex(index)
            return size * (this.#density.get(nearest) / sizes[nearest])
        })
        const cumulativePagesBefore = [0]
        let sum = 0
        for (const pages of pagesForSection) cumulativePagesBefore.push(sum += pages)
        this.#pagesForSection = pagesForSection
        this.#cumulativePagesBefore = cumulativePagesBefore
        this.#pagesTotal = sum
    }
    // get progress given index of and fractions within a section
    getProgress(index, fractionInSection, pageFraction = 0) {
        const { sizes, sizePerLoc, sizePerTimeUnit, sizeTotal } = this
        const sizeInSection = sizes[index] ?? 0
        const sizeBefore = sizes.slice(0, index).reduce((a, b) => a + b, 0)
        const size = sizeBefore + fractionInSection * sizeInSection
        const nextSize = size + pageFraction * sizeInSection
        const remainingTotal = sizeTotal - size
        const remainingSection = (1 - fractionInSection) * sizeInSection
        // epic-26-architecture-hardening Issue 11 審查修正（Important #1，
        // reviews/review-issue-11.md）：完全沒有任何已知密度時，直接沿用
        // 改動前「位元組數一次性相除」的公式，不經過 #pagesForSection 逐
        // section 除法後再加總——IEEE754 浮點數加法不具結合律，逐 section
        // 相加在極少數情況下會產生跨越 Math.floor/Math.ceil 整數邊界的誤
        // 差，讓零回歸不變式在數學上嚴格成立，而非僅絕大多數情況成立。
        const noKnownDensity = this.#density.size === 0
        const pagesInSection = this.#pagesForSection[index] ?? 0
        const pagesBeforeSection = this.#cumulativePagesBefore[index] ?? 0
        const current = noKnownDensity
            ? size / sizePerLoc
            : pagesBeforeSection + fractionInSection * pagesInSection
        const next = noKnownDensity
            ? nextSize / sizePerLoc
            : current + pageFraction * pagesInSection
        const total = noKnownDensity ? sizeTotal / sizePerLoc : this.#pagesTotal
        return {
            fraction: nextSize / sizeTotal,
            section: {
                current: index,
                total: sizes.length,
            },
            location: {
                current: Math.floor(current),
                next: Math.floor(next),
                total: Math.ceil(total),
            },
            time: {
                section: remainingSection / sizePerTimeUnit,
                total: remainingTotal / sizePerTimeUnit,
            },
        }
    }
    // the inverse of `getProgress`
    // get index of and fraction in section based on total fraction
    getSection(fraction) {
        if (fraction <= 0) return [0, 0]
        if (fraction >= 1) return [this.sizes.length - 1, 1]
        fraction = fraction + Number.EPSILON
        const { sizeTotal } = this
        let index = this.sectionFractions.findIndex(x => x > fraction) - 1
        if (index < 0) return [0, 0]
        while (!this.sizes[index]) index++
        const fractionInSection = (fraction - this.sectionFractions[index])
            / (this.sizes[index] / sizeTotal)
        return [index, fractionInSection]
    }
}
