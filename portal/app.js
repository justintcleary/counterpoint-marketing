import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_EMAIL } from "./config.js";

export const configured =
  SUPABASE_URL.startsWith("http") && !SUPABASE_ANON_KEY.startsWith("YOUR_");

export const sb = configured
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  : null;

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

export function notice(el, message, kind = "bad") {
  if (!el) return;
  el.className = "note note-" + kind;
  el.textContent = message;
  el.classList.remove("hidden");
}

export function clearNotice(el) {
  if (el) el.classList.add("hidden");
}

export function fmtDate(value) {
  if (!value) return "No deadline";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short", day: "numeric", year: "numeric",
  });
}

export function statusPill(status) {
  const map = {
    approved: "pill-ok", open: "pill-ok", accepted: "pill-ok",
    pending: "pill-warn", submitted: "pill-warn", draft: "pill-warn",
    rejected: "pill-bad", declined: "pill-bad", closed: "pill-bad",
  };
  return `<span class="pill ${map[status] || ""}">${esc(status)}</span>`;
}

/* ------------------------------------------------------------------ */
/* configuration guard                                                 */
/* ------------------------------------------------------------------ */

export function requireConfig() {
  if (configured) return true;
  const main = $("#main") || document.body;
  main.innerHTML = `
    <div class="wrap narrow">
      <div class="note note-warn">
        <strong>Portal not connected yet.</strong><br>
        Add your Supabase URL and anon key in <code>portal/config.js</code>,
        then run <code>supabase/schema.sql</code> in the Supabase SQL editor.
        Setup steps are in <code>portal/SETUP.md</code>.
      </div>
    </div>`;
  return false;
}

/* ------------------------------------------------------------------ */
/* session + profile                                                   */
/* ------------------------------------------------------------------ */

export async function currentProfile() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return null;
  const { data, error } = await sb
    .from("profiles").select("*").eq("id", session.user.id).single();
  if (error) return null;
  return data;
}

// Redirects away if the visitor is not allowed on this page.
// need: "any" | "approved" | "admin"
export async function guard(need = "any") {
  const profile = await currentProfile();
  if (!profile) { location.href = "index.html"; return null; }
  if (need === "admin" && profile.role !== "admin") {
    location.href = "dashboard.html"; return null;
  }
  return profile;
}

export async function signOut() {
  await sb.auth.signOut();
  location.href = "index.html";
}

export function mountNav(profile, active) {
  const links = $("#navLinks");
  if (!links) return;
  const admin = profile?.role === "admin"
    ? `<a href="admin.html" class="${active === "admin" ? "active" : ""}">Admin</a>` : "";
  links.innerHTML = `
    <a href="dashboard.html" class="${active === "dashboard" ? "active" : ""}">Campaigns</a>
    ${admin}
    <span class="muted">${esc(profile?.full_name || profile?.email || "")}</span>
    <button id="signOutBtn">Sign out</button>`;
  $("#signOutBtn").addEventListener("click", signOut);
}

/* ------------------------------------------------------------------ */
/* email notifications (FormSubmit, no extra account needed)           */
/* ------------------------------------------------------------------ */

export async function notifyTeam(subject, fields) {
  try {
    await fetch("https://formsubmit.co/ajax/" + NOTIFY_EMAIL, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ _subject: subject, ...fields }),
    });
  } catch (err) {
    // Never block the user's action on a notification failure.
    console.warn("Notification failed", err);
  }
}
