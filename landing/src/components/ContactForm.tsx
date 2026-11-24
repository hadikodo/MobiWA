import { FormEvent, useState } from 'react';
import { site, supabase } from '../config';

type Topic = 'general' | 'sales' | 'support' | 'account_deletion' | 'privacy';

const topics: { value: Topic; label: string }[] = [
  { value: 'sales', label: 'I want MobiWA for my store' },
  { value: 'support', label: 'Help with the app' },
  { value: 'general', label: 'General question' },
  { value: 'privacy', label: 'Privacy / my data' },
  { value: 'account_deletion', label: 'Delete my account' },
];

/**
 * Sends to the Supabase table `contact_messages` (insert-only for visitors;
 * the MobiWA team reads it in the app's Admin → Inbox). Falls back to email if the
 * request fails.
 */
export default function ContactForm({ defaultTopic = 'sales' }: { defaultTopic?: Topic }) {
  const [state, setState] = useState<'idle' | 'sending' | 'sent' | 'error'>('idle');
  const [error, setError] = useState('');

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const data = new FormData(form);
    if (data.get('website')) return; // honeypot: bots fill hidden fields

    const body = {
      name: String(data.get('name') ?? '').trim(),
      email: String(data.get('email') ?? '').trim(),
      business: String(data.get('business') ?? '').trim(),
      topic: String(data.get('topic') ?? 'general'),
      message: String(data.get('message') ?? '').trim(),
    };
    if (body.message.length < 5) {
      setState('error');
      setError('Please write a little more in your message.');
      return;
    }

    setState('sending');
    setError('');
    try {
      if (!supabase.url || !supabase.key) throw new Error('Contact form is not configured.');
      const res = await fetch(`${supabase.url}/rest/v1/contact_messages`, {
        method: 'POST',
        headers: {
          apikey: supabase.key,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const j = await res.json().catch(() => ({}));
        throw new Error(
          String(j?.message ?? '').includes('Too many')
            ? 'You sent several messages recently. Please try again in an hour.'
            : 'We could not send your message.',
        );
      }
      setState('sent');
      form.reset();
    } catch (err) {
      setState('error');
      setError(err instanceof Error ? err.message : 'We could not send your message.');
    }
  }

  if (state === 'sent') {
    return (
      <div className="form">
        <div className="form-msg ok">Thanks! Your message was sent. We usually reply within one business day.</div>
        <button className="btn btn-ghost" onClick={() => setState('idle')}>
          Send another message
        </button>
      </div>
    );
  }

  return (
    <form className="form" onSubmit={onSubmit} noValidate={false}>
      <div className="form-row">
        <div className="field">
          <label htmlFor="cf-name">Your name</label>
          <input id="cf-name" name="name" required maxLength={100} autoComplete="name" />
        </div>
        <div className="field">
          <label htmlFor="cf-email">Email</label>
          <input id="cf-email" name="email" type="email" required maxLength={200} autoComplete="email" />
        </div>
      </div>
      <div className="form-row">
        <div className="field">
          <label htmlFor="cf-business">Store / business (optional)</label>
          <input id="cf-business" name="business" maxLength={150} autoComplete="organization" />
        </div>
        <div className="field">
          <label htmlFor="cf-topic">Topic</label>
          <select id="cf-topic" name="topic" defaultValue={defaultTopic}>
            {topics.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div className="field">
        <label htmlFor="cf-message">Message</label>
        <textarea id="cf-message" name="message" required minLength={5} maxLength={4000} />
      </div>
      {/* Honeypot — hidden from people, filled by bots. */}
      <div className="hp" aria-hidden>
        <label>
          Website <input name="website" tabIndex={-1} autoComplete="off" />
        </label>
      </div>
      {state === 'error' && (
        <div className="form-msg err">
          {error} You can also email us at <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>.
        </div>
      )}
      <button className="btn btn-primary" type="submit" disabled={state === 'sending'}>
        {state === 'sending' ? 'Sending…' : 'Send message'}
      </button>
      <small>
        By sending this form you agree that we use your details to answer you, as described in our{' '}
        <a href="/privacy">Privacy Policy</a>.
      </small>
    </form>
  );
}
