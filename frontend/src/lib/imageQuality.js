/**
 * Tarayıcıda basit foto kalite ipuçları: ortalama parlaklık + basit keskinlik vekili.
 * Tıbbi ölçüm değil; kullanıcıyı daha tutarlı selfie için yönlendirir.
 */
export async function analyzeSkinPhotoQuality(file) {
  if (!file || !file.type?.startsWith("image/")) {
    return {
      meanLuma: null,
      variance: null,
      sharpnessApprox: null,
      tooDark: false,
      tooBlurry: false,
    };
  }

  try {
    const bitmap = await createImageBitmap(file);
    const maxSide = 160;
    const scale = Math.min(maxSide / bitmap.width, maxSide / bitmap.height, 1);
    const w = Math.max(8, Math.round(bitmap.width * scale));
    const h = Math.max(8, Math.round(bitmap.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    if (!ctx) {
      bitmap.close?.();
      return { meanLuma: null, variance: null, sharpnessApprox: null, tooDark: false, tooBlurry: false };
    }
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close?.();

    const imgData = ctx.getImageData(0, 0, w, h);
    const d = imgData.data;
    let sum = 0;
    let sumSq = 0;
    const n = (d.length / 4) | 0;
    const gray = new Float32Array(n);
    let gi = 0;
    for (let i = 0; i < d.length; i += 4) {
      const y = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      gray[gi++] = y;
      sum += y;
      sumSq += y * y;
    }
    const mean = sum / n;
    const variance = Math.max(0, sumSq / n - mean * mean);

    // Laplacian benzeri: komşu farklarının ortalama mutlak değeri (küçük = bulanık)
    let lapSum = 0;
    let lapCount = 0;
    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const idx = y * w + x;
        const c = gray[idx];
        const nbr = (gray[idx - 1] + gray[idx + 1] + gray[idx - w] + gray[idx + w]) / 4;
        lapSum += Math.abs(c - nbr);
        lapCount++;
      }
    }
    const sharpnessApprox = lapCount ? lapSum / lapCount : 0;

    const meanLuma = mean / 255;
    const tooDark = mean < 42;
    const tooBlurry = sharpnessApprox < 2.2 && variance < 180;

    return {
      meanLuma: Math.round(meanLuma * 1000) / 1000,
      variance: Math.round(variance * 10) / 10,
      sharpnessApprox: Math.round(sharpnessApprox * 100) / 100,
      tooDark,
      tooBlurry,
    };
  } catch {
    return {
      meanLuma: null,
      variance: null,
      sharpnessApprox: null,
      tooDark: false,
      tooBlurry: false,
    };
  }
}
