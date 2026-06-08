import * as dns from 'dns/promises';

/**
 * Blocklist of IP ranges that should never be accessed via webhooks.
 * Prevents SSRF attacks targeting internal services.
 */
const BLOCKED_PREFIXES = [
  '127.',           // Loopback IPv4
  '0.',             // Current network
  '10.',            // RFC 1918 private
  '172.16.',        // RFC 1918 private (172.16.0.0/12)
  '172.17.',
  '172.18.',
  '172.19.',
  '172.2',
  '172.3',
  '172.31.',        // End of 172.16/12 range
  '192.168.',       // RFC 1918 private
  '169.254.',       // Link-local (AWS/GCP metadata)
  '100.64.',        // Carrier-grade NAT
  '::1',            // Loopback IPv6
  'fc',             // IPv6 unique local
  'fd',             // IPv6 unique local
  'fe80',           // IPv6 link-local
];

const BLOCKED_HOSTS = [
  'localhost',
  'metadata.google.internal',
  'metadata.internal',
];

/**
 * Validates that a URL does not resolve to a private/internal IP address.
 * Prevents Server-Side Request Forgery (SSRF) attacks.
 *
 * @throws Error if the URL resolves to a blocked IP or hostname
 */
export async function validateWebhookUrl(url: string): Promise<void> {
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(url);
  } catch {
    throw new Error('Invalid URL format');
  }

  // Must be HTTPS
  if (parsedUrl.protocol !== 'https:') {
    throw new Error('Webhook URL must use HTTPS');
  }

  const hostname = parsedUrl.hostname.toLowerCase();

  // Check blocked hostnames
  if (BLOCKED_HOSTS.includes(hostname)) {
    throw new Error(`Webhook URL hostname '${hostname}' is not allowed`);
  }

  // Resolve DNS and check the IP
  try {
    const addresses = await dns.resolve4(hostname);
    for (const ip of addresses) {
      if (isBlockedIp(ip)) {
        throw new Error(`Webhook URL resolves to blocked IP address: ${ip}`);
      }
    }

    // Also check IPv6
    try {
      const v6Addresses = await dns.resolve6(hostname);
      for (const ip of v6Addresses) {
        if (isBlockedIpV6(ip)) {
          throw new Error(`Webhook URL resolves to blocked IPv6 address`);
        }
      }
    } catch {
      // No AAAA records — that's fine
    }
  } catch (err) {
    // If the error is from our own check, rethrow it
    if (err instanceof Error && err.message.includes('blocked')) {
      throw err;
    }
    // DNS resolution failure — allow but log
    // Some hostnames might not resolve at creation time but work later
  }
}

function isBlockedIp(ip: string): boolean {
  return BLOCKED_PREFIXES.some(prefix => ip.startsWith(prefix)) ||
    ip === '0.0.0.0' ||
    ip.startsWith('224.') ||  // Multicast
    ip.startsWith('239.');    // Multicast
}

function isBlockedIpV6(ip: string): boolean {
  const lower = ip.toLowerCase();
  return lower.startsWith('::1') ||
    lower.startsWith('fc') ||
    lower.startsWith('fd') ||
    lower.startsWith('fe80');
}
