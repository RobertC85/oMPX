console.log('[oMPX] main.js loaded');
// --- Audio Processing Sliders: Double-click for numeric input ---

document.addEventListener('DOMContentLoaded', function() {
  function showUiError(msg) {
    var alertDiv = document.getElementById('ui-error-alert');
    if (alertDiv) {
      alertDiv.textContent = '[UI ERROR] ' + msg;
      alertDiv.style.display = '';
    } else {
      alert(msg);
    }
  }
  // --- Band Meter Visualizer ---
  // Use the first <audio> element on the page for metering
  const audio = document.querySelector('audio');
  if (audio && window.AudioContext) {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const src = ctx.createMediaElementSource(audio);
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 2048;
    src.connect(analyser);
    analyser.connect(ctx.destination);
    const freqData = new Uint8Array(analyser.frequencyBinCount);
    const bandDefs = [
      {name:'sub', lo:30, hi:120},
      {name:'low', lo:120, hi:400},
      {name:'mid', lo:400, hi:2000},
      {name:'pres', lo:2000, hi:6000},
      {name:'air', lo:6000, hi:15000},
    ];
    function updateBandMeters() {
      analyser.getByteFrequencyData(freqData);
      const nyquist = ctx.sampleRate / 2;
      const hzPerBin = nyquist / freqData.length;
      bandDefs.forEach((b) => {
        const start = Math.max(0, Math.floor(b.lo / hzPerBin));
        const end = Math.min(freqData.length - 1, Math.ceil(b.hi / hzPerBin));
        let sum = 0;
        let n = 0;
        for(let i=start;i<=end;i++){ sum += freqData[i] || 0; n++; }
        const avg = n > 0 ? (sum / n) : 0;
        const linear = Math.max(1e-6, avg / 255);
        const db = 20 * Math.log10(linear);
        const clampedDb = Math.max(-60, Math.min(0, db));
        const pct = ((clampedDb + 60) / 60) * 100;
        const fill = document.getElementById(`meter_${b.name}`);
        const label = document.getElementById(`meter_${b.name}_db`);
        if(fill) fill.style.width = `${pct.toFixed(1)}%`;
        if(label) label.textContent = `${db.toFixed(1)} dB`;
      });
    }
    function drawMeters() {
      updateBandMeters();
      requestAnimationFrame(drawMeters);
    }
    audio.addEventListener('play', () => ctx.resume());
    drawMeters();
  }

  const sliderIds = [
    'pre_gain_db','post_gain_db','parallel_dry_mix','stereo_width','hf_tame_db','hf_tame_freq','output_limit',
    'hpf_freq','lpf_freq','xover_1','xover_2','xover_3','xover_4',
    'band1_trim_db','band2_trim_db','band3_trim_db','band4_trim_db','band5_trim_db'
  ];
   // Add AGC controls to sliderIds
   const agcSliderIds = [
     'agc_freq','agc_gain','agc_max_gain','agc_peak'
   ];
   const allSliderIds = sliderIds.concat(agcSliderIds);
   allSliderIds.forEach(id => {
     try {
       const slider = document.getElementById(id);
       const valSpan = document.getElementById(id + '_val');
       if (!slider) return;
       // Update value span and send real-time update on slider input
       slider.addEventListener('input', () => {
         // Debug: log slider input
         console.log(`[oMPX] Slider #${id} input:`, slider.value);
         if (valSpan) {
           valSpan.textContent = slider.value;
         } else {
           showUiError('Value span #' + id + '_val not found for slider #' + id);
         }
         // Send real-time update to backend
         const program = window.currentProgram || 1; // Default to Program 1
         fetch('/api/update_param', {
           method: 'POST',
           headers: { 'Content-Type': 'application/json' },
           body: JSON.stringify({ program, param: id, value: slider.value })
         }).then(r => r.json()).then(data => {
           if (!data.ok) showUiError(data.message || 'Failed to update parameter');
         }).catch(e => showUiError('Network error: ' + e));
       });
       if (valSpan) valSpan.textContent = slider.value;
       // Double-click value span to edit
       if (valSpan) {
         valSpan.style.cursor = 'pointer';
         valSpan.title = 'Double-click to edit';
         valSpan.addEventListener('dblclick', function(e) {
           e.preventDefault();
           const num = document.createElement('input');
           num.type = 'number';
           num.value = slider.value;
           num.min = slider.min;
           num.max = slider.max;
           num.step = slider.step;
           num.style.width = '80px';
           num.style.marginLeft = '8px';
           valSpan.style.display = 'none';
           valSpan.parentNode.insertBefore(num, valSpan.nextSibling);
           num.focus();
           num.select();
           function finish() {
             let v = num.value;
             if (slider.min !== undefined && v < slider.min) v = slider.min;
             if (slider.max !== undefined && v > slider.max) v = slider.max;
             slider.value = v;
             valSpan.textContent = v;
             valSpan.style.display = '';
             num.remove();
             slider.dispatchEvent(new Event('input'));
           }
           num.addEventListener('blur', finish);
           num.addEventListener('keydown', function(ev) {
             if (ev.key === 'Enter') finish();
             if (ev.key === 'Escape') {
               valSpan.style.display = '';
               num.remove();
             }
           });
         });
       }
       // Double-click slider for numeric entry (keep this for power users)
       slider.addEventListener('dblclick', function(e) {
         e.preventDefault();
         const num = document.createElement('input');
         num.type = 'number';
         num.value = slider.value;
         num.min = slider.min;
         num.max = slider.max;
         num.step = slider.step;
         num.style.width = '80px';
         num.style.marginLeft = '8px';
         slider.style.display = 'none';
         slider.parentNode.insertBefore(num, slider.nextSibling);
         num.focus();
         num.select();
         function finish() {
           let v = num.value;
           if (slider.min !== undefined && v < slider.min) v = slider.min;
           if (slider.max !== undefined && v > slider.max) v = slider.max;
           slider.value = v;
           if (valSpan) valSpan.textContent = v;
           slider.style.display = '';
           num.remove();
           slider.dispatchEvent(new Event('input'));
         }
         num.addEventListener('blur', finish);
         num.addEventListener('keydown', function(ev) {
           if (ev.key === 'Enter') finish();
           if (ev.key === 'Escape') {
             slider.style.display = '';
             num.remove();
           }
         });
       });
     } catch (err) {
       showUiError('Slider/Value event error for #' + id + ': ' + (err && err.message ? err.message : err));
     }
   });

   // AGC filter string auto-update
   function updateAgcFilterString() {
     const f = document.getElementById('agc_freq').value;
     const g = document.getElementById('agc_gain').value;
     const m = document.getElementById('agc_max_gain').value;
     const p = document.getElementById('agc_peak').value;
     document.getElementById('agc_filter').value = `dynaudnorm=f=${f}:g=${g}:m=${m}:p=${p}`;
   }
   try {
     ['agc_freq','agc_gain','agc_max_gain','agc_peak'].forEach(id => {
       const el = document.getElementById(id);
       if (el) el.addEventListener('input', updateAgcFilterString);
     });
     updateAgcFilterString();
   } catch (err) {
     showUiError('AGC filter string update error: ' + (err && err.message ? err.message : err));
   }
});
// Theme switching logic
document.addEventListener('DOMContentLoaded', function() {
    // Program name editing logic
    function enableProgramNameEditing() {
      const programBtns = [
        document.querySelector('.menu-btn[data-section="program1"]'),
        document.querySelector('.menu-btn[data-section="program2"]')
      ];
      programBtns.forEach((btn, idx) => {
        if (!btn) return;
        btn.addEventListener('dblclick', function() {
          const currentName = btn.textContent;
          const input = document.createElement('input');
          input.type = 'text';
          input.value = currentName;
          input.style.width = (btn.offsetWidth - 8) + 'px';
          input.style.fontSize = 'inherit';
          input.style.fontWeight = 'inherit';
          input.style.background = '#222';
          input.style.color = 'var(--accent)';
          input.style.border = '1px solid var(--accent)';
          input.style.borderRadius = '8px';
          input.style.padding = '6px 8px';
          input.style.margin = '0';
          input.style.textAlign = 'center';
          btn.replaceWith(input);
          input.focus();
          input.select();
          function saveName() {
            const newName = input.value.trim() || currentName;
            btn.textContent = newName;
            input.replaceWith(btn);
          }
          input.addEventListener('blur', saveName);
          input.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
              saveName();
            } else if (e.key === 'Escape') {
              input.replaceWith(btn);
            }
          });
        });
      });
    }

  const themeSelect = document.getElementById('theme-select');
  const modernUI = document.getElementById('modern-ui');
  const legacyUI = document.getElementById('legacy-ui');
  const sidebar = document.getElementById('sidebar');
  function enableLegacyTabs() {
    // Legacy UI tab logic
    const tabProg1 = document.getElementById('tab_prog1');
    const tabProg2 = document.getElementById('tab_prog2');
    const tabGlobal = document.getElementById('tab_global');
    if (!tabProg1 || !tabProg2 || !tabGlobal) return;
    function setActiveTab(tab) {
      tabProg1.classList.toggle('active', tab === 'program1');
      tabProg2.classList.toggle('active', tab === 'program2');
      tabGlobal.classList.toggle('active', tab === 'global');
      document.querySelectorAll('.global-field').forEach(el => {
        el.classList.toggle('active', tab === 'global');
      });
      document.querySelectorAll('.program-field').forEach(el => {
        el.classList.remove('active');
        if (tab === 'program1' && el.classList.contains('program-1')) el.classList.add('active');
        if (tab === 'program2' && el.classList.contains('program-2')) el.classList.add('active');
      });
    }
    tabProg1.addEventListener('click', function() { setActiveTab('program1'); });
    tabProg2.addEventListener('click', function() { setActiveTab('program2'); });
    tabGlobal.addEventListener('click', function() { setActiveTab('global'); });
    setActiveTab('program1');
  }
  function setThemeUI(val) {
    console.log('[oMPX] setThemeUI called with:', val);
    if (val === 'legacy') {
      if (modernUI) modernUI.style.display = 'none';
      if (legacyUI) legacyUI.style.display = '';
      if (sidebar) sidebar.style.opacity = 0.3;
      enableLegacyTabs();
      console.log('[oMPX] Legacy UI should now be visible.');
    } else {
      if (modernUI) modernUI.style.display = '';
      if (legacyUI) legacyUI.style.display = 'none';
      if (sidebar) sidebar.style.opacity = 1;
      console.log('[oMPX] Modern UI should now be visible.');
    }
    // Fallback: if both are hidden, show legacy UI
    if (modernUI && legacyUI && modernUI.style.display === 'none' && legacyUI.style.display === 'none') {
      legacyUI.style.display = '';
      console.log('[oMPX] Fallback: Both UIs hidden, forcing legacy UI visible.');
    }
  }
  if (themeSelect) {
    themeSelect.addEventListener('change', function() {
      setThemeUI(themeSelect.value);
    });
    setThemeUI(themeSelect.value);
  }
  enableProgramNameEditing();
});
// main.js - Externalized JavaScript for oMPX Web UI
// (All logic moved from index.html for maintainability)

