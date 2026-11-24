import { Link } from 'react-router-dom';
import { company, site } from '../config';

export default function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="footer">
      <div className="container">
        <div className="footer-grid">
          <div className="footer-about">
            <Link to="/" className="brand">
              <img src="/logo.svg" alt="" width={36} height={36} />
              MobiWA
            </Link>
            <p>
              Collect your WhatsApp leads, let AI sort real customers, and reach them with the right offer —
              automatically.
            </p>
          </div>

          <div>
            <h4>Product</h4>
            <ul>
              <li>
                <Link to="/#how">How it works</Link>
              </li>
              <li>
                <Link to="/#features">Features</Link>
              </li>
              <li>
                <a href={site.playStoreUrl} target="_blank" rel="noopener noreferrer">
                  Android app
                </a>
              </li>
              <li>
                <a href={site.appUrl}>Web app</a>
              </li>
              <li>
                <Link to="/extension">Browser extension</Link>
              </li>
            </ul>
          </div>

          <div>
            <h4>Legal</h4>
            <ul>
              <li>
                <Link to="/privacy">Privacy Policy</Link>
              </li>
              <li>
                <Link to="/terms">Terms of Service</Link>
              </li>
              <li>
                <Link to="/delete-account">Delete your account</Link>
              </li>
            </ul>
          </div>

          <div>
            <h4>Company</h4>
            <ul>
              <li>
                <Link to="/#contact">Contact us</Link>
              </li>
              <li>
                <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>
              </li>
              <li>
                <Link to="/#faq">FAQ</Link>
              </li>
            </ul>
          </div>
        </div>

        <div className="footer-bottom">
          <span>
            © {year} {company.legalName}. All rights reserved.
          </span>
          <span>
            WhatsApp is a trademark of WhatsApp LLC. MobiWA is not affiliated with, endorsed or sponsored by
            WhatsApp or Meta.
          </span>
        </div>
      </div>
    </footer>
  );
}
