import { createApp } from 'vue'
import './style.css'
import './assets/editorDslHighlight.css'
import './assets/responsive.css'
import App from './App.vue'
import router from './router/index.js'

createApp(App).use(router).mount('#app')
