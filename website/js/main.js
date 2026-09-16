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

/* ── Play Store Release Notice Modal ── */
function showPlayStoreNotice(e) {
  if (e) e.preventDefault();
  let modal = document.getElementById('playStoreModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'playStoreModal';
    modal.innerHTML = `
      <div class="modal-backdrop" onclick="closePlayStoreModal()"></div>
      <div class="modal-dialog">
        <div class="modal-icon">
          <svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><path d="M3.609 1.814L13.793 12 3.61 22.186c-.347-.291-.56-.723-.56-1.22V3.034c0-.497.213-.929.56-1.22zm10.89 10.89l2.257 2.258-10.74 6.202 8.483-8.46zm0-1.408L6.016 2.836l10.74 6.202-2.257 2.258zm1.409.704l3.197 1.846c.642.37.642.977 0 1.348l-3.197 1.846-1.89-1.89 1.89-1.85z"/></svg>
        </div>
        <h3 class="modal-title">App Not Released Yet</h3>
        <p class="modal-desc">GymOS is currently under review by the Google Play Store team and will be released very soon! Please check back shortly to install it on your Android device.</p>
        <button class="modal-btn" onclick="closePlayStoreModal()">Got it</button>
      </div>
    `;
    document.body.appendChild(modal);
  }
  modal.classList.add('active');
  document.body.style.overflow = 'hidden';
}

function closePlayStoreModal() {
  const modal = document.getElementById('playStoreModal');
  if (modal) modal.classList.remove('active');
  document.body.style.overflow = '';
}

window.showPlayStoreNotice = showPlayStoreNotice;
window.closePlayStoreModal = closePlayStoreModal;

// Close modal on Escape key
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closePlayStoreModal();
});
