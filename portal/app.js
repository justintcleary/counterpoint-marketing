import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_EMAIL } from "./config.js?v=2";

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

/* ------------------------------------------------------------------ */
/* demographics vocabulary (must match the checks in schema.sql)       */
/* ------------------------------------------------------------------ */

export const GENDERS = ["woman", "man", "non-binary", "other", "prefer not to say"];

export const LEANINGS = [
  "left", "lean left", "moderate", "lean right", "right",
  "non-political", "prefer not to say",
];

// Campaign targeting uses the same words minus the opt-outs, plus "any".
export const TARGET_GENDERS = ["any", "woman", "man", "non-binary"];
export const TARGET_LEANINGS = [
  "any", "left", "lean left", "moderate", "lean right", "right", "non-political",
];

export function optionList(values, selected) {
  return values
    .map((v) => `<option value="${esc(v)}"${v === selected ? " selected" : ""}>${esc(v)}</option>`)
    .join("");
}

// Plain-language age range, e.g. "20-40", "40+", "under 25".
export function ageRangeLabel(min, max) {
  if (min && max) return `${min}-${max}`;
  if (min) return `${min}+`;
  if (max) return `under ${max}`;
  return "";
}

// The chips shown under a campaign title: who this campaign is looking for.
export function targetChips(campaign) {
  const bits = [];
  const g = campaign.target_gender;
  if (g && g !== "any") bits.push(g === "woman" ? "women" : g === "man" ? "men" : g);
  const age = ageRangeLabel(campaign.target_age_min, campaign.target_age_max);
  if (age) bits.push(age);
  if (campaign.target_leaning && campaign.target_leaning !== "any") {
    bits.push(campaign.target_leaning);
  }
  if (campaign.target_location) bits.push(campaign.target_location);
  if (campaign.target_niche) bits.push(campaign.target_niche);
  if (!bits.length) bits.push("open to everyone");
  return bits.map((b) => `<span class="tag">${esc(b)}</span>`).join("");
}

// Does this creator match what the campaign is asking for? Used to sort
// campaigns, never to hide them: creators can still apply to anything.
export function matchesTarget(campaign, profile) {
  if (!profile) return false;
  const g = campaign.target_gender;
  if (g && g !== "any" && profile.gender && profile.gender !== g) return false;
  if (campaign.target_age_min && profile.age && profile.age < campaign.target_age_min) return false;
  if (campaign.target_age_max && profile.age && profile.age > campaign.target_age_max) return false;
  const l = campaign.target_leaning;
  if (l && l !== "any" && profile.political_leaning && profile.political_leaning !== l) return false;
  return true;
}
