import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_EMAIL } from "./config.js?v=3";

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
    pending: "pill-warn", submitted: "pill-warn", draft: "pill-warn", review: "pill-lime",
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

// Where each kind of account lands after signing in.
export function homeFor(profile) {
  if (!profile) return "index.html";
  if (profile.role === "admin") return "admin.html";
  if (profile.role === "client") return "client.html";
  return "dashboard.html";
}

// Redirects away if the visitor is not allowed on this page.
// need: "any" | "creator" | "client" | "admin"
export async function guard(need = "any") {
  const profile = await currentProfile();
  if (!profile) { location.href = "index.html"; return null; }
  const ok =
    need === "any" ||
    (need === "admin"   && profile.role === "admin") ||
    (need === "client"  && profile.role === "client") ||
    (need === "creator" && profile.role !== "client");
  if (!ok) { location.href = homeFor(profile); return null; }
  return profile;
}

export async function signOut() {
  await sb.auth.signOut();
  location.href = "index.html";
}

export function mountNav(profile, active) {
  const links = $("#navLinks");
  if (!links) return;
  const a = (href, label, key) =>
    `<a href="${href}" class="${active === key ? "active" : ""}">${label}</a>`;
  let items = "";
  if (profile?.role === "client") {
    items = a("client.html", "Your campaigns", "client");
  } else {
    items = a("dashboard.html", "Campaigns", "dashboard");
    if (profile?.role === "admin") items += a("admin.html", "Admin", "admin");
  }
  links.innerHTML = `
    ${items}
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

/* ------------------------------------------------------------------ */
/* content tracking                                                    */
/* ------------------------------------------------------------------ */

// Must match content_items_stage_check in schema.sql, in pipeline order.
export const STAGES = [
  "not started", "drafting", "submitted for review",
  "changes requested", "approved", "scheduled", "posted",
];

export const CAMPAIGN_STATUSES = ["draft", "review", "open", "closed"];

export function stagePill(stage) {
  const cls = {
    "not started": "", "drafting": "pill-warn", "submitted for review": "pill-lime",
    "changes requested": "pill-bad", "approved": "pill-ok", "scheduled": "pill-ok",
    "posted": "pill-ok",
  }[stage] || "";
  return `<span class="pill ${cls}">${esc(stage)}</span>`;
}

// 0 to 100, how far along a set of content items is.
export function progressOf(items) {
  if (!items.length) return 0;
  const score = (it) => Math.max(0, STAGES.indexOf(it.stage)) / (STAGES.length - 1);
  return Math.round(items.reduce((sum, it) => sum + score(it), 0) / items.length * 100);
}

export function progressBar(items) {
  const pct = progressOf(items);
  const posted = items.filter(i => i.stage === "posted").length;
  return `<div class="progress" title="${pct}% complete">
    <div class="progress-bar" style="width:${pct}%"></div></div>
    <span class="muted">${posted}/${items.length} posted</span>`;
}

// Plain-language label for a campaign status, from the client's seat.
export function campaignStatusLabel(status) {
  return {
    draft: "Draft", review: "With counterpoint", open: "Live with creators", closed: "Closed",
  }[status] || status;
}

/* ------------------------------------------------------------------ */
/* social handles, one column per platform                            */
/* ------------------------------------------------------------------ */

export const PLATFORMS = [
  { key: "tiktok_handle",    label: "TikTok",    url: (h) => `https://www.tiktok.com/@${h}` },
  { key: "instagram_handle", label: "Instagram", url: (h) => `https://www.instagram.com/${h}` },
  { key: "youtube_handle",   label: "YouTube",   url: (h) => `https://www.youtube.com/@${h}` },
  { key: "x_handle",         label: "X",         url: (h) => `https://x.com/${h}` },
];

