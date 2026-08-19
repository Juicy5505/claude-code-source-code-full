"use client";

import { useMemo } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Plus, Pin, Trash2, MessageSquare } from "lucide-react";
import { useChatStore } from "@/lib/store";
import { cn } from "@/lib/utils";
import type { Conversation } from "@/lib/types";

function relativeTime(ts: number): string {
  const diff = Date.now() - ts;
  const min = Math.floor(diff / 60000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const day = Math.floor(hr / 24);
  if (day < 7) return `${day}d ago`;
  return new Date(ts).toLocaleDateString();
}

export function ChatHistory() {
  const {
    conversations,
    activeConversationId,
    pinnedIds,
    createConversation,
    setActiveConversation,
    deleteConversation,
    pinConversation,
  } = useChatStore();

  const { pinned, recent } = useMemo(() => {
    const pinnedSet = new Set(pinnedIds);
    const pinnedList: Conversation[] = [];
    const recentList: Conversation[] = [];
    for (const c of conversations) {
      (pinnedSet.has(c.id) ? pinnedList : recentList).push(c);
    }
    return { pinned: pinnedList, recent: recentList };
  }, [conversations, pinnedIds]);

  const renderItem = (conversation: Conversation) => {
    const isActive = conversation.id === activeConversationId;
    const isPinned = pinnedIds.includes(conversation.id);
    return (
      <motion.div
        key={conversation.id}
        layout
        initial={{ opacity: 0, y: 4 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0 }}
        className={cn(
          "group flex items-center gap-2 rounded-md px-2.5 py-2 cursor-pointer transition-colors",
          isActive
            ? "bg-surface-800 text-surface-100"
            : "text-surface-400 hover:bg-surface-800/60 hover:text-surface-200"
        )}
        onClick={() => setActiveConversation(conversation.id)}
      >
        <MessageSquare className="w-4 h-4 flex-shrink-0 opacity-70" aria-hidden="true" />
        <div className="flex-1 min-w-0">
          <p className="text-xs font-medium truncate">{conversation.title || "Untitled"}</p>
          <p className="text-[10px] text-surface-500">{relativeTime(conversation.updatedAt)}</p>
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            pinConversation(conversation.id);
          }}
          title={isPinned ? "Unpin" : "Pin"}
          aria-label={isPinned ? "Unpin conversation" : "Pin conversation"}
          className={cn(
            "p-1 rounded transition-opacity",
            isPinned
              ? "text-brand-400 opacity-100"
              : "text-surface-500 opacity-0 group-hover:opacity-100 hover:text-surface-200"
          )}
        >
          <Pin className="w-3.5 h-3.5" aria-hidden="true" />
        </button>
        <button
          onClick={(e) => {
            e.stopPropagation();
            deleteConversation(conversation.id);
          }}
          title="Delete"
          aria-label="Delete conversation"
          className="p-1 rounded text-surface-500 opacity-0 group-hover:opacity-100 hover:text-red-400 transition-opacity"
        >
          <Trash2 className="w-3.5 h-3.5" aria-hidden="true" />
        </button>
      </motion.div>
    );
  };

  return (
    <div className="flex flex-col h-full min-h-0">
      <div className="px-2 py-2 flex-shrink-0">
        <button
          onClick={() => createConversation()}
          className={cn(
            "flex w-full items-center justify-center gap-2 rounded-md px-3 py-2",
            "bg-brand-600 hover:bg-brand-500 text-white text-xs font-medium transition-colors"
          )}
        >
          <Plus className="w-4 h-4" aria-hidden="true" />
          New conversation
        </button>
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto px-2 pb-2 space-y-0.5">
        {conversations.length === 0 && (
          <div className="mt-8 text-center text-xs text-surface-500 px-4">
            No conversations yet. Start a new one to begin.
          </div>
        )}

        {pinned.length > 0 && (
          <>
            <p className="px-2 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-wide text-surface-500">
              Pinned
            </p>
            <AnimatePresence initial={false}>{pinned.map(renderItem)}</AnimatePresence>
          </>
        )}

        {recent.length > 0 && (
          <>
            {pinned.length > 0 && (
              <p className="px-2 pt-3 pb-1 text-[10px] font-semibold uppercase tracking-wide text-surface-500">
                Recent
              </p>
            )}
            <AnimatePresence initial={false}>{recent.map(renderItem)}</AnimatePresence>
          </>
        )}
      </div>
    </div>
  );
}
