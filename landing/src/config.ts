/**
 * Everything that may change between environments or needs your company
 * details lives here. Legal pages read their company info from `company`.
 *
 * TODO before going live: fill in `company.legalName`, `company.address`
 * and `company.jurisdiction` (they appear in the Privacy Policy and Terms).
 */
export const site = {
  name: 'MobiWA',
  domain: 'mobiwa.com',
  url: 'https://mobiwa.com',
  appUrl: 'https://app.mobiwa.com',
  playStoreUrl: 'https://play.google.com/store/apps/details?id=com.mobiwa.app',
  /** MobiWA Connector on the Chrome Web Store — set once it is published. */
  chromeExtensionUrl: '',
  supportEmail: 'support@mobiwa.com',
  privacyEmail: 'privacy@mobiwa.com',
  salesEmail: 'sales@mobiwa.com',
};

export const company = {
  /** Legal entity that operates MobiWA, e.g. "MobiWA SAL" or "Your Company LLC". */
  legalName: 'MobiWA',
  /** Registered address shown in the legal pages. */
  address: '[Registered company address]',
  /** Courts / law that govern the Terms, e.g. "Lebanon". */
  jurisdiction: '[Country of incorporation]',
};

/** Dates shown at the top of the legal pages. */
export const legal = {
  privacyUpdated: 'November 23, 2026',
  termsUpdated: 'November 23, 2026',
};

export const supabase = {
  url: import.meta.env.VITE_SUPABASE_URL as string | undefined,
  key: import.meta.env.VITE_SUPABASE_KEY as string | undefined,
};
