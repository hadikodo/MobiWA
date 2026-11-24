import { Send, SearchUser, Sparkles } from './Icons';

/** Illustrative phone showing the app's home screen (pure CSS, no screenshot). */
export default function PhoneMockup() {
  return (
    <div className="phone-wrap" aria-hidden>
      <div className="phone">
        <div className="phone-notch" />
        <div className="phone-screen">
          <div className="ps-top">
            <img src="/logo.svg" alt="" />
            <div>
              <b>MobiWA</b>
              <small>248 numbers · 131 customers</small>
            </div>
          </div>

          <div className="ps-card">
            <div className="ps-ico" style={{ background: '#2f80ed' }}>
              <SearchUser size={20} color="#fff" />
            </div>
            <div>
              <b>1 · Get Numbers</b>
              <span>Collect every unsaved number from WhatsApp.</span>
            </div>
          </div>
          <div className="ps-card">
            <div className="ps-ico" style={{ background: '#8b5cf6' }}>
              <Sparkles size={20} color="#fff" />
            </div>
            <div>
              <b>2 · AI Sort</b>
              <span>Customers filed by what they asked for.</span>
              <span className="ps-badge" style={{ background: '#efe9fe', color: '#7c3aed' }}>
                37 waiting in Unnamed
              </span>
            </div>
          </div>
          <div className="ps-card">
            <div className="ps-ico" style={{ background: '#00a884' }}>
              <Send size={20} color="#fff" />
            </div>
            <div>
              <b>3 · Send Messages</b>
              <span>Text, photos, videos or PDFs — automatically.</span>
            </div>
          </div>

          <div className="ps-grid">
            <div className="ps-chip">
              📱 iPhone Repair<span>58</span>
            </div>
            <div className="ps-chip">
              🔋 Car Batteries<span>41</span>
            </div>
            <div className="ps-chip">
              🎂 Wedding Cakes<span>32</span>
            </div>
            <div className="ps-chip">
              🗑️ Junk<span>17</span>
            </div>
          </div>

          <div className="ps-nav">
            <span className="on">● Home</span>
            <span>Contacts</span>
            <span>Settings</span>
          </div>
        </div>
      </div>

      <div className="float-card one">
        <div className="dot" style={{ background: '#8b5cf6' }}>
          <Sparkles size={18} color="#fff" />
        </div>
        <div>
          <b>+961 70 ••• 590</b>
          <small>→ iPhone Repair</small>
        </div>
      </div>
      <div className="float-card two">
        <div className="dot" style={{ background: '#00a884' }}>
          <Send size={18} color="#fff" />
        </div>
        <div>
          <b>42 of 42 sent</b>
          <small>New offers this week 🎉</small>
        </div>
      </div>
    </div>
  );
}