// "@name", "name", or a pasted profile URL all become "name".
export function cleanHandle(value) {
  let v = String(value || "").trim();
  if (!v) return null;
  if (v.includes("/")) {
    try {
      const url = new URL(/^https?:\/\//i.test(v) ? v : "https://" + v);
      const parts = url.pathname.split("/").filter(Boolean);
      // Prefer an @segment, otherwise the first segment that is not a
      // platform prefix like youtube.com/c/… or youtube.com/user/…
      v = parts.find((x) => x.startsWith("@"))
        || parts.find((x) => !["c", "channel", "user", "profile"].includes(x.toLowerCase()))
        || "";
    } catch { /* leave as typed */ }
  }
  v = v.replace(/^@+/, "").replace(/[?#].*$/, "").trim();
  return v || null;
}

export function hasAnyHandle(obj) {
  return PLATFORMS.some((p) => obj[p.key]) || !!obj.handles;
}

// Linked chips, one per platform, plus any free-text "other" handles.
export function handleLinks(obj) {
  const chips = PLATFORMS.filter((p) => obj[p.key]).map((p) =>
    `<a class="tag tag-link" href="${esc(p.url(obj[p.key]))}" target="_blank" rel="noopener">${p.label} @${esc(obj[p.key])}</a>`);
  if (obj.handles) chips.push(`<span class="tag">${esc(obj.handles)}</span>`);
  return chips.length ? `<div class="tags tags-tight">${chips.join("")}</div>` : "";
}

// Plain text for notification emails.
export function handleText(obj) {
  const bits = PLATFORMS.filter((p) => obj[p.key]).map((p) => `${p.label} @${obj[p.key]}`);
  if (obj.handles) bits.push(obj.handles);
  return bits.join(", ");
}

/* ------------------------------------------------------------------ */
/* modal + creator profile popup                                       */
/* ------------------------------------------------------------------ */

export function showModal(html) {
  closeModal();
  const wrap = document.createElement("div");
  wrap.className = "modal-backdrop";
  wrap.id = "modal";
  wrap.innerHTML = `<div class="modal" role="dialog" aria-modal="true">
    <button class="modal-close" aria-label="Close">&times;</button>
    ${html}</div>`;
  document.body.appendChild(wrap);
  document.body.classList.add("modal-open");
  wrap.addEventListener("click", (e) => { if (e.target === wrap) closeModal(); });
  wrap.querySelector(".modal-close").addEventListener("click", closeModal);
  document.addEventListener("keydown", escClose);
}

export function closeModal() {
  $("#modal")?.remove();
  document.body.classList.remove("modal-open");
  document.removeEventListener("keydown", escClose);
}

function escClose(e) { if (e.key === "Escape") closeModal(); }

// Everything we know about a creator, from whichever rows the viewer has.
// p: profile-shaped object (may be a directory row with no email).
// applications: rows with campaign_title, status, pitch, created_at.
// content: rows with campaign_title, title, stage, due_date, post_url.
export function creatorModal(p, { applications = [], content = [], showEmail = false } = {}) {
  const demo = [
    p.age ? `${p.age} years old` : null, p.gender, p.political_leaning, p.location,
  ].filter(Boolean);
  const row = (label, value) => value
    ? `<div class="kv"><span>${label}</span><div>${value}</div></div>` : "";

  showModal(`
    <p class="kicker">${p.role === "client" ? "Client" : "Creator"}</p>
    <h2 style="margin:0 0 4px">${esc(p.full_name || "Unnamed")}
      ${p.role === "admin" ? ' <span class="pill pill-lime">admin</span>' : ""}
      ${p.status ? " " + statusPill(p.status) : ""}</h2>
    ${showEmail && p.email ? `<p class="muted" style="margin:0 0 12px"><a class="linklike" href="mailto:${esc(p.email)}">${esc(p.email)}</a></p>` : ""}
    ${handleLinks(p) || '<p class="faint">No handles on file.</p>'}
    <div class="kv-grid">
      ${row("Audience", esc(p.audience_size || ""))}
      ${row("Interests", interestChips(p, "tag-interest"))}
      ${row("Demographics", demo.length ? demo.map(esc).join(" · ") : "")}
      ${row("Joined", p.created_at ? fmtDate(p.created_at) : "")}
      ${row("Notes", p.notes ? `<span style="white-space:pre-wrap">${esc(p.notes)}</span>` : "")}
    </div>
    ${applications.length ? `
      <h3 class="modal-h3">Applications</h3>
      ${applications.map(a => `
        <div class="applicant">
          <div class="spread"><strong>${esc(a.campaign_title)}</strong>${statusPill(a.status)}</div>
          <div class="muted">${fmtDate(a.created_at)}</div>
          ${a.pitch ? `<div style="margin-top:4px">${esc(a.pitch)}</div>` : ""}
        </div>`).join("")}` : ""}
    ${content.length ? `
      <h3 class="modal-h3">Content</h3>
      ${content.map(i => `
        <div class="applicant">
          <div class="spread"><strong>${esc(i.title || "Deliverable")}</strong>${stagePill(i.stage)}</div>
          <div class="muted">${esc(i.campaign_title)} · due ${fmtDate(i.due_date)}</div>
          ${i.post_url ? `<a class="linklike" href="${esc(i.post_url)}" target="_blank" rel="noopener">${esc(i.post_url)}</a>` : ""}
        </div>`).join("")}` : ""}
  `);
}

// Wrap a creator's name so a click opens their profile. Pages listen for
// [data-person] clicks once, via delegation, so re-rendering is free.
export function nameLink(id, name) {
  return `<button type="button" class="namelink" data-person="${esc(id)}">${esc(name || "Unnamed")}</button>`;
}

/* ------------------------------------------------------------------ */
/* interests: up to five tags per creator                             */
/* ------------------------------------------------------------------ */

export const MAX_INTERESTS = 5;

export const INTEREST_SUGGESTIONS = [
  "politics", "news", "lifestyle", "fashion", "beauty", "fitness", "health",
  "food", "travel", "parenting", "family", "finance", "business", "tech",
  "gaming", "sports", "music", "comedy", "education", "faith", "outdoors",
  "cars", "home", "pets", "art", "books", "college", "military", "small business",
];

export function cleanInterest(value) {
  return String(value || "").trim().toLowerCase().replace(/\s+/g, " ").slice(0, 30);
}

export function interestChips(obj, cls = "") {
  const tags = Array.isArray(obj.interests) ? obj.interests : [];
  if (tags.length) {
    return `<div class="tags tags-tight">${tags.map((t) => `<span class="tag ${cls}">${esc(t)}</span>`).join("")}</div>`;
  }
  return obj.niche ? `<span class="muted">${esc(obj.niche)}</span>` : "";
}

// A chip-style tag editor. Type and press Enter or comma, or click a
// suggestion. Returns { get() } for reading the current tags.
export function mountTagInput(root, { initial = [], max = MAX_INTERESTS,
                                      suggestions = INTEREST_SUGGESTIONS,
                                      placeholder = "Type an interest and press Enter" } = {}) {
  let tags = [...new Set(initial.map(cleanInterest).filter(Boolean))].slice(0, max);
  root.classList.add("taginput");
  root.innerHTML = `
    <div class="taginput-box">
      <div class="taginput-chips"></div>
      <input type="text" class="taginput-field" placeholder="${esc(placeholder)}" autocomplete="off">
    </div>
    <div class="taginput-suggest"></div>
    <div class="taginput-count muted"></div>`;
  const chips = root.querySelector(".taginput-chips");
  const field = root.querySelector(".taginput-field");
  const sugg = root.querySelector(".taginput-suggest");
  const count = root.querySelector(".taginput-count");

  const add = (value) => {
    const v = cleanInterest(value);
    if (!v || tags.includes(v) || tags.length >= max) return;
    tags.push(v); field.value = ""; render();
  };
  const remove = (v) => { tags = tags.filter((t) => t !== v); render(); };

  function render() {
    chips.innerHTML = tags.map((t) =>
      `<span class="tag tag-edit">${esc(t)}<button type="button" aria-label="Remove ${esc(t)}" data-rm="${esc(t)}">&times;</button></span>`).join("");
    chips.querySelectorAll("[data-rm]").forEach((b) => b.addEventListener("click", () => remove(b.dataset.rm)));
    const full = tags.length >= max;
    field.disabled = full;
    field.placeholder = full ? `That's ${max}, remove one to change` : placeholder;
    const q = cleanInterest(field.value);
    const shown = suggestions.filter((s) => !tags.includes(s) && (!q || s.includes(q))).slice(0, 12);
    sugg.innerHTML = full ? "" : shown.map((s) =>
      `<button type="button" class="tag tag-suggest" data-add="${esc(s)}">+ ${esc(s)}</button>`).join("");
    sugg.querySelectorAll("[data-add]").forEach((b) => b.addEventListener("click", () => add(b.dataset.add)));
    count.textContent = `${tags.length} of ${max}`;
  }

  field.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === ",") { e.preventDefault(); add(field.value); }
    else if (e.key === "Backspace" && !field.value && tags.length) remove(tags[tags.length - 1]);
  });
  field.addEventListener("input", render);
  field.addEventListener("blur", () => { if (field.value.trim()) add(field.value); });
  render();
  return { get: () => [...tags], set: (next) => { tags = [...next]; render(); } };
}
