/**
 * Ürün görselini kutuya paketler, mühürler, sepete uçar.
 * prefers-reduced-motion ise kısa fade ile biter.
 */
export function flyProductToCart({ fromEl, toEl, imageUrl }) {
  if (!fromEl || !toEl || typeof document === "undefined") {
    return Promise.resolve();
  }
  const reduce =
    typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const from = fromEl.getBoundingClientRect();
  const to = toEl.getBoundingClientRect();
  if (!from.width || !to.width) return Promise.resolve();

  const ghost = document.createElement("div");
  ghost.className = "store-fly";
  ghost.setAttribute("aria-hidden", "true");
  ghost.style.left = `${from.left + from.width / 2}px`;
  ghost.style.top = `${from.top + from.height / 2}px`;
  ghost.style.width = `${Math.max(110, Math.min(150, from.width))}px`;
  ghost.style.height = `${Math.max(130, Math.min(180, from.height))}px`;

  const inner = document.createElement("div");
  inner.className = "store-fly__pack";
  if (imageUrl) {
    const img = document.createElement("img");
    img.src = imageUrl;
    img.alt = "";
    img.draggable = false;
    inner.appendChild(img);
  }
  const wrap = document.createElement("span");
  wrap.className = "store-fly__wrap";
  inner.appendChild(wrap);
  const lid = document.createElement("span");
  lid.className = "store-fly__lid";
  inner.appendChild(lid);
  const seal = document.createElement("span");
  seal.className = "store-fly__seal";
  seal.textContent = "Rebi";
  inner.appendChild(seal);
  ghost.appendChild(inner);
  document.body.appendChild(ghost);

  const dx = to.left + to.width / 2 - (from.left + from.width / 2);
  const dy = to.top + to.height / 2 - (from.top + from.height / 2);

  return new Promise((resolve) => {
    const cleanup = () => {
      ghost.remove();
      toEl.classList.remove("store-cart--catch");
      resolve();
    };

    if (reduce) {
      ghost.classList.add("store-fly--done");
      window.setTimeout(cleanup, 200);
      return;
    }

    requestAnimationFrame(() => {
      ghost.classList.add("store-fly--packing");
      window.setTimeout(() => {
        ghost.classList.add("store-fly--sealed");
        window.setTimeout(() => {
          ghost.style.setProperty("--fly-x", `${dx}px`);
          ghost.style.setProperty("--fly-y", `${dy}px`);
          ghost.classList.add("store-fly--flying");
          toEl.classList.add("store-cart--catch");
          window.setTimeout(cleanup, 900);
        }, 280);
      }, 520);
    });
  });
}
