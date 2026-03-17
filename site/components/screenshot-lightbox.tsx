"use client";

import { useState, useEffect, useCallback } from "react";
import { X } from "lucide-react";

export function ScreenshotLightbox({
  src,
  alt,
  title,
  caption,
  className,
}: {
  src: string;
  alt: string;
  title?: string;
  caption?: string;
  className?: string;
}) {
  const [open, setOpen] = useState(false);

  const close = useCallback(() => setOpen(false), []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, close]);

  return (
    <>
      {/* Inline thumbnail — clickable */}
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={`group cursor-zoom-in ${className ?? ""}`}
      >
        <img
          src={src}
          alt={alt}
          className="w-full rounded-xl transition-transform duration-200 group-hover:scale-[1.01]"
        />
      </button>

      {/* Lightbox overlay */}
      {open && (
        <div
          className="fixed inset-0 z-[100] flex flex-col items-center justify-center p-4 md:p-10"
          onClick={close}
        >
          {/* Backdrop */}
          <div className="absolute inset-0 bg-black/90 backdrop-blur-md" />

          {/* Close button */}
          <button
            type="button"
            onClick={close}
            className="absolute right-5 top-5 z-20 rounded-full bg-white/10 p-2 text-white/60 transition-colors hover:bg-white/20 hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>

          {/* Framed screenshot */}
          <div
            className="relative z-10 w-full"
            style={{ maxWidth: "min(90vw, calc(70vh * 1.6))" }}
            onClick={(e) => e.stopPropagation()}
          >
            <div className="overflow-hidden rounded-xl border border-white/20 shadow-2xl">
              <img
                src={src}
                alt={alt}
                className="h-auto w-full select-none"
              />
              {(title || caption) && (
                <div className="border-t border-white/20 bg-black px-10 py-3">
                  {title && (
                    <span className="font-mono text-[10px] font-bold uppercase tracking-widest text-white/40">
                      {title}
                    </span>
                  )}
                  {caption && (
                    <p className="mt-1 text-xs leading-relaxed text-white/80">
                      {caption}
                    </p>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* Hint */}
          <div className="relative z-10 mt-4 font-mono text-[10px] uppercase tracking-widest text-white/30">
            esc to close
          </div>
        </div>
      )}
    </>
  );
}
