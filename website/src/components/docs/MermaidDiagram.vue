<script setup>
import { nextTick, onMounted, ref, watch } from 'vue'

const props = defineProps({
  chart: {
    type: String,
    required: true,
  },
  title: {
    type: String,
    default: '',
  },
})

const host = ref(null)
const error = ref('')

let renderVersion = 0

async function renderChart() {
  const version = renderVersion + 1
  renderVersion = version
  error.value = ''

  await nextTick()

  if (!host.value) {
    return
  }

  try {
    const mermaid = (await import('mermaid')).default

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'neutral',
      fontFamily: 'IBM Plex Sans, Segoe UI, sans-serif',
    })

    const { svg } = await mermaid.render(`grammar-mermaid-${version}`, props.chart)

    if (version !== renderVersion || !host.value) {
      return
    }

    host.value.innerHTML = svg
  } catch (cause) {
    if (version !== renderVersion) {
      return
    }

    const message = cause instanceof Error ? cause.message : 'Unknown Mermaid render error'
    error.value = message

    if (host.value) {
      host.value.innerHTML = ''
    }
  }
}

onMounted(() => {
  renderChart()
})

watch(() => props.chart, () => {
  renderChart()
})
</script>

<template>
  <figure class="mermaid-block">
    <div
      ref="host"
      class="mermaid-surface"
      :aria-label="title || 'Mermaid diagram'"
      role="img"
    />
    <figcaption v-if="title" class="mermaid-caption">{{ title }}</figcaption>
    <p v-if="error" class="mermaid-error">Mermaid 渲染失败：{{ error }}</p>
  </figure>
</template>

<style scoped>
.mermaid-block {
  margin: 20px 0 28px;
}

.mermaid-surface {
  overflow-x: auto;
  padding: 18px;
  border: 1px solid var(--line);
  border-radius: var(--radius-lg);
  background:
    radial-gradient(circle at top right, rgba(15, 98, 254, 0.08), transparent 34%),
    var(--surface-2);
  box-shadow: var(--shadow-sm);
}

.mermaid-surface :deep(svg) {
  display: block;
  min-width: 620px;
  max-width: 100%;
  height: auto;
  margin: 0 auto;
}

.mermaid-caption {
  margin-top: 10px;
  font-size: 13px;
  color: var(--text-soft);
  text-align: center;
}

.mermaid-error {
  margin-top: 12px;
  color: var(--danger);
}

@media (max-width: 700px) {
  .mermaid-surface {
    padding: 12px;
  }

  .mermaid-surface :deep(svg) {
    min-width: 520px;
  }
}
</style>