'use client'

import React, { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

interface NavItem {
  id: string
  label: string
  icon: React.ReactNode
}

interface AnimatedBottomNavProps {
  items: NavItem[]
  activeId: string
  onChange: (id: string) => void
}

export function AnimatedBottomNav({ items, activeId, onChange }: AnimatedBottomNavProps) {
  return (
    <nav className="flex items-center justify-around bg-white dark:bg-stone-800 border-t border-stone-200 dark:border-stone-700 px-2 py-1">
      {items.map((item) => {
        const isActive = item.id === activeId
        return (
          <button
            key={item.id}
            onClick={() => onChange(item.id)}
            className="relative flex flex-col items-center justify-center px-3 py-1.5 min-w-[56px]"
          >
            <motion.div
              animate={{
                scale: isActive ? 1.15 : 1,
                y: isActive ? -2 : 0,
              }}
              transition={{ type: 'spring', stiffness: 400, damping: 20 }}
              className={isActive ? 'text-orange-500' : 'text-muted-foreground'}
            >
              {item.icon}
            </motion.div>
            <AnimatePresence>
              {isActive && (
                <motion.span
                  initial={{ opacity: 0, y: 4, height: 0 }}
                  animate={{ opacity: 1, y: 0, height: 'auto' }}
                  exit={{ opacity: 0, y: 4, height: 0 }}
                  transition={{ duration: 0.2 }}
                  className="text-[10px] font-medium text-orange-500 mt-0.5"
                >
                  {item.label}
                </motion.span>
              )}
            </AnimatePresence>
            {isActive && (
              <motion.div
                layoutId="nav-indicator"
                className="absolute -top-1 left-1/2 -translate-x-1/2 w-8 h-0.5 rounded-full bg-orange-500"
                transition={{ type: 'spring', stiffness: 400, damping: 30 }}
              />
            )}
          </button>
        )
      })}
    </nav>
  )
}

interface TabItem {
  id: string
  label: string
}

interface AnimatedTabBarProps {
  tabs: TabItem[]
  activeId: string
  onChange: (id: string) => void
}

export function AnimatedTabBar({ tabs, activeId, onChange }: AnimatedTabBarProps) {
  return (
    <div className="relative flex border-b border-stone-200 dark:border-stone-700">
      {tabs.map((tab) => {
        const isActive = tab.id === activeId
        return (
          <button
            key={tab.id}
            onClick={() => onChange(tab.id)}
            className={`relative px-4 py-2 text-sm font-medium transition-colors ${
              isActive ? 'text-orange-600' : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab.label}
            {isActive && (
              <motion.div
                layoutId="tab-indicator"
                className="absolute bottom-0 left-0 right-0 h-0.5 bg-orange-500"
                transition={{ type: 'spring', stiffness: 400, damping: 30 }}
              />
            )}
          </button>
        )
      })}
    </div>
  )
}

interface AnimatedDrawerProps {
  isOpen: boolean
  onClose: () => void
  title?: string
  children: React.ReactNode
  side?: 'left' | 'right'
}

export function AnimatedDrawer({
  isOpen,
  onClose,
  title,
  children,
  side = 'left',
}: AnimatedDrawerProps) {
  const slideFrom = side === 'left' ? { x: '-100%' } : { x: '100%' }
  const slideTo = { x: 0 }

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.25 }}
            className="fixed inset-0 bg-black/40 z-40"
            onClick={onClose}
          />
          <motion.div
            initial={slideFrom}
            animate={slideTo}
            exit={slideFrom}
            transition={{ type: 'spring', stiffness: 300, damping: 30 }}
            className={`fixed top-0 ${side === 'left' ? 'left-0' : 'right-0'} h-full w-72 bg-white dark:bg-stone-800 shadow-xl z-50 flex flex-col`}
          >
            {title && (
              <div className="flex items-center justify-between px-4 py-3 border-b border-stone-200 dark:border-stone-700">
                <h3 className="text-sm font-semibold">{title}</h3>
                <button
                  onClick={onClose}
                  className="p-1 rounded-md hover:bg-stone-100 dark:hover:bg-stone-700"
                  aria-label="Close drawer"
                >
                  <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            )}
            <div className="flex-1 overflow-y-auto p-4">{children}</div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
