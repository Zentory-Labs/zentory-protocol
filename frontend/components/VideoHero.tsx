"use client";

import { useRef, useEffect } from "react";

interface VideoHeroProps {
  children: React.ReactNode;
  className?: string;
}

export function VideoHero({ children, className = "" }: VideoHeroProps) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.play().catch(() => {
      // Autoplay blocked — show paused frame
    });
  }, []);

  return (
    <div className={`relative min-h-screen min-h-[100dvh] overflow-hidden ${className}`}>
      {/* Video background — full bleed */}
      <video
        ref={videoRef}
        src="/hero_bg.mp4"
        autoPlay
        muted
        loop
        playsInline
        className="absolute inset-0 w-full h-full object-cover object-center"
        style={{ zIndex: 0 }}
      />

      {/* Dark vignette — strongest at edges */}
      <div
        className="absolute inset-0"
        style={{
          zIndex: 1,
          background:
            "radial-gradient(ellipse 80% 80% at 50% 50%, transparent 0%, #030508cc 60%, #030508 100%)",
        }}
      />

      {/* Neon city glow — bottom half, subtle pink/purple bleed */}
      <div
        className="absolute left-0 right-0 bottom-0 h-[60%] pointer-events-none"
        style={{
          zIndex: 2,
          background:
            "linear-gradient(to top, rgba(255, 45, 106, 0.06) 0%, rgba(157, 0, 255, 0.04) 40%, transparent 100%)",
        }}
      />

      {/* Scanline overlay for depth */}
      <div
        className="absolute inset-0 pointer-events-none opacity-[0.03]"
        style={{
          zIndex: 3,
          backgroundImage: "repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,229,255,0.5) 2px, rgba(0,229,255,0.5) 4px)",
        }}
      />

      {/* Content layer */}
      <div
        className="relative flex flex-col items-center justify-center min-h-screen min-h-[100dvh] px-6"
        style={{ zIndex: 10 }}
      >
        {children}
      </div>
    </div>
  );
}
