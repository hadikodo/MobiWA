import { Link } from 'react-router-dom';
import { company, legal, site } from '../config';

export default function Terms() {
  const c = company.legalName;
  return (
    <article className="legal">
      <div className="container">
        <h1>Terms of Service</h1>
        <p className="updated">Last updated: {legal.termsUpdated}</p>

        <p>
          These Terms of Service (“<b>Terms</b>”) are an agreement between you and {c} (“<b>MobiWA</b>”, “<b>we</b>”)
          for the use of the MobiWA Android app, web app, browser extension and website (the “<b>Service</b>”). By
          creating, receiving or using an account you agree to these Terms and to our{' '}
          <Link to="/privacy">Privacy Policy</Link>. If you use the Service for a business, you accept these Terms on its
          behalf and confirm you are authorised to do so.
        </p>

        <div className="callout warn">
          <b>Important:</b> MobiWA is an independent product and is <b>not affiliated with, endorsed or sponsored by
          WhatsApp LLC or Meta Platforms, Inc.</b> You are responsible for using WhatsApp in line with WhatsApp’s terms
          and for only messaging people who agreed to hear from you. Misuse can get your WhatsApp number restricted or
          banned by WhatsApp.
        </div>

        <nav className="toc" aria-label="Contents">
          <ol>
            <li><a href="#service">The Service</a></li>
            <li><a href="#accounts">Accounts</a></li>
            <li><a href="#use">Acceptable use</a></li>
            <li><a href="#whatsapp">WhatsApp & third parties</a></li>
            <li><a href="#data">Your data & customers</a></li>
            <li><a href="#ai">AI results</a></li>
            <li><a href="#fees">Fees</a></li>
            <li><a href="#ip">Intellectual property</a></li>
            <li><a href="#termination">Suspension & termination</a></li>
            <li><a href="#disclaimer">Disclaimers</a></li>
            <li><a href="#liability">Limitation of liability</a></li>
            <li><a href="#indemnity">Indemnity</a></li>
            <li><a href="#changes">Changes</a></li>
            <li><a href="#law">Governing law</a></li>
            <li><a href="#contact">Contact</a></li>
          </ol>
        </nav>

        <h2 id="service">1. The Service</h2>
        <p>MobiWA helps businesses that sell through WhatsApp to:</p>
        <ul>
          <li>collect phone numbers from their own WhatsApp chat list (“Get Numbers”);</li>
          <li>have AI read selected chats and classify contacts as customers by request, or as junk (“AI Sort”);</li>
          <li>send their own messages, images, videos or documents to selected numbers (“Send Messages”).</li>
        </ul>
        <p>
          On Android this uses the Accessibility service; on a computer the web app at app.mobiwa.com uses the MobiWA
          Connector browser extension with WhatsApp Web. Features may change, and we may add, modify or remove features at any time.
        </p>

        <h2 id="accounts">2. Accounts</h2>
        <ul>
          <li>Accounts are created by us. You must give accurate information.</li>
          <li>Keep your password confidential. You are responsible for activity under your account.</li>
          <li>
            An account can be signed in on <b>one device at a time</b>. Signing out frees it for another device.
            We may end a session or suspend an account to protect the account or the Service.
          </li>
          <li>You must be at least 18 years old and able to enter a binding contract.</li>
        </ul>

        <h2 id="use">3. Acceptable use</h2>
        <p>You agree <b>not</b> to use the Service to:</p>
        <ul>
          <li>send spam, unsolicited bulk messages, or messages to people who have not agreed to be contacted or have asked you to stop;</li>
          <li>send content that is illegal, fraudulent, deceptive, harassing, hateful, sexually explicit, or that infringes others’ rights;</li>
          <li>promote prohibited goods or services (for example weapons, drugs, counterfeit goods, gambling where unlawful, or financial scams);</li>
          <li>collect or use personal data in breach of privacy, consumer-protection or anti-spam laws that apply to you;</li>
          <li>impersonate anyone, or hide the identity of your business;</li>
          <li>interfere with, reverse engineer, overload or attack the Service, or bypass the one-device limit or other security measures;</li>
          <li>resell or provide the Service to third parties without our written permission.</li>
        </ul>
        <p>
          You must keep a reasonable pause between messages, include a way for recipients to opt out where the law
          requires it, and promptly honour opt-out requests. We may investigate and act on suspected misuse.
        </p>

        <h2 id="whatsapp">4. WhatsApp and other third parties</h2>
        <p>
          The Service works with WhatsApp, WhatsApp Business and WhatsApp Web, which are provided by WhatsApp LLC under
          their own terms. You must comply with the WhatsApp Terms of Service, the WhatsApp Business Terms and the
          WhatsApp Business Messaging Policy. WhatsApp may limit, suspend or ban numbers at its sole discretion,
          including for automated or bulk messaging. <b>We are not responsible for any action WhatsApp takes on your
          number or account</b>, and changes made by WhatsApp to its apps may stop features from working until we
          update the Service. Other third-party services (such as Google Play, the Chrome Web Store, Supabase and Google’s AI)
          are governed by their own terms.
        </p>

        <h2 id="data">5. Your data and your customers</h2>
        <ul>
          <li>You keep all rights to the data you put into the Service (“Your Data”). You grant us the rights needed to host and process it to provide the Service, as described in the Privacy Policy.</li>
          <li>
            For your customers’ personal data you are the controller and we process it on your behalf. You confirm you
            have a lawful basis to collect, analyse and contact these people, and that you have given them any notices
            the law requires.
          </li>
          <li>You can export or delete Your Data, and delete your account, at any time (see the <Link to="/delete-account">deletion page</Link>).</li>
        </ul>

        <h2 id="ai">6. AI results</h2>
        <p>
          AI Sort uses an AI model to classify chats. Results can be wrong or incomplete. Review categories before
          relying on them, especially before sending messages. You are responsible for the decisions you make and the
          messages you send.
        </p>

        <h2 id="fees">7. Fees</h2>
        <p>
          If you have a paid plan, prices, billing and renewal terms are those agreed in your order or
          shown at purchase. Fees are non-refundable except where the law requires otherwise. We may change prices
          with at least 30 days’ notice; changes apply from your next billing period.
        </p>

        <h2 id="ip">8. Intellectual property</h2>
        <p>
          The Service, including its software, design, logos and content (excluding Your Data), belongs to {c} and its
          licensors. We grant you a limited, non-exclusive, non-transferable, revocable licence to use the Service under
          these Terms. “WhatsApp” is a trademark of WhatsApp LLC and is used only to describe compatibility.
        </p>

        <h2 id="termination">9. Suspension and termination</h2>
        <p>
          You may stop using the Service and delete your account at any time. We may suspend or terminate access,
          with notice where reasonable, if you breach these Terms, create risk or legal exposure for us or others, or
          if required by law. On termination your right to use the Service ends, and we delete your data as described
          in the Privacy Policy. Sections 4–6 and 8–15 survive termination.
        </p>

        <h2 id="disclaimer">10. Disclaimers</h2>
        <p>
          The Service is provided “as is” and “as available”. To the maximum extent permitted by law we disclaim all
          warranties, express or implied, including merchantability, fitness for a particular purpose and
          non-infringement. We do not guarantee that the Service will be uninterrupted, error-free, compatible with
          every version of WhatsApp or Android, or that messages will be delivered or read.
        </p>

        <h2 id="liability">11. Limitation of liability</h2>
        <p>
          To the maximum extent permitted by law, {c} will not be liable for indirect, incidental, special,
          consequential or punitive damages, or for loss of profits, revenue, data, goodwill, or WhatsApp account
          access. Our total liability for any claim relating to the Service is limited to the amount you paid us for
          the Service in the 12 months before the claim, or USD 100 if you paid nothing. Nothing in these Terms limits
          liability that cannot be limited by law.
        </p>

        <h2 id="indemnity">12. Indemnity</h2>
        <p>
          You will defend and indemnify {c} against claims, losses and costs (including reasonable legal fees) arising
          from your messages, Your Data, your breach of these Terms, or your breach of WhatsApp’s terms or of any law.
        </p>

        <h2 id="changes">13. Changes to these Terms</h2>
        <p>
          We may update these Terms. We will change the “Last updated” date and, for material changes, notify you in
          the app or by email at least 15 days before they take effect. Continuing to use the Service after that means
          you accept the new Terms.
        </p>

        <h2 id="law">14. Governing law</h2>
        <p>
          These Terms are governed by the laws of {company.jurisdiction}, without regard to conflict-of-law rules. The
          courts of {company.jurisdiction} have exclusive jurisdiction, except that mandatory consumer-protection rights
          of your country of residence still apply.
        </p>

        <h2 id="contact">15. Contact</h2>
        <p>
          {c}
          <br />
          {company.address}
          <br />
          <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>
        </p>
      </div>
    </article>
  );
}
