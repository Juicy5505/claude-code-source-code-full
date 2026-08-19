"use client";

import { useState } from "react";
import { Check, CornerDownRight, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { useCollaborationContext } from "./CollaborationProvider";

interface AnnotationThreadProps {
  messageId: string;
  onClose: () => void;
}

function initials(name: string): string {
  return name
    .split(" ")
    .map((p) => p[0])
    .filter(Boolean)
    .slice(0, 2)
    .join("")
    .toUpperCase();
}

export function AnnotationThread({ messageId, onClose }: AnnotationThreadProps) {
  const { annotations, addAnnotation, resolveAnnotation, replyAnnotation } =
    useCollaborationContext();
  const thread = annotations[messageId] ?? [];

  const [draft, setDraft] = useState("");
  const [replyFor, setReplyFor] = useState<string | null>(null);
  const [replyText, setReplyText] = useState("");

  const submitComment = () => {
    const text = draft.trim();
    if (!text) return;
    addAnnotation(messageId, text);
    setDraft("");
  };

  const submitReply = (annotationId: string) => {
    const text = replyText.trim();
    if (!text) return;
    replyAnnotation(annotationId, text);
    setReplyText("");
    setReplyFor(null);
  };

  return (
    <div className="rounded-lg border border-surface-700 bg-surface-900 shadow-xl overflow-hidden">
      <div className="flex items-center justify-between border-b border-surface-800 px-3 py-2">
        <span className="text-xs font-semibold text-surface-200">
          Comments{thread.length > 0 ? ` (${thread.length})` : ""}
        </span>
        <button
          onClick={onClose}
          aria-label="Close comments"
          className="p-1 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800 transition-colors"
        >
          <X className="w-3.5 h-3.5" aria-hidden="true" />
        </button>
      </div>

      <div className="max-h-72 overflow-y-auto px-3 py-2 space-y-3">
        {thread.length === 0 && (
          <p className="py-4 text-center text-xs text-surface-500">No comments yet.</p>
        )}

        {thread.map((annotation) => (
          <div
            key={annotation.id}
            className={cn(
              "rounded-md border p-2",
              annotation.resolved
                ? "border-surface-800 bg-surface-800/40 opacity-70"
                : "border-surface-700 bg-surface-800/60"
            )}
          >
            <div className="flex items-start gap-2">
              <span
                className="flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full text-[9px] font-bold text-white"
                style={{ backgroundColor: annotation.author.color }}
              >
                {initials(annotation.author.name)}
              </span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5">
                  <span className="text-[11px] font-medium text-surface-200 truncate">
                    {annotation.author.name}
                  </span>
                  {annotation.resolved && (
                    <span className="text-[9px] text-emerald-400">resolved</span>
                  )}
                </div>
                <p className="mt-0.5 text-xs text-surface-300 break-words">{annotation.text}</p>

                {annotation.replies.length > 0 && (
                  <div className="mt-2 space-y-1.5 border-l border-surface-700 pl-2">
                    {annotation.replies.map((reply) => (
                      <div key={reply.id} className="flex items-start gap-1.5">
                        <span className="text-[10px] font-medium text-surface-400 flex-shrink-0">
                          {reply.author.name}:
                        </span>
                        <span className="text-[11px] text-surface-300 break-words">{reply.text}</span>
                      </div>
                    ))}
                  </div>
                )}

                <div className="mt-1.5 flex items-center gap-3">
                  <button
                    onClick={() => setReplyFor((v) => (v === annotation.id ? null : annotation.id))}
                    className="flex items-center gap-1 text-[10px] text-surface-500 hover:text-surface-300 transition-colors"
                  >
                    <CornerDownRight className="w-3 h-3" aria-hidden="true" />
                    Reply
                  </button>
                  <button
                    onClick={() => resolveAnnotation(annotation.id, !annotation.resolved)}
                    className="flex items-center gap-1 text-[10px] text-surface-500 hover:text-emerald-400 transition-colors"
                  >
                    <Check className="w-3 h-3" aria-hidden="true" />
                    {annotation.resolved ? "Reopen" : "Resolve"}
                  </button>
                </div>

                {replyFor === annotation.id && (
                  <div className="mt-2 flex items-center gap-1.5">
                    <input
                      autoFocus
                      value={replyText}
                      onChange={(e) => setReplyText(e.target.value)}
                      onKeyDown={(e) => e.key === "Enter" && submitReply(annotation.id)}
                      placeholder="Reply…"
                      className="flex-1 rounded border border-surface-700 bg-surface-900 px-2 py-1 text-[11px] text-surface-200 outline-none focus:border-brand-500"
                    />
                    <button
                      onClick={() => submitReply(annotation.id)}
                      className="rounded bg-brand-600 px-2 py-1 text-[10px] font-medium text-white hover:bg-brand-500 transition-colors"
                    >
                      Send
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="flex items-center gap-1.5 border-t border-surface-800 px-3 py-2">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submitComment()}
          placeholder="Add a comment…"
          className="flex-1 rounded border border-surface-700 bg-surface-900 px-2 py-1 text-xs text-surface-200 outline-none focus:border-brand-500"
        />
        <button
          onClick={submitComment}
          className="rounded bg-brand-600 px-2.5 py-1 text-xs font-medium text-white hover:bg-brand-500 transition-colors"
        >
          Comment
        </button>
      </div>
    </div>
  );
}
