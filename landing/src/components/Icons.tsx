/** Small inline SVG icon set (stroke icons, 24×24). */
type P = { size?: number; color?: string };

const base = (size = 24, color = 'currentColor') => ({
  width: size,
  height: size,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: color,
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
});

export const SearchUser = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <circle cx="10" cy="8" r="4" />
    <path d="M2 20c0-3.3 3.6-6 8-6 1.2 0 2.3.2 3.3.5" />
    <circle cx="18" cy="17" r="3" />
    <path d="m20.2 19.2 1.8 1.8" />
  </svg>
);
export const Sparkles = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M12 3l1.9 4.6L18.5 9.5l-4.6 1.9L12 16l-1.9-4.6L5.5 9.5l4.6-1.9z" />
    <path d="M19 15l.8 2 2 .8-2 .8L19 21l-.8-2.4-2-.8 2-.8z" />
  </svg>
);
export const Send = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M22 2 11 13" />
    <path d="M22 2 15 22l-4-9-9-4z" />
  </svg>
);
export const Check = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <circle cx="12" cy="12" r="10" />
    <path d="m8 12 3 3 5-6" />
  </svg>
);
export const Folder = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
  </svg>
);
export const Image = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <rect x="3" y="3" width="18" height="18" rx="3" />
    <circle cx="9" cy="9" r="2" />
    <path d="m21 15-5-5L5 21" />
  </svg>
);
export const Shield = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5z" />
    <path d="m9 12 2 2 4-4" />
  </svg>
);
export const Users = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <circle cx="9" cy="8" r="4" />
    <path d="M2 21c0-3.9 3.1-7 7-7s7 3.1 7 7" />
    <path d="M16 4a4 4 0 0 1 0 8M22 21c0-3-1.8-5.6-4.5-6.6" />
  </svg>
);
export const Chart = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M3 3v18h18" />
    <rect x="7" y="12" width="3" height="6" />
    <rect x="12" y="8" width="3" height="10" />
    <rect x="17" y="5" width="3" height="13" />
  </svg>
);
export const Contacts = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <rect x="4" y="3" width="16" height="18" rx="2" />
    <circle cx="12" cy="10" r="3" />
    <path d="M7.5 17c.8-1.8 2.5-3 4.5-3s3.7 1.2 4.5 3" />
  </svg>
);
export const Clock = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <circle cx="12" cy="12" r="10" />
    <path d="M12 6v6l4 2" />
  </svg>
);
export const Mail = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <rect x="2" y="4" width="20" height="16" rx="2" />
    <path d="m22 6-10 7L2 6" />
  </svg>
);
export const Globe = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <circle cx="12" cy="12" r="10" />
    <path d="M2 12h20M12 2a15 15 0 0 1 0 20M12 2a15 15 0 0 0 0 20" />
  </svg>
);
export const Phone = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <rect x="6" y="2" width="12" height="20" rx="3" />
    <path d="M11 18h2" />
  </svg>
);
export const Menu = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M4 6h16M4 12h16M4 18h16" />
  </svg>
);
export const Close = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M6 6l12 12M18 6 6 18" />
  </svg>
);
export const Lock = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <rect x="4" y="11" width="16" height="10" rx="2" />
    <path d="M8 11V7a4 4 0 0 1 8 0v4" />
  </svg>
);
export const Store = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M3 9 4.5 4h15L21 9" />
    <path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0" />
    <path d="M5 12v8h14v-8" />
  </svg>
);
export const Heart = ({ size, color }: P) => (
  <svg {...base(size, color)}>
    <path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8z" />
  </svg>
);

/** Google Play triangle mark (filled, brand colours). */
export const PlayMark = ({ size = 26 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
    <path d="M3.6 2.3 13.4 12l-9.8 9.7c-.4-.2-.6-.6-.6-1.1V3.4c0-.5.2-.9.6-1.1z" fill="#00d7fe" />
    <path d="m16.7 8.7-3.3 3.3-9.8-9.7c.2-.1.5-.1.8 0l12.3 6.4z" fill="#00f076" />
    <path d="m16.7 15.3-12.3 6.4c-.3.1-.6.1-.8 0l9.8-9.7z" fill="#ff3a44" />
    <path d="m20.6 13.3-3.9 2-3.3-3.3 3.3-3.3 3.9 2c.8.4.8 2.2 0 2.6z" fill="#ffd500" />
  </svg>
);
