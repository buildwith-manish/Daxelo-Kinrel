export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="min-h-dvh flex items-center justify-center bg-kinrel-bg p-6"
    >
      {children}
    </div>
  )
}
