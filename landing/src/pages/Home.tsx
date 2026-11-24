import { Link } from 'react-router-dom';
import { site } from '../config';
import ContactForm from '../components/ContactForm';
import PhoneMockup from '../components/PhoneMockup';
import PlayButton from '../components/PlayButton';
import {
  Chart,
  Check,
  Clock,
  Contacts,
  Folder,
  Globe,
  Heart,
  Image,
  Lock,
  Mail,
  Phone,
  SearchUser,
  Send,
  Shield,
  Sparkles,
  Store,
  Users,
} from '../components/Icons';

const steps = [
  {
    icon: <SearchUser size={28} color="#fff" />,
    color: '#2f80ed',
    title: 'Get Numbers',
    text: 'MobiWA scrolls through WhatsApp or WhatsApp Business and collects every chat from a number you never saved — in minutes, not hours.',
  },
  {
    icon: <Sparkles size={28} color="#fff" />,
    color: '#8b5cf6',
    title: 'AI Sort',
    text: 'Our AI reads each conversation and files real customers into categories named after what they asked for — “iPhone Repair”, “Car Batteries”… Everything else goes to Junk.',
  },
  {
    icon: <Send size={28} color="#fff" />,
    color: '#00a884',
    title: 'Send Messages',
    text: 'Pick categories, contacts or a pasted list, write your offer with a photo, video or PDF, and press Send. MobiWA delivers it to each number, one by one.',
  },
];

const features = [
  {
    icon: <Folder size={24} color="#00a884" />,
    bg: '#e3f7f1',
    title: 'Smart categories',
    text: 'Customers grouped by product or service automatically. Existing categories are reused, new ones created when needed.',
  },
  {
    icon: <Image size={24} color="#8b5cf6" />,
    bg: '#efe9fe',
    title: 'Rich messages',
    text: 'Send text, images, videos or PDF catalogs, with captions — the same way you would by hand.',
  },
  {
    icon: <Contacts size={24} color="#2f80ed" />,
    bg: '#e6effd',
    title: 'Your saved contacts too',
    text: 'Sort or message contacts from your phone book, filtered to the ones that use WhatsApp.',
  },
  {
    icon: <Users size={24} color="#f97316" />,
    bg: '#feeee2',
    title: 'Team accounts',
    text: 'Create an account for each salesperson. Each one works on their own phone; admins see everything.',
  },
  {
    icon: <Chart size={24} color="#0ea5e9" />,
    bg: '#e0f4fd',
    title: 'Admin dashboard',
    text: 'Numbers collected, customers found and messages sent — per user and per day.',
  },
  {
    icon: <Shield size={24} color="#16a34a" />,
    bg: '#e4f6ea',
    title: 'Private by design',
    text: 'Chats are read only when you start an action and are never stored. One account works on one device at a time.',
  },
];

const faqs = [
  {
    q: 'Do I need WhatsApp Business?',
    a: 'No. MobiWA works with WhatsApp and WhatsApp Business on Android. You choose which one at the start of each action. The web app works with WhatsApp Web.',
  },
  {
    q: 'What does the AI read, and is it stored?',
    a: 'Only the chats you ask it to sort. The text is sent to the AI to decide the category and is not stored. We keep the phone number, the chosen category and a short reason, so you can see why.',
  },
  {
    q: 'Why does the app need the Accessibility permission?',
    a: 'Android only lets an app work inside WhatsApp through the Accessibility service. MobiWA uses it only while an action you started is running — a STOP button is always on screen — and only inside WhatsApp.',
  },
  {
    q: 'Can WhatsApp limit my number?',
    a: 'Yes, if you message many people who do not expect it. Only message customers who contacted you or agreed to hear from you, keep a pause between messages (adjustable in Settings), and respect opt-outs. See our Terms of Service.',
  },
  {
    q: 'Can my sales team use it?',
    a: 'Yes. An admin creates accounts for each person. Each account can be signed in on one phone at a time, and the admin can sign anyone out remotely.',
  },
  {
    q: 'Does it work on a computer?',
    a: 'Yes — open the web app at app.mobiwa.com in Chrome, install the free MobiWA Connector extension, and keep WhatsApp Web open. The same three steps work there.',
  },
];

