import * as Sentry from '@sentry/react'
import { createRoot } from 'react-dom/client'
import App from './App'
import './style.css'

// Sentry hanya aktif bila VITE_SENTRY_DSN diisi; tanpa DSN panel berjalan seperti biasa.
const dsn = import.meta.env.VITE_SENTRY_DSN
if (dsn) Sentry.init({ dsn, sendDefaultPii: false, environment: import.meta.env.MODE, tracesSampleRate: 0 })

createRoot(document.getElementById('root')).render(
  dsn ? <Sentry.ErrorBoundary fallback={<p>Terjadi kesalahan. Muat ulang halaman.</p>}><App /></Sentry.ErrorBoundary> : <App />
)
