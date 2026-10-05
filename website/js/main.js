/* ══════════════════════════════════════════════════════════
   GymOS — Main JavaScript
   Handles: Scroll animations, navbar, FAQ, mobile menu,
            counter animation, smooth interactions
   ══════════════════════════════════════════════════════════ */

document.addEventListener('DOMContentLoaded', () => {
  initNavbar();
  initScrollAnimations();
  initFAQ();
  initMobileMenu();
  initCounterAnimation();
  initSmoothScroll();
});

/* ── Navbar scroll effect ── */
function initNavbar() {
  const navbar = document.querySelector('.navbar');
  if (!navbar) return;

  const onScroll = () => {
    if (window.scrollY > 50) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  };

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
}

/* ── Scroll Animations (IntersectionObserver) ── */
function initScrollAnimations() {
  const elements = document.querySelectorAll('.animate-on-scroll');
  if (!elements.length) return;

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    },
    {
      threshold: 0.1,
      rootMargin: '0px 0px -60px 0px',
    }
  );

  elements.forEach((el) => observer.observe(el));
}

/* ── FAQ Accordion ── */
function toggleFAQ(button) {
  const item = button.closest('.faq-item');
  if (!item) return;
  const wasActive = item.classList.contains('active');

  // Close all
  document.querySelectorAll('.faq-item').forEach((i) => i.classList.remove('active'));

  // Toggle current
  if (!wasActive) {
    item.classList.add('active');
  }
}
window.toggleFAQ = toggleFAQ;

function initFAQ() {
  const faqItems = document.querySelectorAll('.faq-item');
  if (!faqItems.length) return;

  faqItems.forEach((item) => {
    const question = item.querySelector('.faq-item__question');
    if (!question) return;

    // Avoid double event listeners if onclick is present or already bound
    if (!question.getAttribute('onclick') && !question.dataset.faqBound) {
      question.dataset.faqBound = 'true';
      question.addEventListener('click', () => toggleFAQ(question));
    }
  });
}

/* ── Mobile Menu ── */
function initMobileMenu() {
  const toggle = document.querySelector('.navbar__toggle');
  const links = document.querySelector('.navbar__links');
  const overlay = document.querySelector('.nav-overlay');

  if (!toggle || !links) return;

  const closeMenu = () => {
    toggle.classList.remove('active');
    links.classList.remove('open');
    if (overlay) overlay.classList.remove('active');
    document.body.style.overflow = '';
  };

  const openMenu = () => {
    toggle.classList.add('active');
    links.classList.add('open');
    if (overlay) overlay.classList.add('active');
    document.body.style.overflow = 'hidden';
  };

  toggle.addEventListener('click', () => {
    if (links.classList.contains('open')) {
      closeMenu();
    } else {
      openMenu();
    }
  });

  if (overlay) {
    overlay.addEventListener('click', closeMenu);
  }

  // Close on link click (mobile)
  links.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', closeMenu);
  });
}

/* ── Animated Counters ── */
function initCounterAnimation() {
  const counters = document.querySelectorAll('[data-count]');
  if (!counters.length) return;

  const animateCounter = (el) => {
    const target = parseInt(el.getAttribute('data-count'), 10);
    const suffix = el.getAttribute('data-suffix') || '';
    const prefix = el.getAttribute('data-prefix') || '';
    const duration = 2000;
    const start = 0;
    const startTime = performance.now();

    const update = (currentTime) => {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);

      // Ease out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(start + (target - start) * eased);

      el.textContent = prefix + current.toLocaleString('en-IN') + suffix;

      if (progress < 1) {
        requestAnimationFrame(update);
      }
    };

    requestAnimationFrame(update);
  };

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.3 }
  );

  counters.forEach((counter) => observer.observe(counter));
}

/* ── Smooth Scroll for anchor links ── */
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', function (e) {
      const href = this.getAttribute('href');
      if (href === '#') return;

      const target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        const navHeight = document.querySelector('.navbar')?.offsetHeight || 0;
        const targetPosition = target.getBoundingClientRect().top + window.scrollY - navHeight - 20;

        window.scrollTo({
          top: targetPosition,
          behavior: 'smooth',
        });
      }
    });
  });
}

/* ── Play Store Direct Redirect ── */
function showPlayStoreNotice(e) {
  if (e && e.preventDefault) e.preventDefault();
  window.open('https://play.google.com/store/apps/details?id=com.gymos.fitness.app.v1', '_blank');
}
function closePlayStoreModal() {}

window.showPlayStoreNotice = showPlayStoreNotice;
window.closePlayStoreModal = closePlayStoreModal;

/* ── App Store Release Notice Modal ── */
function showAppStoreNotice(e) {
  if (e && e.preventDefault) e.preventDefault();
  let modal = document.getElementById('appStoreModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'appStoreModal';
    modal.innerHTML = `
      <div class="modal-backdrop" onclick="closeAppStoreModal()"></div>
      <div class="modal-dialog">
        <div class="modal-icon" style="background:rgba(255,255,255,0.08);color:#fff;">
          <svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.61-.75 1.04-1.8 0.92-2.85-.9.04-2.01.6-2.65 1.35-.56.65-1.06 1.71-0.93 2.73 1.01.08 2.05-.48 2.66-1.23z"/></svg>
        </div>
        <h3 class="modal-title">iOS App In Review</h3>
        <p class="modal-desc">GymOS for iOS is currently under review by the Apple App Store team and will be released very soon! Please check back shortly to install it on your iPhone and iPad.</p>
        <button class="modal-btn" onclick="closeAppStoreModal()">Got it</button>
      </div>
    `;
    document.body.appendChild(modal);
  }
  modal.classList.add('active');
  document.body.style.overflow = 'hidden';
}

function closeAppStoreModal() {
  const modal = document.getElementById('appStoreModal');
  if (modal) modal.classList.remove('active');
  document.body.style.overflow = '';
}

window.showAppStoreNotice = showAppStoreNotice;
window.closeAppStoreModal = closeAppStoreModal;

// Close modals on Escape key
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    closePlayStoreModal();
    closeAppStoreModal();
  }
});