export default function Home() {
  return (
    <>
      {/* ------------------------------------------------------------- hero */}
      <section className="hero">
        <div className="container hero-grid">
          <div>
            <div className="pill">
              <b>NEW</b> AI sorts your WhatsApp customers for you
            </div>
            <h1>
              Turn WhatsApp chats into <span className="grad">loyal customers</span>
            </h1>
            <p className="lead">
              MobiWA collects every unsaved number from your WhatsApp, lets AI organise real customers by what they
              asked for, and sends them your offers — automatically.
            </p>
            <div className="hero-cta">
              <PlayButton />
              <a className="btn btn-ghost" href={site.appUrl}>
                <Globe size={20} /> Open the web app
              </a>
            </div>
            <div className="hero-note">
              <span>
                <Check size={16} color="#00a884" /> WhatsApp & WhatsApp Business
              </span>
              <span>
                <Check size={16} color="#00a884" /> Text, photos, videos, PDFs
              </span>
              <span>
                <Check size={16} color="#00a884" /> Android & web
              </span>
            </div>
          </div>
          <PhoneMockup />
        </div>
      </section>

      <div className="trust">
        <div className="container trust-row">
          <span>
            <Store size={18} /> Phone & electronics shops
          </span>
          <span>
            <Store size={18} /> Auto parts
          </span>
          <span>
            <Store size={18} /> Fashion & beauty
          </span>
          <span>
            <Store size={18} /> Bakeries & restaurants
          </span>
          <span>
            <Store size={18} /> Any store that sells on WhatsApp
          </span>
        </div>
      </div>

      {/* ------------------------------------------------------ how it works */}
      <section className="section" id="how">
        <div className="container">
          <div className="section-head">
            <div className="eyebrow">How it works</div>
            <h2>Three steps. No spreadsheets.</h2>
            <p>From a messy chat list to organised customers and a sent campaign — in one app.</p>
          </div>
          <div className="steps">
            {steps.map((s, i) => (
              <div className="step" key={s.title}>
                <span className="step-num">{i + 1}</span>
                <div className="step-icon" style={{ background: s.color }}>
                  {s.icon}
                </div>
                <h3>{s.title}</h3>
                <p>{s.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ---------------------------------------------------------- features */}
      <section className="section alt" id="features">
        <div className="container">
          <div className="section-head">
            <div className="eyebrow">Features</div>
            <h2>Everything a WhatsApp seller needs</h2>
            <p>Built for stores that get dozens of WhatsApp messages a day and lose track of who asked for what.</p>
          </div>
          <div className="features">
            {features.map((f) => (
              <div className="feature" key={f.title}>
                <div className="feature-icon" style={{ background: f.bg }}>
                  {f.icon}
                </div>
                <h3>{f.title}</h3>
                <p>{f.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------- audiences */}
      <section className="section" id="stores">
        <div className="container">
          <div className="section-head">
            <div className="eyebrow">Who it helps</div>
            <h2>Good for your store. Better for your customers.</h2>
          </div>
          <div className="split">
            <div className="audience stores">
              <div className="feature-icon" style={{ background: '#00a884' }}>
                <Store size={24} color="#fff" />
              </div>
              <h3>For stores</h3>
              <p>Stop losing sales in a long chat list.</p>
              <ul className="checks">
                <li>
                  <Check size={20} color="#00a884" />
                  <div>
                    <b>Never lose a lead</b>
                    <span>Every unsaved number who ever messaged you, in one place.</span>
                  </div>
                </li>
                <li>
                  <Check size={20} color="#00a884" />
                  <div>
                    <b>Know who wants what</b>
                    <span>Customers grouped by product, so each offer reaches the right people.</span>
                  </div>
                </li>
                <li>
                  <Check size={20} color="#00a884" />
                  <div>
                    <b>Hours saved every week</b>
                    <span>No copying numbers, no saving contacts, no sending one by one.</span>
                  </div>
                </li>
                <li>
                  <Check size={20} color="#00a884" />
                  <div>
                    <b>Your whole team, one view</b>
                    <span>Accounts for each salesperson and a dashboard for the owner.</span>
                  </div>
                </li>
              </ul>
            </div>
            <div className="audience customers">
              <div className="feature-icon" style={{ background: '#8b5cf6' }}>
                <Heart size={24} color="#fff" />
              </div>
              <h3>For your customers</h3>
              <p>Messages they actually want to receive.</p>
              <ul className="checks">
                <li>
                  <Check size={20} color="#8b5cf6" />
                  <div>
                    <b>Relevant offers</b>
                    <span>Someone who asked about phone repair hears about phone repair — not everything.</span>
                  </div>
                </li>
                <li>
                  <Check size={20} color="#8b5cf6" />
                  <div>
                    <b>Faster follow-up</b>
                    <span>Their request isn’t buried under hundreds of chats.</span>
                  </div>
                </li>
                <li>
                  <Check size={20} color="#8b5cf6" />
                  <div>
                    <b>On the app they already use</b>
                    <span>Photos, videos and catalogs right in WhatsApp — no new app to install.</span>
                  </div>
                </li>
                <li>
                  <Check size={20} color="#8b5cf6" />
                  <div>
                    <b>Respectful by default</b>
                    <span>Paced sending and clear guidance to message only people who opted in.</span>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------- platforms */}
      <section className="section alt">
        <div className="container">
          <div className="section-head">
            <div className="eyebrow">Use it anywhere</div>
            <h2>On your phone or your computer</h2>
            <p>One account, the same categories and customers on both.</p>
          </div>
          <div className="platforms">
            <div className="platform">
              <div className="feature-icon" style={{ background: '#e3f7f1' }}>
                <Phone size={24} color="#00a884" />
              </div>
              <h3>Android app</h3>
              <p>Works with WhatsApp and WhatsApp Business on your phone. Download it from Google Play.</p>
              <PlayButton />
            </div>
            <div className="platform">
              <div className="feature-icon" style={{ background: '#e6effd' }}>
                <Globe size={24} color="#2f80ed" />
              </div>
              <h3>Web app</h3>
              <p>
                Open <b>app.mobiwa.com</b> in Chrome with the free MobiWA Connector extension and WhatsApp Web. Great
                for big campaigns from your desk.
              </p>
              <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginTop: 'auto' }}>
                <a className="btn btn-primary" href={site.appUrl}>
                  Open web app
                </a>
                <Link className="btn btn-ghost" to="/extension">
                  Get the extension
                </Link>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------------- faq */}
      <section className="section" id="faq">
        <div className="container">
          <div className="section-head">
            <div className="eyebrow">FAQ</div>
            <h2>Questions, answered</h2>
          </div>
          <div className="faq">
            {faqs.map((f) => (
              <details key={f.q}>
                <summary>{f.q}</summary>
                <p>{f.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* -------------------------------------------------------------- cta */}
      <section className="container" style={{ paddingBottom: 96 }}>
        <div className="cta-band">
          <div>
            <h2>Ready to sell more on WhatsApp?</h2>
            <p>Install MobiWA and run your first AI Sort today.</p>
          </div>
          <PlayButton />
        </div>
      </section>

      {/* ---------------------------------------------------------- contact */}
      <section className="section alt" id="contact">
        <div className="container contact-grid">
          <div className="contact-info">
            <div className="eyebrow">Contact us</div>
            <h2>Let’s talk about your store</h2>
            <p>
              Want accounts for your team, a demo, or help with the app? Send us a message and we’ll get back to you
              within one business day.
            </p>
            <div className="contact-lines">
              <a href={`mailto:${site.salesEmail}`}>
                <Mail size={20} color="#00a884" /> {site.salesEmail}
              </a>
              <a href={`mailto:${site.supportEmail}`}>
                <Mail size={20} color="#00a884" /> {site.supportEmail}
              </a>
              <div>
                <Clock size={20} color="#00a884" /> Replies within 1 business day
              </div>
              <div>
                <Lock size={20} color="#00a884" /> Your details are only used to reply to you
              </div>
            </div>
          </div>
          <ContactForm />
        </div>
      </section>
    </>
  );
}