// Layout and theme switching logic
const layoutSelect = document.getElementById('layout-select');
const themeGroups = document.querySelectorAll('.theme-group');
const themeSidebar = document.getElementById('theme-sidebar');
const themeTopbar = document.getElementById('theme-topbar');
const themeOriginal = document.getElementById('theme-original');
const sidebarNav = document.getElementById('sidebar');
function setLayout(layout) {
  sidebarNav.style.display = (layout === 'sidebar') ? '' : 'none';
  themeGroups.forEach(g => g.style.display = 'none');
  if (layout === 'sidebar') themeSidebar.style.display = '';
  if (layout === 'topbar') themeTopbar.style.display = '';
  if (layout === 'original') themeOriginal.style.display = '';
}
if (layoutSelect) {
  layoutSelect.addEventListener('change', e => setLayout(e.target.value));
  setLayout('sidebar');
}
const themeOriginalSelect = document.getElementById('theme-original-select');
if (themeOriginalSelect) {
  themeOriginalSelect.addEventListener('change', function() {
    if (this.value === 'daylight') {
      this.style.color = '#fff';
      this.style.background = '#e0e0e0';
    } else {
      this.style.color = '';
      this.style.background = '';
    }
  });
}
// Patch audio preview logic
const programSelect = document.getElementById('program-select');
const patchAudio = document.getElementById('patch-audio');
const audioSource = document.getElementById('audio-source');
if (programSelect && patchAudio && audioSource) {
  programSelect.addEventListener('change', function() {
    const prog = programSelect.value;
    audioSource.src = `/api/preview.mp3?program=${prog}`;
    patchAudio.load();
  });
}

