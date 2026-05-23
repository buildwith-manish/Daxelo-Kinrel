'use client'

import React, { useState, useRef, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

interface AnimatedTextFieldProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string
  error?: string
  success?: boolean
  characterCount?: { current: number; max: number }
  leftIcon?: React.ReactNode
  rightIcon?: React.ReactNode
}

export function AnimatedTextField({
  label,
  error,
  success,
  characterCount,
  leftIcon,
  rightIcon,
  className = '',
  onFocus,
  onBlur,
  ...props
}: AnimatedTextFieldProps) {
  const [isFocused, setIsFocused] = useState(false)

  const handleFocus = useCallback((e: React.FocusEvent<HTMLInputElement>) => {
    setIsFocused(true)
    onFocus?.(e)
  }, [onFocus])

  const handleBlur = useCallback((e: React.FocusEvent<HTMLInputElement>) => {
    setIsFocused(false)
    onBlur?.(e)
  }, [onBlur])

  const borderColor = error
    ? 'border-red-500'
    : success
      ? 'border-green-500'
      : isFocused
        ? 'border-orange-500'
        : 'border-stone-300 dark:border-stone-600'

  return (
    <div className={`relative ${className}`}>
      <motion.label
        className={`block text-sm font-medium mb-1 transition-colors ${
          error ? 'text-red-500' : isFocused ? 'text-orange-600' : 'text-muted-foreground'
        }`}
        animate={{ scale: isFocused ? 1.02 : 1 }}
        transition={{ duration: 0.15 }}
      >
        {label}
      </motion.label>

      <motion.div
        className="relative"
        animate={
          error
            ? { x: [0, -4, 4, -4, 0] }
            : undefined
        }
        transition={error ? { duration: 0.3 } : undefined}
      >
        <div className="relative flex items-center">
          {leftIcon && (
            <span className="absolute left-3 text-muted-foreground">{leftIcon}</span>
          )}
          <input
            {...props}
            className={`w-full rounded-lg border-2 ${borderColor} bg-white dark:bg-stone-800 px-3 py-2 text-sm outline-none transition-all ${
              leftIcon ? 'pl-10' : ''
            } ${rightIcon ? 'pr-10' : ''}`}
            onFocus={handleFocus}
            onBlur={handleBlur}
          />
          {rightIcon && (
            <span className="absolute right-3 text-muted-foreground">{rightIcon}</span>
          )}
        </div>
      </motion.div>

      <AnimatePresence>
        {error && (
          <motion.p
            initial={{ opacity: 0, y: -5, height: 0 }}
            animate={{ opacity: 1, y: 0, height: 'auto' }}
            exit={{ opacity: 0, y: -5, height: 0 }}
            transition={{ duration: 0.2 }}
            className="text-xs text-red-500 mt-1"
          >
            {error}
          </motion.p>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {success && !error && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.8 }}
            transition={{ duration: 0.1 }}
            className="absolute right-0 top-0 mt-7 mr-3"
          >
            <svg className="w-4 h-4 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {characterCount && (
          <motion.p
            initial={{ opacity: 0, y: -5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
            className={`text-xs mt-1 text-right ${
              characterCount.current > characterCount.max
                ? 'text-red-500'
                : 'text-muted-foreground'
            }`}
          >
            {characterCount.current}/{characterCount.max}
          </motion.p>
        )}
      </AnimatePresence>
    </div>
  )
}

interface AnimatedDropdownProps {
  label: string
  value: string
  options: { value: string; label: string }[]
  onChange: (value: string) => void
  placeholder?: string
  error?: string
  className?: string
}

export function AnimatedDropdown({
  label,
  value,
  options,
  onChange,
  placeholder = 'Select...',
  error,
  className = '',
}: AnimatedDropdownProps) {
  const [isOpen, setIsOpen] = useState(false)
  const selectedOption = options.find(o => o.value === value)

  return (
    <div className={`relative ${className}`}>
      <label className="block text-sm font-medium text-muted-foreground mb-1">{label}</label>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className={`w-full rounded-lg border-2 ${
          isOpen ? 'border-orange-500' : 'border-stone-300 dark:border-stone-600'
        } bg-white dark:bg-stone-800 px-3 py-2 text-sm text-left flex items-center justify-between transition-colors`}
      >
        <span className={selectedOption ? 'text-foreground' : 'text-muted-foreground'}>
          {selectedOption?.label || placeholder}
        </span>
        <motion.svg
          className="w-4 h-4 text-muted-foreground"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          animate={{ rotate: isOpen ? 180 : 0 }}
          transition={{ duration: 0.2 }}
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </motion.svg>
      </button>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: -8, scaleY: 0.95 }}
            animate={{ opacity: 1, y: 0, scaleY: 1 }}
            exit={{ opacity: 0, y: -8, scaleY: 0.95 }}
            transition={{ duration: 0.2 }}
            className="absolute z-50 mt-1 w-full rounded-lg border border-stone-200 dark:border-stone-700 bg-white dark:bg-stone-800 shadow-lg overflow-hidden origin-top"
          >
            {options.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onChange(option.value)
                  setIsOpen(false)
                }}
                className={`w-full text-left px-3 py-2 text-sm hover:bg-orange-50 dark:hover:bg-stone-700 transition-colors ${
                  option.value === value ? 'bg-orange-50 dark:bg-stone-700 text-orange-600 font-medium' : 'text-foreground'
                }`}
              >
                {option.label}
              </button>
            ))}
          </motion.div>
        )}
      </AnimatePresence>

      {error && <p className="text-xs text-red-500 mt-1">{error}</p>}
    </div>
  )
}

