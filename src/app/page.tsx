"use client";

import React, { useState, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Plus,
  ChevronLeft,
  ChevronRight,
  X,
  Users,
  Sparkles,
  Pause,
  Play,
  Eye,
  Send,
} from "lucide-react";
import { cn } from "@/lib/utils";

// ── Types ──────────────────────────────────────────────────

interface User {
  id: string;
  name: string;
  username: string;
  avatar: string | null;
}

interface Family {
  id: string;
  name: string;
  familyCode: string | null;
  memberCount: number;
  generationCount: number;
}

interface Story {
  id: string;
  userId: string;
  familyId: string | null;
  caption: string | null;
  bgGradient: string;
  viewed: boolean;
  createdAt: string;
  user: User;
  views: { viewerId: string; viewedAt: string }[];
}

interface StoryGroup {
  user: User;
  stories: Story[];
  hasUnviewed: boolean;
}

// ── Color Constants (matching Flutter KinrelColors) ───────

const orange = "#E8612A";
const darkBg = "#131416";
const darkCard = "#191B2C";
const darkElevated = "#202338";
const textWhite = "#F5F0EE";
const textSilver = "#C9B4A8";
const textDim = "#8A7A72";

// ── Greeting helpers ──────────────────────────────────────

function getGreetingEmoji(): string {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return "☀️";
  if (hour >= 12 && hour < 17) return "🌤️";
  if (hour >= 17 && hour < 21) return "🌅";
  return "🌙";
}

function getGreetingPrefix(): string {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return "Good morning";
  if (hour >= 12 && hour < 17) return "Good afternoon";
  if (hour >= 17 && hour < 21) return "Good evening";
  return "Good night";
}

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

// ── Stories Viewer (Full-screen overlay) ──────────────────

