'use client';

import { useFocusTrap, useFocusOnMount } from '@/hooks/use-accessibility';

// ── Skip to Content Link ──────────────────────────────────────────
export function SkipToContent() {
  return (
    <a
      href="#main-content"
      className="sr-only focus:not-sr-only focus:absolute focus:z-[100] focus:top-2 focus:left-2 focus:px-4 focus:py-2 focus:rounded-xl focus:bg-[#F97316] focus:text-white focus:font-semibold focus:shadow-lg focus:outline-none focus:ring-2 focus:ring-[#F97316] focus:ring-offset-2"
    >
      Skip to main content
    </a>
  );
}

// ── Accessible Dialog Wrapper ──────────────────────────────────────
type AccessibleDialogProps = {
  children: React.ReactNode;
  isOpen: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  className?: string;
};

export function AccessibleDialog({
  children,
  isOpen,
  onClose,
  title,
  description,
  className = '',
}: AccessibleDialogProps) {
  const trapRef = useFocusTrap(isOpen);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label={title}
      aria-describedby={description ? 'dialog-desc' : undefined}
    >
      <div
        ref={trapRef}
        className={`bg-white dark:bg-[#1C1917] rounded-2xl shadow-2xl border border-[#FED7AA] dark:border-[#44403C] max-w-lg w-full mx-4 p-6 ${className}`}
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="text-lg font-bold text-[#1C1917] dark:text-[#F5F5F4] mb-1">{title}</h2>
        {description && (
          <p id="dialog-desc" className="text-sm text-[#57534E] dark:text-[#A8A29E] mb-4">{description}</p>
        )}
        {children}
      </div>
    </div>
  );
}

// ── Accessible Card ────────────────────────────────────────────────
type AccessibleCardProps = {
  children: React.ReactNode;
  title: string;
  role?: 'article' | 'region' | 'group';
  interactive?: boolean;
  onClick?: () => void;
  className?: string;
};

export function AccessibleCard({
  children,
  title,
  role = 'region',
  interactive = false,
  onClick,
  className = '',
}: AccessibleCardProps) {
  const Component = interactive ? 'button' : 'div';
  return (
    <Component
      role={role}
      aria-label={title}
      onClick={onClick}
      tabIndex={interactive ? 0 : undefined}
      className={`rounded-2xl border border-[#FED7AA] dark:border-[#44403C] bg-white dark:bg-[#1C1917] shadow-lg p-4 ${
        interactive
          ? 'cursor-pointer hover:shadow-xl hover:border-[#F97316] focus:outline-none focus:ring-2 focus:ring-[#F97316] focus:ring-offset-2 transition-all duration-200'
          : ''
      } ${className}`}
    >
      {children}
    </Component>
  );
}

// ── Accessible Form Field ──────────────────────────────────────────
type AccessibleFieldProps = {
  children: React.ReactNode;
  label: string;
  hint?: string;
  error?: string;
  required?: boolean;
  id: string;
};

export function AccessibleField({
  children,
  label,
  hint,
  error,
  required = false,
  id,
}: AccessibleFieldProps) {
  return (
    <div className="space-y-1.5">
      <label
        htmlFor={id}
        className="text-sm font-medium text-[#1C1917] dark:text-[#F5F5F4] flex items-center gap-1"
      >
        {label}
        {required && <span className="text-[#EF4444]" aria-hidden="true">*</span>}
      </label>
      {children}
      {hint && !error && (
        <p id={`${id}-hint`} className="text-xs text-[#78716C] dark:text-[#A8A29E]">{hint}</p>
      )}
      {error && (
        <p id={`${id}-error`} className="text-xs text-[#EF4444]" role="alert">{error}</p>
      )}
    </div>
  );
}

// ── Live Region ───────────────────────────────────────────────────
type LiveRegionProps = {
  children: React.ReactNode;
  politeness?: 'polite' | 'assertive';
  className?: string;
};

export function LiveRegion({
  children,
  politeness = 'polite',
  className = '',
}: LiveRegionProps) {
  return (
    <div
      role="status"
      aria-live={politeness}
      aria-atomic="true"
      className={`sr-only ${className}`}
    >
      {children}
    </div>
  );
}
