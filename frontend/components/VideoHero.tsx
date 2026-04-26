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
    <>
      {/* Fixed video backdrop — true fullscreen */}
      <div
        className="fixed inset-0 z-0"
        style={{ pointerEvents: "none" }}
      >
        <video
          ref={videoRef}
          src="/hero_bg.mp4"
          autoPlay
          muted
          loop
          playsInline
          className="w-full h-full object-cover object-center"
          style={{ display: "block" }}
        />
        {/* Dark overlay so content is always readable */}
        <div
          className="absolute inset-0"
          style={{
            background:
              "linear-gradient(to bottom, rgba(11,11,13,0.55) 0%, rgba(11,11,13,0.4) 50%, rgba(11,11,13,0.7) 100%)",
          }}
        />
      </div>

      {/* Scrollable content on top */}
      <div className={`relative z-10 ${className}`}>
        {children}
      </div>
    </>
  );
}
