import { Link } from 'react-router-dom';
import ContactForm from '../components/ContactForm';
import { site } from '../config';

/** Account-deletion page required by Google Play (linked from the store listing). */
export default function DeleteAccount() {
  return (
    <article className="legal">
      <div className="container">
        <h1>Delete your MobiWA account</h1>
        <p className="updated">How to delete your account and the data linked to it.</p>

        <h2>Option 1 — in the app (fastest)</h2>
        <ol className="steps-list">
          <li>Open the MobiWA app (Android) or the web app at {site.appUrl.replace('https://', '')} and sign in.</li>
          <li>Go to <b>Settings</b>.</li>
          <li>Scroll to <b>About</b> and tap <b>Delete my account</b>.</li>
          <li>Type <b>DELETE</b> to confirm. Your account is deleted immediately.</li>
        </ol>

        <h2>Option 2 — without the app</h2>
        <p>
          Send us a request with the form below (choose “Delete my account”) or email{' '}
          <a href={`mailto:${site.privacyEmail}?subject=Delete my MobiWA account`}>{site.privacyEmail}</a> including
          your <b>username</b>. We may ask you to confirm the request, and
          we complete it within 30 days.
        </p>

        <h2>What is deleted</h2>
        <ul>
          <li>Your account (username, name, password, role, business information).</li>
          <li>All phone numbers, names, categories and AI sorting results in your account.</li>
          <li>Your usage statistics and device / session information.</li>
        </ul>

        <h2>What may be kept</h2>
        <ul>
          <li>Messages you sent us through the contact form, for up to 24 months.</li>
          <li>Encrypted backups, which are overwritten automatically within 30 days.</li>
          <li>Information we must keep by law (for example invoices), for the period the law requires.</li>
        </ul>
        <p>
          Deleting your MobiWA account does not delete anything in WhatsApp. To only remove numbers but keep your
          account, use <b>Settings → Delete all my numbers</b> in the app. See our{' '}
          <Link to="/privacy">Privacy Policy</Link> for details.
        </p>

        <h2>Request deletion</h2>
        <ContactForm defaultTopic="account_deletion" />
      </div>
    </article>
  );
}
