import { site } from '../config';

/** How to set up the web app (app.mobiwa.com) with the MobiWA Connector extension. */
export default function Extension() {
  return (
    <article className="legal">
      <div className="container">
        <h1>Use MobiWA on your computer</h1>
        <p className="updated">The web app works with WhatsApp Web through the free MobiWA Connector extension.</p>

        <div className="callout">
          Browsers don’t let one website control another, so the web app needs a small Chrome extension to work inside
          WhatsApp Web — the same way the Android app uses the Accessibility service. The extension only runs on
          web.whatsapp.com and {site.appUrl.replace('https://', '')}, and only acts when you start an action.
        </div>

        <h2>Set up (2 minutes)</h2>
        <ol className="steps-list">
          <li>
            Use <b>Google Chrome</b> (or Edge / Brave) on your computer.
          </li>
          <li>
            Install the extension:{' '}
            {site.chromeExtensionUrl ? (
              <a href={site.chromeExtensionUrl} target="_blank" rel="noopener noreferrer">
                MobiWA Connector on the Chrome Web Store
              </a>
            ) : (
              <>
                <b>MobiWA Connector</b> — Chrome Web Store link coming soon. Until then, ask{' '}
                <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a> for the install package.
              </>
            )}
          </li>
          <li>
            Open <a href="https://web.whatsapp.com" target="_blank" rel="noopener noreferrer">web.whatsapp.com</a> in a tab
            and link it to your phone (WhatsApp → Linked devices). Keep this tab open.
          </li>
          <li>
            Open <a href={site.appUrl}>{site.appUrl.replace('https://', '')}</a> and sign in. The status card turns green
            when the extension and WhatsApp Web are connected.
          </li>
        </ol>

        <h2>Good to know</h2>
        <ul>
          <li>Your account can be signed in on one device at a time — sign out on your phone before using the web app.</li>
          <li>While an action runs, MobiWA uses the WhatsApp Web tab. Don’t type in it until it finishes; a STOP button is shown there.</li>
          <li>Works with any WhatsApp or WhatsApp Business account linked to WhatsApp Web.</li>
        </ul>
      </div>
    </article>
  );
}