// --- oMPX Web UI Main Logic ---
document.addEventListener('DOMContentLoaded', function() {
  // Sidebar navigation
  document.querySelectorAll('.menu-btn').forEach(btn => {
    btn.addEventListener('click', function() {
      const section = btn.getAttribute('data-section');
      document.querySelectorAll('.section').forEach(sec => sec.style.display = 'none');
      const target = document.getElementById('section-' + section);
      if (target) target.style.display = '';
      document.querySelectorAll('.menu-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
  });
  // Show Program 1 by default
  const firstSection = document.getElementById('section-program1');
  if (firstSection) firstSection.style.display = '';
  const firstBtn = document.querySelector('.menu-btn[data-section="program1"]');
  if (firstBtn) firstBtn.classList.add('active');

  // Example: wire up Apply/Test/Undo buttons if present
  document.querySelectorAll('.apply-btn').forEach(btn => {
    btn.onclick = async () => {
      const cat = btn.getAttribute('data-cat');
      const prog = btn.getAttribute('data-prog');
      const resultEl = document.getElementById('action-result-' + cat.replace(/\W/g,'_') + '-' + prog);
      if (resultEl) resultEl.textContent = 'Applying...';
      // Collect values (customize as needed)
      const adv = window.collectAdvanced ? window.collectAdvanced(cat) : {};
      try {
        const res = await fetch(`/api/apply_mpx?v=${document.querySelector('.ompx-version')?.textContent || ''}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ program: parseInt(prog), category: cat, ...adv })
        });
        const data = await res.json();
        if (resultEl) resultEl.textContent = data.message || (data.ok ? 'Applied.' : 'Failed');
      } catch (e) {
        if (resultEl) resultEl.textContent = 'Error: ' + e;
      }
    };
  });
  document.querySelectorAll('.test-btn').forEach(btn => {
    let testActive = false;
    btn.onclick = async () => {
      const cat = btn.getAttribute('data-cat');
      const prog = btn.getAttribute('data-prog');
      const resultEl = document.getElementById('action-result-' + cat.replace(/\W/g,'_') + '-' + prog);
      if (!testActive) {
        if (resultEl) resultEl.textContent = 'Testing...';
        btn.textContent = 'Stop Test';
        const adv = window.collectAdvanced ? window.collectAdvanced(cat) : {};
        try {
          const res = await fetch(`/api/preview_start?v=${document.querySelector('.ompx-version')?.textContent || ''}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ program: parseInt(prog), category: cat, ...adv })
          });
          const data = await res.json();
          if (resultEl) resultEl.textContent = data.message || (data.ok ? 'Preview started.' : 'Failed');
          testActive = true;
        } catch (e) {
          if (resultEl) resultEl.textContent = 'Error: ' + e;
        }
      } else {
        if (resultEl) resultEl.textContent = '';
        btn.textContent = 'Test';
        testActive = false;
      }
    };
  });
  document.querySelectorAll('.undo-btn').forEach(btn => {
    btn.onclick = () => {
      const cat = btn.getAttribute('data-cat');
      const prog = btn.getAttribute('data-prog');
      const key = cat + '-' + prog;
      if (!window._settingsHistory) window._settingsHistory = {};
      if (!window._settingsHistory[key] || window._settingsHistory[key].length < 2) return;
      window._settingsHistory[key].pop();
      const prev = window._settingsHistory[key][window._settingsHistory[key].length - 1];
      if (prev) {
        Object.entries(prev).forEach(([k, v]) => {
          const el = document.getElementById(k);
          if (el) el.value = v;
        });
      }
    };
  });

  // Custom CSS support (now under global settings)
  const cssKey = 'ompx_custom_css';
  const cssArea = document.getElementById('custom-css');
  const cssBtn = document.getElementById('apply-css-btn');
  const cssStatus = document.getElementById('css-status');
  if (cssArea && window.localStorage) {
    cssArea.value = localStorage.getItem(cssKey) || '';
    applyCustomCSS(cssArea.value);
    if (cssBtn) {
      cssBtn.onclick = () => {
        const val = cssArea.value;
        localStorage.setItem(cssKey, val);
        applyCustomCSS(val);
        if (cssStatus) {
          cssStatus.textContent = 'Custom CSS applied.';
          setTimeout(() => { cssStatus.textContent = ''; }, 2000);
        }
      };
    }
  }
  function applyCustomCSS(css) {
    let styleTag = document.getElementById('custom-css-style');
    if (!styleTag) {
      styleTag = document.createElement('style');
      styleTag.id = 'custom-css-style';
      document.head.appendChild(styleTag);
    }
    styleTag.textContent = css;
  }

  // Helper for advanced controls (stub)
  window.collectAdvanced = function(cat) {
    // Implement as needed for your categories
    return {};
  };
});