function StoriesViewer({
  storyGroups,
  initialGroupIndex = 0,
  onClose,
  onMarkViewed,
}: {
  storyGroups: StoryGroup[];
  initialGroupIndex: number;
  onClose: () => void;
  onMarkViewed: (storyId: string) => void;
}) {
  const [groupIdx, setGroupIdx] = useState(initialGroupIndex);
  const [storyIdx, setStoryIdx] = useState(0);
  const [isPaused, setIsPaused] = useState(false);
  const [progress, setProgress] = useState(0);

  const currentGroup = storyGroups[groupIdx];
  const currentStory = currentGroup?.stories[storyIdx];

  // Auto-advance timer using ref to track progress and state only for rendering
  const progressRef = React.useRef(0);
  const rafRef = React.useRef<number>(0);
  const startTimeRef = React.useRef(0);

  useEffect(() => {
    if (isPaused || !currentStory) {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      return;
    }

    const duration = 5000; // 5 seconds per story
    startTimeRef.current = performance.now();
    progressRef.current = 0;

    function tick() {
      const elapsed = performance.now() - startTimeRef.current;
      const pct = Math.min((elapsed / duration) * 100, 100);
      progressRef.current = pct;
      setProgress(pct);

      if (pct >= 100) {
        progressRef.current = 0;
        // Move to next story
        if (storyIdx < currentGroup.stories.length - 1) {
          setStoryIdx((i) => i + 1);
        } else if (groupIdx < storyGroups.length - 1) {
          setGroupIdx((g) => g + 1);
          setStoryIdx(0);
        } else {
          onClose();
        }
        return;
      }
      rafRef.current = requestAnimationFrame(tick);
    }

    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [isPaused, groupIdx, storyIdx, currentGroup, storyGroups.length, onClose]);

  // Mark story as viewed
  useEffect(() => {
    if (currentStory && !currentStory.viewed) {
      onMarkViewed(currentStory.id);
    }
  }, [currentStory, onMarkViewed]);

  const goNext = useCallback(() => {
    if (storyIdx < currentGroup.stories.length - 1) {
      setStoryIdx((i) => i + 1);
      setProgress(0);
    } else if (groupIdx < storyGroups.length - 1) {
      setGroupIdx((g) => g + 1);
      setStoryIdx(0);
      setProgress(0);
    } else {
      onClose();
    }
  }, [storyIdx, groupIdx, currentGroup, storyGroups.length, onClose]);

  const goPrev = useCallback(() => {
    if (storyIdx > 0) {
      setStoryIdx((i) => i - 1);
      setProgress(0);
    } else if (groupIdx > 0) {
      setGroupIdx((g) => g - 1);
      setStoryIdx(0);
      setProgress(0);
    }
  }, [storyIdx, groupIdx]);

  if (!currentStory) return null;

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        exit={{ opacity: 0, scale: 0.95 }}
        transition={{ duration: 0.2 }}
        className="fixed inset-0 z-50 flex items-center justify-center bg-black"
        onClick={(e) => {
          if (e.target === e.currentTarget) onClose();
        }}
      >
        {/* Story card */}
        <div className="relative w-full max-w-md h-full max-h-[100dvh] flex flex-col">
          {/* Progress bars */}
          <div className="absolute top-0 left-0 right-0 z-20 flex gap-1 p-2 pt-3">
            {currentGroup.stories.map((_, i) => (
              <div
                key={i}
                className="flex-1 h-[3px] rounded-full bg-white/30 overflow-hidden"
              >
                <div
                  className="h-full bg-white rounded-full transition-all duration-50"
                  style={{
                    width:
                      i < storyIdx
                        ? "100%"
                        : i === storyIdx
                        ? `${progress}%`
                        : "0%",
                  }}
                />
              </div>
            ))}
          </div>

          {/* Header */}
          <div className="absolute top-6 left-0 right-0 z-20 flex items-center justify-between px-4 py-2">
            <div className="flex items-center gap-3">
              {/* User avatar */}
              <div
                className="w-9 h-9 rounded-full flex items-center justify-center text-white font-bold text-sm"
                style={{
                  background: `linear-gradient(135deg, ${orange}, #F59240)`,
                }}
              >
                {currentGroup.user.name[0]?.toUpperCase()}
              </div>
              <div>
                <p className="text-white text-sm font-semibold leading-tight">
                  {currentGroup.user.name}
                </p>
                <p className="text-white/60 text-xs">
                  @{currentGroup.user.username} · {timeAgo(currentStory.createdAt)}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setIsPaused(!isPaused)}
                className="p-2 rounded-full hover:bg-white/10 transition"
                aria-label={isPaused ? "Play" : "Pause"}
              >
                {isPaused ? (
                  <Play size={18} className="text-white" />
                ) : (
                  <Pause size={18} className="text-white" />
                )}
              </button>
              <button
                onClick={onClose}
                className="p-2 rounded-full hover:bg-white/10 transition"
                aria-label="Close"
              >
                <X size={20} className="text-white" />
              </button>
            </div>
          </div>

          {/* Story content */}
          <div
            className={cn(
              "flex-1 flex items-center justify-center p-8 rounded-none",
              `bg-gradient-to-br ${currentStory.bgGradient}`
            )}
            onClick={(e) => {
              const rect = e.currentTarget.getBoundingClientRect();
              const x = e.clientX - rect.left;
              if (x < rect.width / 3) {
                goPrev();
              } else {
                goNext();
              }
            }}
          >
            {currentStory.caption && (
              <p className="text-white text-xl md:text-2xl font-semibold text-center leading-relaxed drop-shadow-lg">
                {currentStory.caption}
              </p>
            )}
          </div>

          {/* Footer with reply */}
          <div className="absolute bottom-0 left-0 right-0 z-20 p-4 flex items-center gap-3 bg-gradient-to-t from-black/60 to-transparent">
            <div className="flex-1 flex items-center gap-2 bg-white/10 backdrop-blur-sm rounded-full px-4 py-2.5">
              <input
                type="text"
                placeholder={`Reply to ${currentGroup.user.name}...`}
                className="flex-1 bg-transparent text-white text-sm placeholder:text-white/50 outline-none"
                onClick={(e) => e.stopPropagation()}
              />
            </div>
            <button
              className="p-2.5 rounded-full bg-white/10 backdrop-blur-sm"
              onClick={(e) => e.stopPropagation()}
              aria-label="Send reply"
            >
              <Send size={18} className="text-white" />
            </button>
          </div>

          {/* Navigation arrows (desktop) */}
          {groupIdx > 0 && (
            <button
              onClick={goPrev}
              className="absolute left-2 top-1/2 -translate-y-1/2 z-20 p-2 rounded-full bg-black/30 backdrop-blur-sm hover:bg-black/50 transition hidden md:block"
              aria-label="Previous story"
            >
              <ChevronLeft size={24} className="text-white" />
            </button>
          )}
          {groupIdx < storyGroups.length - 1 && (
            <button
              onClick={goNext}
              className="absolute right-2 top-1/2 -translate-y-1/2 z-20 p-2 rounded-full bg-black/30 backdrop-blur-sm hover:bg-black/50 transition hidden md:block"
              aria-label="Next story"
            >
              <ChevronRight size={24} className="text-white" />
            </button>
          )}
        </div>
      </motion.div>
    </AnimatePresence>
  );
}

