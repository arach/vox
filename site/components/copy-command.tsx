"use client";

import { useState } from "react";
import { Check, Copy } from "lucide-react";

export function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(command);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={copy}
      className="group inline-flex h-11 items-center gap-3 rounded-full border border-line-strong bg-panel px-5 font-mono text-[12px] text-ink transition-all hover:border-accent/35 hover:bg-white"
    >
      <span className="text-muted">$</span>
      <span>{command}</span>
      <span className="text-muted transition-colors group-hover:text-accent">
        {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
      </span>
    </button>
  );
}

export function CopyCommandBlock({ command, label }: { command: string; label: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(command);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="grid gap-3 rounded-[1.5rem] border border-line bg-canvas px-4 py-4 sm:grid-cols-[minmax(0,390px)_1fr] sm:items-center">
      <button
        onClick={copy}
        className="group flex items-center justify-between rounded-full border border-line-strong bg-panel px-4 py-3 font-mono text-[12px] text-ink transition-all hover:border-accent/35 hover:bg-white"
      >
        <span className="min-w-0 truncate text-left">
          <span className="text-muted">$ </span>
          {command}
        </span>
        <span className="ml-3 shrink-0 text-muted transition-colors group-hover:text-accent">
          {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
        </span>
      </button>
      <p className="text-sm leading-7 text-secondary">{label}</p>
    </div>
  );
}
