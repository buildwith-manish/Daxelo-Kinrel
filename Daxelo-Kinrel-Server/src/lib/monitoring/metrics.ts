// DAXELO KINREL — Monitoring Metrics
// Pack 02: Support & Operations

export interface ApiMetric {
  route: string
  method: string
  statusCode: number
  duration: number
  error?: boolean
}

/**
 * Track an API metric in DogStatsD-compatible format.
 * In production, these would be sent via the Datadog agent's DogStatsD interface.
 */
export function trackApiMetric(metric: ApiMetric): void {
  const tags = [
    `route:${metric.route}`,
    `method:${metric.method}`,
    `status:${metric.statusCode}`,
    `error:${metric.error ?? false}`,
  ]

  // DogStatsD-compatible metric output (picked up by Datadog agent)
  console.log(`daxelo.api.request.duration:${metric.duration}|ms|#${tags.join(',')}`)
  console.log(`daxelo.api.request.count:1|c|#${tags.join(',')}`)

  if (metric.error) {
    console.log(`daxelo.api.error.count:1|c|#${tags.join(',')}`)
  }
}

/**
 * Track a business metric.
 */
export function trackBusinessMetric(name: string, value: number, tags?: Record<string, string>): void {
  const tagStr = tags ? `|#${Object.entries(tags).map(([k, v]) => `${k}:${v}`).join(',')}` : ''
  console.log(`daxelo.business.${name}:${value}|g${tagStr}`)
}

/**
 * Higher-order function to wrap API route handlers with monitoring.
 * Tracks request duration, status code, and errors.
 */
export function withMonitoring<T extends (...args: unknown[]) => Promise<unknown>>(
  handler: T
): T {
  return ((...args: unknown[]) => {
    const start = Date.now()
    const request = args[0] as { nextUrl?: { pathname: string }; method?: string }

    const route = request?.nextUrl?.pathname ?? 'unknown'
    const method = request?.method ?? 'GET'

    return handler(...args).then((response: unknown) => {
      const duration = Date.now() - start
      const statusCode = (response as { status?: number })?.status ?? 200

      trackApiMetric({ route, method, statusCode, duration })

      return response
    }).catch((error: unknown) => {
      const duration = Date.now() - start

      trackApiMetric({ route, method, statusCode: 500, duration, error: true })

      throw error
    })
  }) as T
}

/**
 * Health check helper — tests various system components.
 */
export async function getComponentHealth(): Promise<{
  name: string
  healthy: boolean
  responseTime: number
}[]> {
  const results: { name: string; healthy: boolean; responseTime: number }[] = []

  // API health
  const apiStart = Date.now()
  results.push({ name: 'api', healthy: true, responseTime: Date.now() - apiStart })

  // Database health
  const dbStart = Date.now()
  try {
    const { db } = await import('@/lib/db')
    await db.$queryRaw`SELECT 1`
    results.push({ name: 'database', healthy: true, responseTime: Date.now() - dbStart })
  } catch {
    results.push({ name: 'database', healthy: false, responseTime: Date.now() - dbStart })
  }

  // Socket.io health (simulated)
  results.push({ name: 'socketio', healthy: true, responseTime: 2 })

  // WhatsApp health (simulated)
  results.push({ name: 'whatsapp', healthy: true, responseTime: 15 })

  // CDN health (simulated)
  results.push({ name: 'cdn', healthy: true, responseTime: 8 })

  // Matrimonial service (simulated)
  results.push({ name: 'matrimonial', healthy: true, responseTime: 5 })

  // Payment processing (simulated)
  results.push({ name: 'payments', healthy: true, responseTime: 12 })

  return results
}