// ── Main Page Component ───────────────────────────────────

export default function HomePage() {
  const [stories, setStories] = useState<StoryGroup[]>([]);
  const [families, setFamilies] = useState<Family[]>([]);
  const [loading, setLoading] = useState(true);
  const [showStories, setShowStories] = useState(false);
  const [storyGroupIndex, setStoryGroupIndex] = useState(0);
  const [addStoryText, setAddStoryText] = useState("");
  const [showAddStory, setShowAddStory] = useState(false);

  // Current user (Manish)
  const currentUser: User = {
    id: "u1",
    name: "Manish",
    username: "manish",
    avatar: null,
  };

  // Fetch data
  useEffect(() => {
    async function fetchData() {
      try {
        const [storiesRes, familiesRes] = await Promise.all([
          fetch("/api/stories?grouped=true"),
          fetch("/api/families"),
        ]);
        const storiesData = await storiesRes.json();
        const familiesData = await familiesRes.json();

        if (storiesData.stories) setStories(storiesData.stories);
        if (familiesData.families) setFamilies(familiesData.families);
      } catch (error) {
        console.error("Failed to fetch data:", error);
      } finally {
        setLoading(false);
      }
    }
    fetchData();
  }, []);

  const handleBannerClick = (familyId: string) => {
    // Find the first story group for this family
    const familyStories = stories.filter(
      (sg) => sg.stories.some((s) => s.familyId === familyId)
    );
    if (familyStories.length > 0) {
      const globalIdx = stories.findIndex(
        (sg) => sg.stories.some((s) => s.familyId === familyId)
      );
      setStoryGroupIndex(globalIdx >= 0 ? globalIdx : 0);
      setShowStories(true);
    }
  };

  const handleAvatarClick = (groupIdx: number) => {
    setStoryGroupIndex(groupIdx);
    setShowStories(true);
  };

  const handleMarkViewed = async (storyId: string) => {
    try {
      await fetch(`/api/stories/${storyId}/view`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ viewerId: currentUser.id }),
      });
    } catch (e) {
      console.error("Failed to mark viewed:", e);
    }
  };

  const handleAddStory = async () => {
    if (!addStoryText.trim()) return;
    try {
      const res = await fetch("/api/stories", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          userId: currentUser.id,
          familyId: families[0]?.id,
          caption: addStoryText.trim(),
        }),
      });
      const data = await res.json();
      if (data.story) {
        // Refresh stories
        const storiesRes = await fetch("/api/stories?grouped=true");
        const storiesData = await storiesRes.json();
        if (storiesData.stories) setStories(storiesData.stories);
        setAddStoryText("");
        setShowAddStory(false);
      }
    } catch (e) {
      console.error("Failed to add story:", e);
    }
  };

  const primaryFamily = families[0];

  return (
    <div className="min-h-screen flex flex-col" style={{ background: darkBg }}>
      {/* ── Sticky Header ─────────────────────────────────── */}
      <header
        className="sticky top-0 z-30 px-4 h-[60px] flex items-center"
        style={{
          background: darkBg,
          borderBottom: "0.5px solid rgba(255,255,255,0.06)",
        }}
      >
        {/* K-graph mini icon */}
        <div
          className="w-5 h-5 rounded flex items-center justify-center font-bold text-[10px] text-white"
          style={{
            background: `linear-gradient(135deg, ${orange}, #F59240)`,
          }}
        >
          K
        </div>
        <div className="ml-3 flex-1">
          <p className="text-xs" style={{ color: textDim }}>
            {getGreetingPrefix()} {getGreetingEmoji()}
          </p>
          <div className="flex items-center gap-1.5">
            <span
              className="text-lg font-bold"
              style={{ color: textWhite }}
            >
              {currentUser.name}
            </span>
            <span
              className="text-xs font-medium"
              style={{ color: orange }}
            >
              @{currentUser.username}
            </span>
          </div>
        </div>
        {/* User avatar */}
        <div
          className="w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm"
          style={{ background: darkCard }}
        >
          <span style={{ color: orange }}>
            {currentUser.name[0]?.toUpperCase()}
          </span>
        </div>
      </header>

      <main className="flex-1 pb-8">
        {/* ── Stories Row (banner icon avatars) ──────────── */}
        <section className="px-4 py-4">
          <div className="flex gap-3.5 overflow-x-auto pb-2 scrollbar-none">
            {/* Add Story button */}
            <button
              onClick={() => setShowAddStory(true)}
              className="flex flex-col items-center gap-1 flex-shrink-0"
              aria-label="Add story"
            >
              <div
                className="w-[52px] h-[52px] rounded-full flex items-center justify-center"
                style={{
                  border: `2px dashed ${orange}80`,
                }}
              >
                <Plus size={20} style={{ color: orange }} />
              </div>
              <span
                className="text-[10px] font-medium"
                style={{ color: textSilver }}
              >
                Add
              </span>
            </button>

            {/* Story avatars */}
            {stories.map((group, idx) => (
              <button
                key={group.user.id}
                onClick={() => handleAvatarClick(idx)}
                className="flex flex-col items-center gap-1 flex-shrink-0"
                aria-label={`View ${group.user.name}'s stories`}
              >
                <div
                  className="w-[52px] h-[52px] rounded-full flex items-center justify-center font-bold text-lg text-white relative"
                  style={{
                    background: group.hasUnviewed
                      ? `linear-gradient(135deg, ${orange}, #F59240)`
                      : darkElevated,
                    boxShadow: group.hasUnviewed
                      ? `0 0 12px ${orange}40`
                      : "none",
                    border: group.hasUnviewed
                      ? `2px solid ${orange}`
                      : "none",
                    padding: group.hasUnviewed ? "2px" : "0",
                  }}
                >
                  <div
                    className="w-full h-full rounded-full flex items-center justify-center"
                    style={{ background: darkCard }}
                  >
                    <span style={{ color: orange }} className="text-lg font-bold">
                      {group.user.name[0]?.toUpperCase()}
                    </span>
                  </div>
                  {/* Unviewed indicator */}
                  {group.hasUnviewed && (
                    <div
                      className="absolute -top-0.5 -right-0.5 w-3 h-3 rounded-full"
                      style={{ background: orange }}
                    />
                  )}
                </div>
                <span
                  className="text-[9px] font-medium max-w-[52px] truncate"
                  style={{
                    color: group.hasUnviewed ? orange : textSilver,
                  }}
                >
                  @{group.user.username}
                </span>
              </button>
            ))}
          </div>
        </section>

        {/* ── Hero Family Banner Card ───────────────────── */}
        {loading ? (
          <div className="px-4 mt-2">
            <div
              className="w-full h-[180px] rounded-2xl animate-pulse"
              style={{ background: darkCard }}
            />
          </div>
        ) : primaryFamily ? (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4, delay: 0.1 }}
            className="px-4 mt-2"
          >
            <button
              onClick={() => handleBannerClick(primaryFamily.id)}
              className="w-full text-left rounded-2xl overflow-hidden relative group"
              style={{
                border: `1px solid ${orange}26`,
                boxShadow: `0 0 24px ${orange}1F`,
              }}
              aria-label={`${primaryFamily.name} family banner - click to view stories`}
            >
              {/* Background */}
              <div
                className="w-full min-h-[180px] p-5"
                style={{
                  background:
                    "radial-gradient(ellipse at top right, #191B2C 0%, #13141E 100%)",
                }}
              >
                {/* Dotted K-graph pattern */}
                <svg
                  className="absolute inset-0 w-full h-full opacity-[0.04] pointer-events-none"
                  viewBox="0 0 400 200"
                >
                  {/* Nodes */}
                  {[
                    [60, 50],
                    [140, 30],
                    [220, 60],
                    [300, 40],
                    [340, 80],
                    [100, 110],
                    [200, 130],
                    [280, 140],
                    [160, 170],
                    [320, 170],
                  ].map(([x, y], i) => (
                    <circle
                      key={i}
                      cx={x}
                      cy={y}
                      r="3"
                      fill={orange}
                    />
                  ))}
                  {/* Edges */}
                  {[
                    [60, 50, 140, 30],
                    [140, 30, 220, 60],
                    [220, 60, 300, 40],
                    [300, 40, 340, 80],
                    [60, 50, 100, 110],
                    [100, 110, 200, 130],
                    [200, 130, 280, 140],
                    [220, 60, 200, 130],
                    [100, 110, 160, 170],
                    [280, 140, 320, 170],
                  ].map(([x1, y1, x2, y2], i) => (
                    <line
                      key={i}
                      x1={x1}
                      y1={y1}
                      x2={x2}
                      y2={y2}
                      stroke={orange}
                      strokeWidth="1"
                    />
                  ))}
                </svg>

                {/* Content */}
                <div className="relative z-10 flex flex-col items-center py-2">
                  {/* Banner icon - Family initial avatar */}
                  <div
                    className="w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-xl mb-3 group-hover:scale-110 transition-transform"
                    style={{
                      background: `linear-gradient(135deg, ${orange}, #F59240)`,
                      boxShadow: `0 0 12px ${orange}66`,
                    }}
                  >
                    {primaryFamily.name[0]?.toUpperCase()}
                  </div>

                  {/* Family name */}
                  <h2
                    className="text-xl font-bold tracking-wide"
                    style={{ color: textWhite }}
                  >
                    {primaryFamily.name}
                  </h2>

                  {/* Family code */}
                  {primaryFamily.familyCode && (
                    <p
                      className="text-xs font-medium mt-0.5"
                      style={{ color: orange }}
                    >
                      @{primaryFamily.familyCode}
                    </p>
                  )}

                  {/* Stats */}
                  <div className="flex items-center gap-1 mt-2">
                    <span className="text-xs" style={{ color: textSilver }}>
                      {primaryFamily.memberCount} Members ·{" "}
                    </span>
                    <span className="text-xs" style={{ color: textSilver }}>
                      0 Links ·{" "}
                    </span>
                    <span className="text-xs" style={{ color: textSilver }}>
                      {primaryFamily.generationCount} Generations
                    </span>
                  </div>

                  {/* Stories hint */}
                  <div
                    className="mt-3 flex items-center gap-1.5 px-3 py-1 rounded-full"
                    style={{ background: `${orange}1A` }}
                  >
                    <Eye size={12} style={{ color: orange }} />
                    <span className="text-[10px] font-medium" style={{ color: orange }}>
                      Tap to view family stories
                    </span>
                  </div>
                </div>
              </div>
            </button>
          </motion.div>
        ) : null}

        {/* ── Family Feed Section ────────────────────────── */}
        <section className="px-4 mt-5">
          <div className="flex items-center gap-2 mb-3">
            <Sparkles size={18} style={{ color: orange }} />
            <h2
              className="text-lg font-bold"
              style={{ color: textWhite }}
            >
              Family Feed
            </h2>
          </div>

          {/* Feed items (stories as cards) */}
          {loading ? (
            <div className="space-y-3">
              {[1, 2].map((i) => (
                <div
                  key={i}
                  className="w-full h-[200px] rounded-2xl animate-pulse"
                  style={{ background: darkCard }}
                />
              ))}
            </div>
          ) : stories.length === 0 ? (
            <div
              className="flex flex-col items-center justify-center py-12 rounded-2xl"
              style={{ background: darkCard }}
            >
              <Users size={40} style={{ color: textDim }} />
              <p className="mt-3 font-medium" style={{ color: textWhite }}>
                No Stories Yet
              </p>
              <p className="text-sm mt-1" style={{ color: textDim }}>
                Be the first to share a story with your family
              </p>
              <button
                onClick={() => setShowAddStory(true)}
                className="mt-4 px-4 py-2 rounded-full text-sm font-medium text-white"
                style={{ background: orange }}
              >
                Add Story
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              {stories.map((group) =>
                group.stories.map((story) => (
                  <motion.div
                    key={story.id}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    className="rounded-2xl overflow-hidden"
                    style={{
                      background: darkCard,
                      border: `1px solid rgba(255,255,255,0.04)`,
                    }}
                  >
                    {/* Story card header */}
                    <div className="flex items-center gap-3 p-3">
                      <div
                        className="w-9 h-9 rounded-full flex items-center justify-center text-white font-bold text-sm flex-shrink-0"
                        style={{
                          background: `linear-gradient(135deg, ${orange}, #F59240)`,
                        }}
                      >
                        {story.user.name[0]?.toUpperCase()}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-1.5">
                          <span
                            className="text-sm font-semibold truncate"
                            style={{ color: textWhite }}
                          >
                            {story.user.name}
                          </span>
                          <span
                            className="text-xs flex-shrink-0"
                            style={{ color: orange }}
                          >
                            @{story.user.username}
                          </span>
                        </div>
                        <span className="text-xs" style={{ color: textDim }}>
                          {timeAgo(story.createdAt)}
                        </span>
                      </div>
                    </div>

                    {/* Story content */}
                    <div
                      className={cn(
                        "mx-3 mb-3 rounded-xl p-6 flex items-center justify-center min-h-[140px]",
                        `bg-gradient-to-br ${story.bgGradient}`
                      )}
                    >
                      <p className="text-white text-base font-medium text-center leading-relaxed drop-shadow-md">
                        {story.caption}
                      </p>
                    </div>

                    {/* Story footer */}
                    <div className="flex items-center justify-between px-3 pb-3">
                      <div className="flex items-center gap-1">
                        <Eye size={14} style={{ color: textDim }} />
                        <span className="text-xs" style={{ color: textDim }}>
                          {story.views.length} views
                        </span>
                      </div>
                    </div>
                  </motion.div>
                ))
              )}
            </div>
          )}
        </section>
      </main>

      {/* ── Footer ───────────────────────────────────────── */}
      <footer
        className="mt-auto py-3 px-4 flex items-center justify-around"
        style={{
          background: darkCard,
          borderTop: "0.5px solid rgba(255,255,255,0.06)",
        }}
      >
        {[
          { icon: "🏠", label: "Home", active: true },
          { icon: "🔍", label: "Search", active: false },
          { icon: "📊", label: "Graph", active: false },
          { icon: "🔔", label: "Alerts", active: false },
          { icon: "👤", label: "Me", active: false },
        ].map((tab) => (
          <button
            key={tab.label}
            className="flex flex-col items-center gap-0.5 px-3 py-1"
          >
            <span className="text-lg">{tab.icon}</span>
            <span
              className="text-[10px] font-medium"
              style={{ color: tab.active ? orange : textDim }}
            >
              {tab.label}
            </span>
          </button>
        ))}
      </footer>

      {/* ── Stories Viewer Overlay ──────────────────────── */}
      {showStories && stories.length > 0 && (
        <StoriesViewer
          storyGroups={stories}
          initialGroupIndex={storyGroupIndex}
          onClose={() => setShowStories(false)}
          onMarkViewed={handleMarkViewed}
        />
      )}

      {/* ── Add Story Modal ─────────────────────────────── */}
      <AnimatePresence>
        {showAddStory && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 backdrop-blur-sm"
            onClick={(e) => {
              if (e.target === e.currentTarget) setShowAddStory(false);
            }}
          >
            <motion.div
              initial={{ y: 100, opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              exit={{ y: 100, opacity: 0 }}
              transition={{ type: "spring", damping: 25, stiffness: 300 }}
              className="w-full max-w-md rounded-t-2xl sm:rounded-2xl p-5"
              style={{ background: darkCard }}
            >
              <div className="flex items-center justify-between mb-4">
                <h3
                  className="text-lg font-bold"
                  style={{ color: textWhite }}
                >
                  Add Story
                </h3>
                <button
                  onClick={() => setShowAddStory(false)}
                  className="p-1 rounded-full hover:bg-white/10"
                  aria-label="Close"
                >
                  <X size={20} style={{ color: textSilver }} />
                </button>
              </div>

              {/* Gradient preview */}
              <div
                className={cn(
                  "w-full h-[160px] rounded-xl flex items-center justify-center p-6 mb-4 bg-gradient-to-br",
                  addStoryText
                    ? "from-orange-500 to-amber-600"
                    : "from-gray-700 to-gray-800"
                )}
              >
                <p className="text-white text-lg font-medium text-center leading-relaxed">
                  {addStoryText || "Type your story below..."}
                </p>
              </div>

              {/* Input */}
              <div className="flex gap-2">
                <input
                  type="text"
                  value={addStoryText}
                  onChange={(e) => setAddStoryText(e.target.value)}
                  placeholder="What's happening in your family?"
                  className="flex-1 rounded-full px-4 py-3 text-sm outline-none"
                  style={{
                    background: darkElevated,
                    color: textWhite,
                    border: `1px solid rgba(255,255,255,0.06)`,
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleAddStory();
                  }}
                  autoFocus
                />
                <button
                  onClick={handleAddStory}
                  disabled={!addStoryText.trim()}
                  className="px-5 py-3 rounded-full text-sm font-medium text-white disabled:opacity-40"
                  style={{ background: orange }}
                >
                  Post
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
