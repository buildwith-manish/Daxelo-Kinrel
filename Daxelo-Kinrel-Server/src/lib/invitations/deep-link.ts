// DAXELO KINREL — Deep Link Generator
// Pack 04: WhatsApp Platform

/**
 * Generates a deep link for a family invitation.
 * Uses NEXT_PUBLIC_APP_URL environment variable or falls back to 'https://daxelo.app'.
 *
 * @param invitationId - The database ID of the invitation
 * @param token - The unique invitation token used in the URL
 * @returns The full deep link URL (e.g. https://daxelo.app/invite/abc123)
 */
export function generateInviteDeepLink(invitationId: string, token: string): string {
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || 'https://daxelo.app'
  return `${baseUrl}/invite/${token}`
}

/**
 * Generates a WhatsApp share URL with a pre-filled message.
 * The message is a Hindi/English mix that includes the inviter name,
 * family name, and the deep link to join.
 *
 * @param deepLink - The invitation deep link URL
 * @param familyName - The name of the family being invited to
 * @param inviterName - The name of the person sending the invitation
 * @returns A WhatsApp URL (https://wa.me/?text=...) ready to open
 */
export function generateWhatsAppShareUrl(
  deepLink: string,
  familyName: string,
  inviterName: string
): string {
  const message = [
    `🙏 ${inviterName} has invited you to join the *${familyName}* family on Daxelo Kinrel!`,
    '',
    'Tap the link below to accept and start building your family tree together:',
    deepLink,
    '',
    '🌱 One family. One tree. Infinite connections.',
  ].join('\n')

  return `https://wa.me/?text=${encodeURIComponent(message)}`
}

/**
 * Generates the URL for the share card page with Open Graph preview.
 * This URL, when shared on WhatsApp, will render a rich preview card
 * with OG meta tags (title, description, image).
 *
 * @param token - The shareable link token
 * @returns The full URL to the share card preview page
 */
export function generateShareCardUrl(token: string): string {
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL || 'https://daxelo.app'
  return `${baseUrl}/api/share/${token}`
}
