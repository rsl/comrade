// Visual-viewport debug readout, loaded only under ?vvdebug=1. Shows the
// live numbers the shell's sizing depends on — visualViewport height and
// offsetTop, innerHeight, window scroll, and the computed shell height —
// so a device without devtools can report what the viewport did when the
// keyboard (or its accessory bar) moved. Numbers, not pixels.

(function () {
  const el = document.createElement("pre")
  el.id = "vvdebug"
  el.className = "c-vvdebug"
  el.setAttribute("aria-hidden", "true")
  document.body.appendChild(el)

  const render = (cause) => {
    const vv = window.visualViewport
    const shell = getComputedStyle(document.documentElement).getPropertyValue("--shell-height").trim()
    el.textContent = [
      `${cause} @${Date.now() % 100000}`,
      `vv.height   ${vv ? vv.height : "n/a"}`,
      `vv.offsetTop ${vv ? vv.offsetTop : "n/a"}`,
      `vv.pageTop  ${vv ? vv.pageTop : "n/a"}`,
      `innerHeight ${window.innerHeight}`,
      `scrollY     ${window.scrollY}`,
      `--shell-height ${shell}`,
    ].join("\n")
  }

  window.addEventListener("resize", () => render("resize"))
  if (window.visualViewport) {
    window.visualViewport.addEventListener("resize", () => render("vv resize"))
    window.visualViewport.addEventListener("scroll", () => render("vv scroll"))
  }
  window.addEventListener("scroll", () => render("win scroll"))
  document.addEventListener("focusin", () => {
    render("focusin")
    ;[100, 300, 600, 1000, 2000].forEach((delay) => setTimeout(() => render(`t+${delay}`), delay))
  })
  render("load")
})()
