// Sticky nav border on scroll
const nav = document.getElementById("nav");
window.addEventListener("scroll", () => {
  nav.classList.toggle("scrolled", window.scrollY > 10);
});

// Mobile menu
const toggle = document.getElementById("navToggle");
const links = document.querySelector(".nav-links");
toggle.addEventListener("click", () => links.classList.toggle("open"));
links.querySelectorAll("a").forEach((a) =>
  a.addEventListener("click", () => links.classList.remove("open"))
);

// Scroll-reveal
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.12 }
);

document
  .querySelectorAll(".card, .process-step, .tier, .market-list li, .split-text, .split-card, .section h2, .kicker")
  .forEach((el) => {
    el.classList.add("reveal");
    observer.observe(el);
  });

// Contact form (no backend yet; acknowledge locally)
const form = document.getElementById("contactForm");
const note = document.getElementById("formNote");
form.addEventListener("submit", (e) => {
  e.preventDefault();
  note.textContent =
    "Thanks! The form backend isn't wired up yet. Reach out directly and we'll get back to you fast.";
  form.reset();
});

// Cursor glow (pointer devices only, skip if reduced motion)
const glow = document.getElementById("cursorGlow");
const fancyOK =
  window.matchMedia("(pointer: fine)").matches &&
  !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
if (glow && fancyOK) {
  window.addEventListener("mousemove", (e) => {
    glow.style.opacity = "1";
    glow.style.left = e.clientX + "px";
    glow.style.top = e.clientY + "px";
  }, { passive: true });
}

// Footer year
document.getElementById("year").textContent = new Date().getFullYear();
