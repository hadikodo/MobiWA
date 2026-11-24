// User management for admins. Uses the service-role key (only available on
// the server) to create, edit and delete Supabase Auth users.
//
// POST { action: "create", username, password, full_name?, role?, business_name?, business_description? }
// POST { action: "update", id, username?, password?, full_name?, role?, active?, business_name?, business_description? }
// POST { action: "delete", id }
// POST { action: "logout", id }   force sign-out from their device
// POST { action: "delete_self", confirm: "DELETE" }   any user deletes their own account
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

// Usernames without "@" are stored as <username>@users.mobiwa.app in Auth.
// Must match lib/data/auth.dart.
const USER_DOMAIN = "users.mobiwa.app";
const toEmail = (username: string) => (username.includes("@") ? username : `${username}@${USER_DOMAIN}`);
const USERNAME_RE = /^[a-z0-9._@-]{3,64}$/;

/** At least 10 characters with letters and digits. */
function passwordProblem(p: string): string | null {
  if (p.length < 10) return "Password must be at least 10 characters.";
  if (!/[A-Za-z]/.test(p) || !/\d/.test(p)) return "Password must contain letters and numbers.";
  return null;
}

/** Assurance level from the caller's JWT ("aal2" = signed in with a second factor). */
function aalOf(token: string): string {
  try {
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(payload + "=".repeat((4 - (payload.length % 4)) % 4))).aal ?? "aal1";
  } catch {
    return "aal1";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Caller must be an active admin.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user: caller } } = await admin.auth.getUser(token);
  if (!caller) return json({ error: "Please sign in again." }, 401);
  const { data: me } = await admin.from("profiles").select("role, active").eq("id", caller.id).single();

  // Any signed-in user may delete their own account (Google Play requirement).
  // Body must be { action: "delete_self", confirm: "DELETE" }.
  const peek = await req.clone().json().catch(() => ({}));
  if (peek?.action === "delete_self") {
    if (peek.confirm !== "DELETE") return json({ error: "Confirmation missing." }, 400);
    if (me?.role === "admin") {
      if (aalOf(token) !== "aal2") return json({ error: "Verify with your authenticator code first." }, 403);
      const { count } = await admin.from("profiles").select("id", { count: "exact", head: true })
        .eq("role", "admin").eq("active", true);
      if ((count ?? 0) <= 1) {
        return json({ error: "You are the only admin. Make another user admin first." }, 400);
      }
    }
    // Removes the auth user; profile, categories, contacts and activity cascade.
    const { error } = await admin.auth.admin.deleteUser(caller.id);
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true });
  }

  if (me?.role !== "admin" || !me.active) return json({ error: "Admins only." }, 403);
  // Admin actions need a session verified with the second factor (TOTP).
  if (aalOf(token) !== "aal2") {
    return json({ error: "Two-step verification required for admin actions." }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const str = (k: string) => (typeof body[k] === "string" ? (body[k] as string).trim() : undefined);
  const role = str("role");
  if (role !== undefined && role !== "user" && role !== "admin") return json({ error: "Role must be user or admin." }, 400);

  try {
    switch (body.action) {
      case "create": {
        const username = str("username")?.toLowerCase() ?? "";
        const password = typeof body.password === "string" ? body.password : "";
        if (!USERNAME_RE.test(username)) {
          return json({ error: "Username: 3-64 characters, letters, numbers, dot, dash or underscore." }, 400);
        }
        const pwErr = passwordProblem(password);
        if (pwErr) return json({ error: pwErr }, 400);

        const { data, error } = await admin.auth.admin.createUser({
          email: toEmail(username),
          password,
          email_confirm: true,
          user_metadata: { username, full_name: str("full_name") ?? "" },
          app_metadata: { role: role ?? "user" },
        });
        if (error) {
          const msg = /already/i.test(error.message) ? "This username is already taken." : error.message;
          return json({ error: msg }, 400);
        }
        // The DB trigger created the profile; apply role and business info.
        await admin.from("profiles").update({
          role: role ?? "user",
          business_name: str("business_name") ?? "",
          business_description: str("business_description") ?? "",
        }).eq("id", data.user.id);
        return json({ id: data.user.id });
      }

      case "update": {
        const id = str("id");
        if (!id) return json({ error: "Missing id" }, 400);
        const isSelf = id === caller.id;
        if (isSelf && (role === "user" || body.active === false)) {
          return json({ error: "You can't remove your own admin access." }, 400);
        }

        const authChanges: Record<string, unknown> = {};
        const username = str("username")?.toLowerCase();
        if (username !== undefined) {
          if (!USERNAME_RE.test(username)) return json({ error: "Invalid username." }, 400);
          authChanges.email = toEmail(username);
          authChanges.email_confirm = true;
          authChanges.user_metadata = { username };
        }
        if (typeof body.password === "string" && body.password.length > 0) {
          const pwErr = passwordProblem(body.password);
          if (pwErr) return json({ error: pwErr }, 400);
          authChanges.password = body.password;
        }
        if (typeof body.active === "boolean") {
          // Disabled users cannot sign in or refresh their session.
          authChanges.ban_duration = body.active ? "none" : "876000h";
        }
        if (Object.keys(authChanges).length) {
          const { error } = await admin.auth.admin.updateUserById(id, authChanges);
          if (error) {
            const msg = /already/i.test(error.message) ? "This username is already taken." : error.message;
            return json({ error: msg }, 400);
          }
        }

        const profileChanges: Record<string, unknown> = {};
        if (username !== undefined) profileChanges.username = username;
        if (role !== undefined) profileChanges.role = role;
        if (typeof body.active === "boolean") profileChanges.active = body.active;
        for (const k of ["full_name", "business_name", "business_description"]) {
          const v = str(k);
          if (v !== undefined) profileChanges[k] = v;
        }
        if (body.active === false) {
          // Disabled users are signed out of their device right away.
          profileChanges.device_id = null;
          profileChanges.device_token = null;
          profileChanges.device_name = "";
          profileChanges.device_bound_at = null;
        }
        if (Object.keys(profileChanges).length) {
          const { error } = await admin.from("profiles").update(profileChanges).eq("id", id);
          if (error) return json({ error: error.message }, 400);
        }
        if (body.active === false) await admin.rpc("revoke_user_sessions", { p_user_id: id });
        return json({ ok: true });
      }

      case "logout": {
        // Force sign-out: free the device slot and end every session. The
        // device loses data access immediately (RLS checks the device) and is
        // signed out at its next check.
        const id = str("id");
        if (!id) return json({ error: "Missing id" }, 400);
        if (id === caller.id) return json({ error: "Use Sign out in Settings to log yourself out." }, 400);
        const { error } = await admin.from("profiles")
          .update({ device_id: null, device_token: null, device_name: "", device_bound_at: null })
          .eq("id", id);
        if (error) return json({ error: error.message }, 400);
        const { error: e2 } = await admin.rpc("revoke_user_sessions", { p_user_id: id });
        if (e2) return json({ error: e2.message }, 400);
        return json({ ok: true });
      }

      case "delete": {
        const id = str("id");
        if (!id) return json({ error: "Missing id" }, 400);
        if (id === caller.id) return json({ error: "You can't delete your own account." }, 400);
        // Removes the auth user; profile, categories, contacts and activity cascade.
        const { error } = await admin.auth.admin.deleteUser(id);
        if (error) return json({ error: error.message }, 400);
        return json({ ok: true });
      }

      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
