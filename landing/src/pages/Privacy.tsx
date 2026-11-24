import { Link } from 'react-router-dom';
import { company, legal, site } from '../config';

export default function Privacy() {
  const c = company.legalName;
  return (
    <article className="legal">
      <div className="container">
        <h1>Privacy Policy</h1>
        <p className="updated">Last updated: {legal.privacyUpdated}</p>

        <p>
          This Privacy Policy explains how {c} (“<b>MobiWA</b>”, “<b>we</b>”, “<b>us</b>”) collects, uses, shares and
          protects information when you use the MobiWA Android app, the MobiWA web app at {site.appUrl}, the MobiWA
          Connector browser extension and the website {site.url} (together, the “<b>Service</b>”).
        </p>

        <div className="callout">
          <b>In short:</b> MobiWA helps businesses organise and message their WhatsApp customers. We only read
          WhatsApp content when you start an action, we never sell your data, chat text sent to our AI is not stored,
          and you can delete your account and data at any time.
        </div>

        <nav className="toc" aria-label="Contents">
          <ol>
            <li><a href="#who">Who we are</a></li>
            <li><a href="#collect">Information we collect</a></li>
            <li><a href="#accessibility">Accessibility service</a></li>
            <li><a href="#contacts">Contacts permission</a></li>
            <li><a href="#use">How we use information</a></li>
            <li><a href="#ai">AI processing</a></li>
            <li><a href="#share">Sharing</a></li>
            <li><a href="#retention">Retention</a></li>
            <li><a href="#security">Security</a></li>
            <li><a href="#rights">Your rights & deletion</a></li>
            <li><a href="#customers">Your customers’ data</a></li>
            <li><a href="#transfers">International transfers</a></li>
            <li><a href="#children">Children</a></li>
            <li><a href="#changes">Changes</a></li>
            <li><a href="#contact">Contact</a></li>
          </ol>
        </nav>

        <h2 id="who">1. Who we are</h2>
        <p>
          The Service is operated by {c}, {company.address}. For any privacy question, contact{' '}
          <a href={`mailto:${site.privacyEmail}`}>{site.privacyEmail}</a>.
        </p>

        <h2 id="collect">2. Information we collect</h2>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Category</th>
                <th>What</th>
                <th>Where it comes from</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Account</td>
                <td>Username, password (stored hashed), full name, role, business name and description, account status.</td>
                <td>Us, when we create your account; you, in Settings.</td>
              </tr>
              <tr>
                <td>Device & session</td>
                <td>
                  An app-specific device identifier (Android ID, or a random ID in the browser), device model, a session
                  token, sign-in time and last-seen time.
                </td>
                <td>Your device, when you sign in. Used to allow one device per account.</td>
              </tr>
              <tr>
                <td>WhatsApp numbers</td>
                <td>Phone numbers of chats that are not saved in your contacts.</td>
                <td>Your WhatsApp chat list, when you run “Get Numbers”.</td>
              </tr>
              <tr>
                <td>Chat text (temporary)</td>
                <td>The text of the chats you choose to sort (up to the last 80 messages per chat).</td>
                <td>WhatsApp, when you run “AI Sort”. Sent to our AI and not stored.</td>
              </tr>
              <tr>
                <td>Sorting results</td>
                <td>Category, a short reason (e.g. “asked about the price of a screen repair”) and, if the customer stated it, their first name.</td>
                <td>Produced by the AI Sort.</td>
              </tr>
              <tr>
                <td>Selected contacts</td>
                <td>Name and phone number of the saved contacts you choose for AI Sort.</td>
                <td>Your phone’s address book, with your permission.</td>
              </tr>
              <tr>
                <td>Messages you send</td>
                <td>
                  The text and the file (image, video, PDF) you send to your recipients. Files stay on your device and
                  are handed to WhatsApp; they are not uploaded to our servers.
                </td>
                <td>You.</td>
              </tr>
              <tr>
                <td>Usage statistics</td>
                <td>Counts per action (numbers found, customers sorted, messages sent/failed) and timestamps.</td>
                <td>The app, when an action finishes.</td>
              </tr>
              <tr>
                <td>Contact form</td>
                <td>Name, email, business, topic and message.</td>
                <td>You, on our website.</td>
              </tr>
              <tr>
                <td>Technical logs</td>
                <td>IP address, browser/app version and error logs kept by our hosting providers.</td>
                <td>Automatically, when you use the Service.</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p>We do not collect location, advertising IDs, payment card data, or the content of chats you did not choose to sort.</p>

        <h2 id="accessibility">3. Accessibility service (Android)</h2>
        <p>
          The MobiWA Android app uses Android’s <b>AccessibilityService API</b>. This is required for the app’s core
          features, because Android offers no other way for an app to work inside WhatsApp on your behalf. With your
          explicit consent, the service is used to:
        </p>
        <ul>
          <li>scroll your WhatsApp / WhatsApp Business chat list and read the phone numbers shown there (Get Numbers);</li>
          <li>open a chat and read the message text shown on screen (AI Sort);</li>
          <li>open a chat, attach the content you prepared and press Send (Send Messages);</li>
          <li>show a small status bar with a STOP button over WhatsApp while an action runs.</li>
        </ul>
        <p>
          The service only acts inside WhatsApp and WhatsApp Business, only while an action that <b>you</b> started is
          running, and never reads passwords, other apps, or your screen at other times. Data handled this way is used
          only for the features above and is never sold or used for advertising. You can turn the service off at any
          time in Android Settings → Accessibility.
        </p>
        <p>
          On a computer, the <b>MobiWA Connector</b> browser extension does the same on web.whatsapp.com for the web
          app. It can only access web.whatsapp.com and {site.appUrl}, acts only when you start an action in the web
          app, does not store your chats, and can be removed at any time from your browser’s extensions page.
        </p>

        <h2 id="contacts">4. Contacts permission (Android)</h2>
        <p>
          If you allow it, MobiWA reads the names and phone numbers in your phone’s address book so you can choose
          contacts for AI Sort or as recipients, and to show which ones use WhatsApp. The address book is read on your
          device. Only the contacts you select for AI Sort are saved to your account; contacts selected only as message
          recipients are not uploaded.
        </p>

        <h2 id="use">5. How we use information</h2>
        <ul>
          <li>To provide the Service: collect numbers, sort them, send your messages, show your categories and dashboards.</li>
          <li>To secure accounts: sign-in, one-device-per-account, abuse and spam prevention.</li>
          <li>To manage accounts and provide customer support.</li>
          <li>To answer support and contact requests.</li>
          <li>To fix bugs and improve reliability (using logs and aggregated statistics).</li>
          <li>To comply with legal obligations.</li>
        </ul>
        <p>
          Where the GDPR or similar laws apply, our legal bases are: performance of a contract (providing the Service),
          your consent (Accessibility and Contacts permissions, which you can withdraw at any time), our legitimate
          interests (security, improvement), and legal obligations.
        </p>

        <h2 id="ai">6. AI processing</h2>
        <p>
          AI Sort sends the text of the selected chat, your existing category names and your business description to
          Google’s Gemini API through our server. The AI returns whether the person is a customer, a category and a
          short reason. We do not store the chat text. Google processes the request as our service provider under its
          API terms. We do not use your data to train AI models.
        </p>

        <h2 id="share">7. Sharing</h2>
        <p>We never sell or rent personal information. We share it only with:</p>
        <ul>
          <li><b>Supabase</b> (database, authentication and server functions) — hosts account and customer data.</li>
          <li><b>Google</b> (Gemini API) — processes chat text for AI Sort, as described above.</li>
          <li><b>Our website / web-app hosting provider</b> — serves the website and web app.</li>
          <li><b>MobiWA staff</b> — only authorised staff can access account data, and only as needed to operate, secure and support the Service.</li>
          <li><b>Authorities</b> — when required by law or to protect rights and safety.</li>
          <li><b>A successor</b> — in a merger or acquisition, under the same protections.</li>
        </ul>
        <p>
          WhatsApp itself is operated by WhatsApp LLC / Meta. Messages you send through WhatsApp are subject to
          WhatsApp’s own terms and privacy policy.
        </p>

        <h2 id="retention">8. Retention</h2>
        <ul>
          <li>Account, categories, numbers and statistics: until you delete them or your account is deleted.</li>
          <li>Chat text sent to the AI: not stored by us.</li>
          <li>Contact form messages: up to 24 months, then deleted.</li>
          <li>Hosting logs: typically up to 30 days.</li>
          <li>Backups are overwritten on a rolling basis.</li>
        </ul>

        <h2 id="security">9. Security</h2>
        <p>
          Data is encrypted in transit (HTTPS) and at rest by our database provider. Access is restricted by row-level
          security so each user only reaches their own data, and only from the device signed in to the account.
          Account management runs on our server. No system is perfectly secure; please keep your password private.
        </p>

        <h2 id="rights">10. Your rights & deleting your data</h2>
        <p>Depending on where you live, you may have the right to access, correct, export or delete your data, to object to or restrict processing, and to withdraw consent.</p>
        <ul>
          <li><b>Delete numbers:</b> in the app, Settings → “Delete all my numbers”, or per number / category.</li>
          <li><b>Delete your account:</b> in the app, Settings → “Delete my account”. This permanently deletes the account and all its data.</li>
          <li>
            <b>Without the app:</b> follow the steps on our <Link to="/delete-account">account deletion page</Link> or email{' '}
            <a href={`mailto:${site.privacyEmail}`}>{site.privacyEmail}</a>. We respond within 30 days.
          </li>
        </ul>
        <p>You may also complain to your local data-protection authority.</p>

        <h2 id="customers">11. Your customers’ data</h2>
        <p>
          When you use MobiWA, the phone numbers and chats of <b>your</b> customers are processed on your behalf. For
          that data you are the controller and we act as your processor. You are responsible
          for having a lawful basis to contact them — in particular, only send marketing messages to people who agreed
          to receive them, and honour opt-out requests. See our <Link to="/terms">Terms of Service</Link>.
        </p>

        <h2 id="transfers">12. International transfers</h2>
        <p>
          Our providers may process data in countries other than yours (our database is hosted in Japan). Where
          required, transfers are protected by appropriate safeguards such as standard contractual clauses.
        </p>

        <h2 id="children">13. Children</h2>
        <p>
          MobiWA is a business tool and is not intended for anyone under 18. We do not knowingly collect data from
          children. If you believe a child provided us data, contact us and we will delete it.
        </p>

        <h2 id="changes">14. Changes to this policy</h2>
        <p>
          We may update this policy. We will change the “Last updated” date and, for significant changes, notify you in
          the app or by email before they take effect.
        </p>

        <h2 id="contact">15. Contact</h2>
        <p>
          {c}
          <br />
          {company.address}
          <br />
          <a href={`mailto:${site.privacyEmail}`}>{site.privacyEmail}</a>
        </p>
      </div>
    </article>
  );
}