interface AnimatedDatePickerProps {
  label: string
  value?: Date
  onChange: (date: Date) => void
  minDate?: Date
  maxDate?: Date
  error?: string
  className?: string
}

export function AnimatedDatePicker({
  label,
  value,
  onChange,
  minDate,
  maxDate,
  error,
  className = '',
}: AnimatedDatePickerProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [viewDate, setViewDate] = useState(value || new Date())
  const formattedValue = value
    ? value.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
    : 'Select date...'

  const year = viewDate.getFullYear()
  const month = viewDate.getMonth()
  const firstDay = new Date(year, month, 1).getDay()
  const daysInMonth = new Date(year, month + 1, 0).getDate()

  const days: (number | null)[] = []
  for (let i = 0; i < firstDay; i++) days.push(null)
  for (let i = 1; i <= daysInMonth; i++) days.push(i)

  const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ]

  const isSelected = (day: number) => {
    if (!value) return false
    return value.getFullYear() === year && value.getMonth() === month && value.getDate() === day
  }

  return (
    <div className={`relative ${className}`}>
      <label className="block text-sm font-medium text-muted-foreground mb-1">{label}</label>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className={`w-full rounded-lg border-2 ${
          isOpen ? 'border-orange-500' : 'border-stone-300 dark:border-stone-600'
        } bg-white dark:bg-stone-800 px-3 py-2 text-sm text-left transition-colors`}
      >
        <span className={value ? 'text-foreground' : 'text-muted-foreground'}>{formattedValue}</span>
      </button>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.2 }}
            className="absolute z-50 mt-1 bg-white dark:bg-stone-800 rounded-lg border border-stone-200 dark:border-stone-700 shadow-lg p-3 w-72"
          >
            <div className="flex items-center justify-between mb-2">
              <button
                type="button"
                onClick={() => setViewDate(new Date(year, month - 1, 1))}
                className="p-1 rounded hover:bg-stone-100 dark:hover:bg-stone-700"
              >
                &larr;
              </button>
              <span className="text-sm font-medium">
                {monthNames[month]} {year}
              </span>
              <button
                type="button"
                onClick={() => setViewDate(new Date(year, month + 1, 1))}
                className="p-1 rounded hover:bg-stone-100 dark:hover:bg-stone-700"
              >
                &rarr;
              </button>
            </div>

            <div className="grid grid-cols-7 gap-0.5 text-center">
              {['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map(d => (
                <div key={d} className="text-xs text-muted-foreground py-1">{d}</div>
              ))}
              {days.map((day, i) => (
                <div key={i} className="h-8">
                  {day !== null && (
                    <motion.button
                      type="button"
                      whileTap={{ scale: 0.9 }}
                      onClick={() => {
                        onChange(new Date(year, month, day))
                        setIsOpen(false)
                      }}
                      className={`w-8 h-8 rounded-full text-xs flex items-center justify-center transition-colors ${
                        isSelected(day)
                          ? 'bg-orange-500 text-white font-bold'
                          : 'hover:bg-orange-50 dark:hover:bg-stone-700'
                      }`}
                    >
                      {day}
                    </motion.button>
                  )}
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {error && <p className="text-xs text-red-500 mt-1">{error}</p>}
    </div>
  )
}
