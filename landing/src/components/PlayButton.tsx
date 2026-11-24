import { site } from '../config';
import { PlayMark } from './Icons';

export default function PlayButton() {
  return (
    <a
      className="play-btn"
      href={site.playStoreUrl}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Get MobiWA on Google Play"
    >
      <PlayMark />
      <span>
        <small>GET IT ON</small>
        <strong>Google Play</strong>
      </span>
    </a>
  );
}
