<script setup>
import { ref, computed, onUnmounted } from 'vue'

const props = defineProps({
  direction:    { type: String,  default: 'horizontal' },
  initialSplit: { type: Number,  default: 0.5 },
  minSize:      { type: Number,  default: 160 },
})

const isHorizontal = computed(() => props.direction === 'horizontal')

const split = ref(props.initialSplit)

const containerRef = ref(null)

const gridTemplate = computed(() => {
  const pct = (split.value * 100).toFixed(2)
  const rest = (100 - split.value * 100).toFixed(2)
  return isHorizontal.value
    ? `${pct}% 6px ${rest}%`
    : `${pct}% 6px ${rest}%`
})

const containerStyle = computed(() => {
  return isHorizontal.value
    ? { display: 'grid', gridTemplateColumns: gridTemplate.value, width: '100%', height: '100%' }
    : { display: 'grid', gridTemplateRows:    gridTemplate.value, width: '100%', height: '100%' }
})

let dragging = false

function clampSplit(newSplit, totalPx) {
  const minFrac = props.minSize / totalPx
  return Math.max(minFrac, Math.min(1 - minFrac, newSplit))
}

function onGutterPointerDown(e) {
  e.preventDefault()
  dragging = true
  e.target.setPointerCapture(e.pointerId)
}

function onPointerMove(e) {
  if (!dragging || !containerRef.value) return
  const rect = containerRef.value.getBoundingClientRect()
  let newSplit
  if (isHorizontal.value) {
    newSplit = (e.clientX - rect.left) / rect.width
    split.value = clampSplit(newSplit, rect.width)
  } else {
    newSplit = (e.clientY - rect.top) / rect.height
    split.value = clampSplit(newSplit, rect.height)
  }
}

function onPointerUp() {
  dragging = false
}

onUnmounted(() => { dragging = false })
</script>

<template>
  <div
    ref="containerRef"
    class="split-pane"
    :style="containerStyle"
    @pointermove="onPointerMove"
    @pointerup="onPointerUp"
  >
    <div class="split-pane__first">
      <slot name="first" />
    </div>

    <div
      class="split-pane__gutter"
      :class="isHorizontal ? 'split-pane__gutter--h' : 'split-pane__gutter--v'"
      @pointerdown="onGutterPointerDown"
    >
      <span class="gutter-dots" />
    </div>

    <div class="split-pane__second">
      <slot name="second" />
    </div>
  </div>
</template>

<style scoped>
.split-pane {
  overflow: hidden;
  position: relative;
  box-sizing: border-box;
}

.split-pane__first,
.split-pane__second {
  overflow: hidden;
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.split-pane__gutter {
  background: transparent;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: opacity 0.18s ease;
  z-index: 10;
  touch-action: none;
  user-select: none;
}
.split-pane__gutter::before {
  content: '';
  position: absolute;
  inset: 1px 2px;
  border-radius: 999px;
  background: var(--line);
  opacity: 0.9;
}
.split-pane__gutter:hover,
.split-pane__gutter:active {
  opacity: 1;
}

.split-pane__gutter--h {
  cursor: col-resize;
  width: 10px;
}
.split-pane__gutter--v {
  cursor: row-resize;
  height: 10px;
}

.gutter-dots {
  display: block;
  width: 2px;
  height: 26px;
  border-radius: 999px;
  background: var(--text-soft);
  opacity: 0.7;
}
.split-pane__gutter--v .gutter-dots {
  width: 26px;
  height: 2px;
}

.split-pane__gutter:hover .gutter-dots,
.split-pane__gutter:active .gutter-dots {
  background: var(--accent);
  opacity: 0.85;
}
</style>
