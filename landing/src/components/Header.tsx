import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { site } from '../config';
import { Close, Menu } from './Icons';

const links = [
  { to: '/#how', label: 'How it works' },
  { to: '/#features', label: 'Features' },
  { to: '/#stores', label: 'For stores' },
  { to: '/#faq', label: 'FAQ' },
  { to: '/#contact', label: 'Contact' },
];

export default function Header() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const { pathname, hash } = useLocation();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => setOpen(false), [pathname, hash]);

  return (
    <header className={`header${scrolled ? ' scrolled' : ''}`}>
      <div className="container header-inner">
        <Link to="/" className="brand" aria-label="MobiWA home">
          <img src="/logo.svg" alt="" width={36} height={36} />
          MobiWA
        </Link>

        <nav className="nav" aria-label="Main">
          {links.map((l) => (
            <Link key={l.to} to={l.to}>
              {l.label}
            </Link>
          ))}
        </nav>

        <div className="header-cta">
          <a className="btn btn-ghost" href={site.appUrl}>
            Sign in
          </a>
          <a className="btn btn-primary" href={site.playStoreUrl} target="_blank" rel="noopener noreferrer">
            Get the app
          </a>
        </div>

        <button
          className="menu-btn"
          aria-label={open ? 'Close menu' : 'Open menu'}
          aria-expanded={open}
          onClick={() => setOpen((o) => !o)}
        >
          {open ? <Close size={20} /> : <Menu size={20} />}
        </button>
      </div>

      <nav className={`mobile-nav${open ? ' open' : ''}`} aria-label="Mobile">
        {links.map((l) => (
          <Link key={l.to} to={l.to}>
            {l.label}
          </Link>
        ))}
        <a className="btn btn-ghost" href={site.appUrl}>
          Sign in to the web app
        </a>
        <a className="btn btn-primary" href={site.playStoreUrl} target="_blank" rel="noopener noreferrer">
          Get the Android app
        </a>
      </nav>
    </header>
  );
}
