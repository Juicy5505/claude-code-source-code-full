"use client";

import { useEffect, useState, useCallback } from "react";
import { FolderOpen, File as FileIcon, RefreshCw, AlertCircle } from "lucide-react";
import { useFileViewerStore } from "@/lib/fileViewerStore";
import { cn } from "@/lib/utils";
import type { FileNode } from "@/lib/types";

/**
 * Lists workspace files exposed by the backend file API (`/api/files/tree`)
 * and opens them in the file viewer. When no backend is available the panel
 * shows a graceful empty/error state instead of failing.
 */
export function FileExplorer() {
  const loadAndOpen = useFileViewerStore((s) => s.loadAndOpen);
  const [nodes, setNodes] = useState<FileNode[] | null>(null);
  const [status, setStatus] = useState<"idle" | "loading" | "error">("idle");

  const refresh = useCallback(async () => {
    setStatus("loading");
    try {
      const res = await fetch("/api/files/tree", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as { tree?: FileNode[] };
      setNodes(data.tree ?? []);
      setStatus("idle");
    } catch {
      setNodes(null);
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return (
    <div className="flex flex-col h-full min-h-0">
      <div className="flex items-center justify-between px-3 py-2 flex-shrink-0">
        <span className="text-[10px] font-semibold uppercase tracking-wide text-surface-500">
          Workspace
        </span>
        <button
          onClick={() => void refresh()}
          title="Refresh"
          aria-label="Refresh file list"
          className="p-1 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-800/60 transition-colors"
        >
          <RefreshCw className={cn("w-3.5 h-3.5", status === "loading" && "animate-spin")} aria-hidden="true" />
        </button>
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto px-2 pb-2">
        {status === "loading" && (
          <p className="mt-6 text-center text-xs text-surface-500">Loading files…</p>
        )}

        {status === "error" && (
          <div className="mt-6 flex flex-col items-center gap-2 px-4 text-center text-xs text-surface-500">
            <AlertCircle className="w-5 h-5 text-surface-600" aria-hidden="true" />
            <span>No file backend connected.</span>
            <span className="text-surface-600">
              Start the API server to browse workspace files here.
            </span>
          </div>
        )}

        {status === "idle" && nodes && nodes.length === 0 && (
          <div className="mt-6 flex flex-col items-center gap-2 px-4 text-center text-xs text-surface-500">
            <FolderOpen className="w-5 h-5 text-surface-600" aria-hidden="true" />
            <span>No files in the workspace.</span>
          </div>
        )}

        {status === "idle" && nodes && nodes.length > 0 && (
          <ul className="space-y-0.5">
            {nodes.map((node) => (
              <FileRow key={node.path} node={node} depth={0} onOpen={loadAndOpen} />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function FileRow({
  node,
  depth,
  onOpen,
}: {
  node: FileNode;
  depth: number;
  onOpen: (path: string) => void | Promise<void>;
}) {
  const [expanded, setExpanded] = useState(false);
  const isDir = node.type === "directory";

  return (
    <li>
      <button
        onClick={() => (isDir ? setExpanded((v) => !v) : void onOpen(node.path))}
        className={cn(
          "flex w-full items-center gap-2 rounded px-2 py-1 text-xs text-left transition-colors",
          "text-surface-300 hover:bg-surface-800/60 hover:text-surface-100"
        )}
        style={{ paddingLeft: `${8 + depth * 12}px` }}
      >
        {isDir ? (
          <FolderOpen className="w-3.5 h-3.5 flex-shrink-0 text-brand-400/80" aria-hidden="true" />
        ) : (
          <FileIcon className="w-3.5 h-3.5 flex-shrink-0 text-surface-500" aria-hidden="true" />
        )}
        <span className="truncate">{node.name}</span>
      </button>
      {isDir && expanded && node.children && node.children.length > 0 && (
        <ul className="space-y-0.5">
          {node.children.map((child) => (
            <FileRow key={child.path} node={child} depth={depth + 1} onOpen={onOpen} />
          ))}
        </ul>
      )}
    </li>
  );
}
