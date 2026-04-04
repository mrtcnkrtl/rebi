const puppeteer = require('puppeteer');

async function testFaceZoneInteraction() {
  console.log('🚀 Testing Face Zone Interaction...\n');
  
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 1600 });
  
  page.on('console', msg => {
    const text = msg.text();
    if (!text.includes('Download the React DevTools') && !text.includes('[vite]')) {
      console.log('Browser:', text);
    }
  });
  
  try {
    // Login
    console.log('📍 Logging in...');
    await page.goto('http://localhost:5173/auth', { waitUntil: 'networkidle0' });
    await new Promise(resolve => setTimeout(resolve, 1000));

    const e2eEmail = process.env.E2E_EMAIL;
    const e2ePassword = process.env.E2E_PASSWORD;
    if (!e2eEmail || !e2ePassword) {
      throw new Error(
        'Demo giriş kaldırıldı. Test için: E2E_EMAIL ve E2E_PASSWORD ortam değişkenlerini ayarla (gerçek test hesabı).'
      );
    }
    await page.type('input[type="email"]', e2eEmail);
    await page.type('input[type="password"]', e2ePassword);
    await Promise.all([
      page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 30000 }).catch(() => {}),
      page.click('button[type="submit"]'),
    ]);
    await new Promise(resolve => setTimeout(resolve, 2000));
    console.log('✅ Logged in\n');
    
    // Navigate to analyze
    console.log('📍 Navigating to analyze page...');
    await page.evaluate(() => {
      const links = Array.from(document.querySelectorAll('a, button'));
      const analyzeLink = links.find(el => 
        el.textContent.includes('Analiz') || 
        el.getAttribute('href')?.includes('analyze')
      );
      if (analyzeLink) analyzeLink.click();
    });
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Fill Step 1
    console.log('📝 Filling Step 1...');
    await page.evaluate(() => {
      const nameInput = document.querySelector('input[type="text"]');
      if (nameInput) nameInput.value = '';
    });
    await page.type('input[type="text"]', 'Test');
    
    await page.evaluate(() => {
      const ageInput = document.querySelector('input[type="number"]');
      if (ageInput) ageInput.value = '';
    });
    await page.type('input[type="number"]', '28');
    
    await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      const kadinButton = buttons.find(btn => btn.textContent.trim() === 'Kadın');
      if (kadinButton) kadinButton.click();
    });
    
    console.log('  ✓ Name: Test, Age: 28, Gender: Kadın\n');
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Click Devam Et
    console.log('📝 Going to Step 2...');
    await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      const devamButton = buttons.find(btn => btn.textContent.includes('Devam'));
      if (devamButton) devamButton.click();
    });
    await new Promise(resolve => setTimeout(resolve, 2500));
    
    // Take screenshot of Step 2
    await page.screenshot({ path: '/tmp/face-zones-1-step2.png', fullPage: true });
    console.log('📸 Screenshot: /tmp/face-zones-1-step2.png\n');
    
    // Analyze face zone buttons
    console.log('🔍 Analyzing face zone buttons...');
    const zoneAnalysis = await page.evaluate(() => {
      // Look for buttons with aria-label containing zone names
      const zoneButtons = Array.from(document.querySelectorAll('button[aria-label]')).filter(btn => {
        const label = btn.getAttribute('aria-label') || '';
        return label.includes('Alın') || label.includes('Yanak') || 
               label.includes('Burun') || label.includes('Çene') || 
               label.includes('Dudak') || label.includes('forehead') ||
               label.includes('cheek') || label.includes('chin');
      });
      
      // Also look for buttons with "+" text
      const plusButtons = Array.from(document.querySelectorAll('button')).filter(btn => 
        btn.textContent.trim() === '+' || btn.textContent.includes('+')
      );
      
      // Look for dashed circles or zone markers in SVG
      const svg = document.querySelector('svg');
      const circles = svg ? Array.from(svg.querySelectorAll('circle')).filter(c => {
        const stroke = c.getAttribute('stroke') || '';
        const dashArray = c.getAttribute('stroke-dasharray') || '';
        return dashArray.length > 0 || stroke.includes('dash');
      }) : [];
      
      return {
        zoneButtonCount: zoneButtons.length,
        zoneLabels: zoneButtons.map(btn => btn.getAttribute('aria-label')),
        plusButtonCount: plusButtons.length,
        dashedCircleCount: circles.length,
        allButtonsNearFace: Array.from(document.querySelectorAll('button')).map(btn => ({
          text: btn.textContent.trim().substring(0, 20),
          ariaLabel: btn.getAttribute('aria-label'),
          classes: btn.className.substring(0, 50)
        })).filter(b => b.text === '+' || b.ariaLabel)
      };
    });
    
    console.log('📊 Zone Button Analysis:');
    console.log('  - Zone buttons with aria-label:', zoneAnalysis.zoneButtonCount);
    console.log('  - Zone labels found:', zoneAnalysis.zoneLabels);
    console.log('  - Plus (+) buttons found:', zoneAnalysis.plusButtonCount);
    console.log('  - Dashed circles in SVG:', zoneAnalysis.dashedCircleCount);
    console.log('  - All clickable buttons near face:', zoneAnalysis.allButtonsNearFace.length);
    
    if (zoneAnalysis.allButtonsNearFace.length > 0) {
      console.log('\n📋 Button details:');
      zoneAnalysis.allButtonsNearFace.forEach((btn, i) => {
        console.log(`  ${i+1}. Text: "${btn.text}", Label: "${btn.ariaLabel}"`);
      });
    }
    
    // Try to click forehead zone button
    console.log('\n📝 Attempting to click forehead zone button (Alın)...');
    const foreheadClicked = await page.evaluate(() => {
      // Try aria-label first
      const alinButton = document.querySelector('button[aria-label*="Alın"]');
      if (alinButton) {
        alinButton.click();
        return { success: true, method: 'aria-label', text: alinButton.textContent.trim() };
      }
      
      // Try finding + buttons in the upper area (y position)
      const buttons = Array.from(document.querySelectorAll('button'));
      const plusButtons = buttons.filter(btn => btn.textContent.trim() === '+');
      
      if (plusButtons.length > 0) {
        // Sort by y position, click the topmost one
        const sorted = plusButtons.sort((a, b) => {
          const rectA = a.getBoundingClientRect();
          const rectB = b.getBoundingClientRect();
          return rectA.top - rectB.top;
        });
        sorted[0].click();
        return { success: true, method: 'position (top)', text: sorted[0].textContent.trim() };
      }
      
      return { success: false, method: 'none', text: '' };
    });
    
    console.log('  ✓ Forehead clicked:', foreheadClicked.success);
    console.log('  - Method:', foreheadClicked.method);
    console.log('  - Button text:', foreheadClicked.text);
    await new Promise(resolve => setTimeout(resolve, 1500));
    
    // Check for concern panel
    console.log('\n🔍 Checking for concern selection panel...');
    const panelCheck = await page.evaluate(() => {
      const allButtons = Array.from(document.querySelectorAll('button'));
      const concernButtons = allButtons.filter(btn => {
        const text = btn.textContent.toLowerCase();
        return text.includes('sivilce') || text.includes('kırışıklık') || 
               text.includes('kuruluk') || text.includes('leke') ||
               text.includes('kızarıklık');
      });
      
      return {
        panelVisible: concernButtons.length > 0,
        concernCount: concernButtons.length,
        concerns: concernButtons.map(btn => btn.textContent.trim())
      };
    });
    
    console.log('📊 Panel Status:');
    console.log('  - Panel visible:', panelCheck.panelVisible ? '✅ YES' : '❌ NO');
    console.log('  - Concern buttons found:', panelCheck.concernCount);
    if (panelCheck.concerns.length > 0) {
      console.log('  - Concerns:', panelCheck.concerns.join(', '));
    }
    
    // Take screenshot after clicking forehead
    await page.screenshot({ path: '/tmp/face-zones-2-forehead-panel.png', fullPage: true });
    console.log('\n📸 Screenshot: /tmp/face-zones-2-forehead-panel.png\n');
    
    // Click Sivilce if panel is visible
    if (panelCheck.panelVisible) {
      console.log('📝 Clicking "Sivilce" in concern panel...');
      const sivilceClicked = await page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button'));
        const sivilceButton = buttons.find(btn => 
          btn.textContent.toLowerCase().includes('sivilce')
        );
        if (sivilceButton) {
          sivilceButton.click();
          return true;
        }
        return false;
      });
      console.log('  ✓ Sivilce clicked:', sivilceClicked);
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Close panel
      console.log('📝 Closing panel...');
      await page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button'));
        const closeButton = buttons.find(btn => 
          btn.textContent.includes('✕') || 
          btn.textContent.includes('×') ||
          btn.getAttribute('aria-label')?.toLowerCase().includes('close') ||
          btn.getAttribute('aria-label')?.toLowerCase().includes('kapat')
        );
        if (closeButton) {
          closeButton.click();
        }
      });
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Take screenshot after selection
      await page.screenshot({ path: '/tmp/face-zones-3-after-forehead.png', fullPage: true });
      console.log('📸 Screenshot: /tmp/face-zones-3-after-forehead.png\n');
      
      // Click chin zone button
      console.log('📝 Clicking chin zone button (Çene)...');
      const chinClicked = await page.evaluate(() => {
        // Try aria-label
        const ceneButton = document.querySelector('button[aria-label*="Çene"]');
        if (ceneButton) {
          ceneButton.click();
          return { success: true, method: 'aria-label' };
        }
        
        // Try finding bottom + button
        const buttons = Array.from(document.querySelectorAll('button'));
        const plusButtons = buttons.filter(btn => btn.textContent.trim() === '+');
        
        if (plusButtons.length > 0) {
          // Sort by y position, click the bottommost one
          const sorted = plusButtons.sort((a, b) => {
            const rectA = a.getBoundingClientRect();
            const rectB = b.getBoundingClientRect();
            return rectB.top - rectA.top;
          });
          sorted[0].click();
          return { success: true, method: 'position (bottom)' };
        }
        
        return { success: false, method: 'none' };
      });
      
      console.log('  ✓ Chin clicked:', chinClicked.success);
      console.log('  - Method:', chinClicked.method);
      await new Promise(resolve => setTimeout(resolve, 1500));
      
      // Click Kuruluk
      console.log('📝 Clicking "Kuruluk" in concern panel...');
      const kurulukClicked = await page.evaluate(() => {
        const buttons = Array.from(document.querySelectorAll('button'));
        const kurulukButton = buttons.find(btn => 
          btn.textContent.toLowerCase().includes('kuruluk')
        );
        if (kurulukButton) {
          kurulukButton.click();
          return true;
        }
        return false;
      });
      console.log('  ✓ Kuruluk clicked:', kurulukClicked);
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      // Take final screenshot
      await page.screenshot({ path: '/tmp/face-zones-4-multiple-zones.png', fullPage: true });
      console.log('\n📸 Screenshot: /tmp/face-zones-4-multiple-zones.png\n');
      
      // Check for visual indicators
      console.log('🔍 Checking for visual zone indicators...');
      const visualCheck = await page.evaluate(() => {
        const svg = document.querySelector('svg');
        
        // Look for colored circles/dots (not dashed, filled)
        const coloredCircles = svg ? Array.from(svg.querySelectorAll('circle')).filter(c => {
          const fill = c.getAttribute('fill') || '';
          const stroke = c.getAttribute('stroke') || '';
          return (fill && fill !== 'none' && !fill.includes('transparent')) ||
                 (stroke && stroke !== 'none' && !stroke.includes('transparent'));
        }) : [];
        
        // Check page text for summary
        const bodyText = document.body.innerText;
        const hasAlinSivilce = bodyText.includes('Alın') && bodyText.includes('Sivilce');
        const hasCeneKuruluk = bodyText.includes('Çene') && bodyText.includes('Kuruluk');
        const hasSummary = bodyText.includes('·') && (hasAlinSivilce || hasCeneKuruluk);
        
        return {
          coloredCircleCount: coloredCircles.length,
          hasAlinSivilce,
          hasCeneKuruluk,
          hasSummary
        };
      });
      
      console.log('📊 Visual Indicators:');
      console.log('  - Colored circles/dots on face:', visualCheck.coloredCircleCount);
      console.log('  - "Alın · Sivilce" visible:', visualCheck.hasAlinSivilce ? '✅ YES' : '❌ NO');
      console.log('  - "Çene · Kuruluk" visible:', visualCheck.hasCeneKuruluk ? '✅ YES' : '❌ NO');
      console.log('  - Summary with · separator:', visualCheck.hasSummary ? '✅ YES' : '❌ NO');
    }
    
    console.log('\n✨ Test completed!');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    await page.screenshot({ path: '/tmp/face-zones-error.png', fullPage: true });
  } finally {
    await browser.close();
  }
}

testFaceZoneInteraction().catch(console.error);
