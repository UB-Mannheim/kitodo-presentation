// translation.js - Clean and Reliable Version
(function() {
  'use strict';

  // Configuration
  const CONFIG = {
    apiUrl: 'BASE_URL/ollama-proxy.php',
    targetElementId: 'tx-dlf-fulltextselection',
    popupZIndex: '10000',
    timeout: 45000
  };

  // Create UI elements
  function createStatusElement() {
    const el = document.createElement('div');
    el.id = 'ocr-translation-status';
    el.style.cssText = `
      position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
      background: #3498db; color: white; padding: 12px 24px; border-radius: 6px;
      z-index: ${CONFIG.popupZIndex}; font-family: Arial, sans-serif; 
      box-shadow: 0 2px 8px rgba(0,0,0,0.2); font-size: 16px;
      min-width: 300px; text-align: center; cursor: pointer;
      transition: background-color 0.3s;
    `;
    el.textContent = '🔍 Scanning for OCR text...';
    return el;
  }

  function createPopupElement() {
    const el = document.createElement('div');
    el.id = 'ocr-translation-popup';
    el.style.cssText = `
      position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);
      width: 90%; max-width: 700px; background: white; border: 1px solid #ddd;
      border-radius: 8px; box-shadow: 0 4px 20px rgba(0,0,0,0.2); 
      z-index: ${parseInt(CONFIG.popupZIndex) + 1};
      padding: 25px; opacity: 0; transition: opacity 0.3s;
      pointer-events: none;
    `;
    el.innerHTML = `
      <div style="text-align:center;margin-bottom:20px;">
        <h3 style="margin:0 0 8px;color:#333;">English Translation</h3>
        <div style="color:#666;font-size:14px">OCR-extracted text</div>
      </div>
      <div id="ocr-translation-content" style="line-height:1.6;max-height:50vh;overflow-y:auto;padding:0 10px;color:#333;">
        Loading translation...
      </div>
      <div style="text-align:right;margin-top:15px;font-size:0.9em;color:#999;">
        Click outside to close
      </div>
    `;
    return el;
  }

  // Find target element (handles iframes)
  function findTargetElement() {
    // Check main document
    let element = document.getElementById(CONFIG.targetElementId);
    
    if (element) return element;
    
    // Check iframes
    const iframes = document.querySelectorAll('iframe');
    for (const iframe of iframes) {
      try {
        if (iframe.contentDocument) {
          const iframeElement = iframe.contentDocument.getElementById(CONFIG.targetElementId);
          if (iframeElement) {
            console.log('[OCR-Translator] Found element in iframe');
            return iframeElement;
          }
        }
      } catch (e) {
        console.warn('[OCR-Translator] Cannot access iframe content');
      }
    }
    
    return null;
  }

  // Update status display
  function updateStatus(statusEl, message, color = '#3498db') {
    statusEl.textContent = message;
    statusEl.style.backgroundColor = color;
  }

  // Show popup with translation
  function showTranslation(statusEl, popupEl, translation) {
    const contentEl = popupEl.querySelector('#ocr-translation-content');
    if (contentEl) {
      contentEl.innerHTML = translation.replace(/\n/g, '<br>');
    }
    
    updateStatus(statusEl, '✅ Translation complete! Click to view', '#27ae60');
    
    // Make popup visible and interactive
    popupEl.style.opacity = '1';
    popupEl.style.pointerEvents = 'auto';
    
    // Hide status when popup shows
    statusEl.style.display = 'none';
  }

  // Close popup
  function closePopup(statusEl, popupEl) {
    popupEl.style.opacity = '0';
    popupEl.style.pointerEvents = 'none';
    statusEl.style.display = 'block';
  }

  // Main translation function
  async function translateText(ocrText) {
    try {
      const response = await fetch(CONFIG.apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ocr_text: ocrText }),
        timeout: CONFIG.timeout
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      
      if (data.error) {
        throw new Error(data.error);
      }
      
      return data.translation || data.response || 'Translation unavailable';
    } catch (error) {
      console.error('[OCR-Translator] API Error:', error);
      throw error;
    }
  }

  // Main execution
  function init() {
    console.log('[OCR-Translator] Initializing...');
    
    // Create UI elements
    const statusElement = createStatusElement();
    const popupElement = createPopupElement();
    
    // Add to DOM
    document.body.appendChild(statusElement);
    document.body.appendChild(popupElement);
    
    // Find OCR text
    const targetElement = findTargetElement();
    
    if (!targetElement) {
      updateStatus(statusElement, '❌ OCR text not found', '#e74c3c');
      console.error('[OCR-Translator] Target element not found');
      return;
    }
    
    const ocrText = targetElement.innerText.trim();
    if (!ocrText) {
      updateStatus(statusElement, '⚠️ No text content found', '#f39c12');
      console.warn('[OCR-Translator] Empty text content');
      return;
    }
    
    updateStatus(statusElement, '🔄 Contacting translation service...', '#9b59b6');
    
    // Set up event listeners
    statusElement.addEventListener('click', () => {
      if (popupElement.style.opacity === '1') {
        closePopup(statusElement, popupElement);
      } else if (popupElement.querySelector('#ocr-translation-content').textContent !== 'Loading translation...') {
        showTranslation(statusElement, popupElement, popupElement.querySelector('#ocr-translation-content').textContent);
      }
    });
    
    popupElement.addEventListener('click', (e) => {
      if (e.target === popupElement) {
        closePopup(statusElement, popupElement);
      }
    });
    
    document.addEventListener('click', (e) => {
      if (!statusElement.contains(e.target) && !popupElement.contains(e.target)) {
        closePopup(statusElement, popupElement);
      }
    });
    
    // Perform translation
    translateText(ocrText)
      .then(translation => {
        showTranslation(statusElement, popupElement, translation);
      })
      .catch(error => {
        updateStatus(statusElement, `❌ Error: ${error.message}`, '#e74c3c');
        popupElement.querySelector('#ocr-translation-content').textContent = `Translation failed: ${error.message}`;
      });
  }

  // Run when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
