"use client";

import { Plus, Search, Settings } from "lucide-react";
import { useChatStore } from "@/lib/store";
import { cn } from "@/lib/utils";

/**
 * Sticky footer actions for the sidebar: new conversation, search, settings.
 */
export function QuickActions() {
  const { createConversation, openSearch, openSettings } = useChatStore();

  const actions: Array<{ label: string; icon: React.ElementType; onClick: () => void }> = [
    { label: "New chat", icon: Plus, onClick: () => createConversation() },
    { label: "Search", icon: Search, onClick: () => openSearch() },
    { label: "Settings", icon: Settings, onClick: () => openSettings() },
  ];

  return (
    <div className="flex-shrink-0 border-t border-surface-800 p-2">
      <div className="flex items-center justify-around gap-1">
        {actions.map(({ label, icon: Icon, onClick }) => (
          <button
            key={label}
            onClick={onClick}
            title={label}
            aria-label={label}
            className={cn(
              "flex flex-1 flex-col items-center gap-1 rounded-md px-2 py-2 transition-colors",
              "text-surface-500 hover:text-surface-200 hover:bg-surface-800/60"
            )}
          >
            <Icon className="w-4 h-4" aria-hidden="true" />
            <span className="text-[10px] font-medium">{label}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
