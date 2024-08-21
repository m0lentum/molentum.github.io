+++
path = "dexterior"
title = "Dexterior showcase"
+++

An experimental collection of [dexterior](https://github.com/m0lentum/dexterior)
simulations built for WebGL. More to come later, probably.

<!-- more -->

# Acoustics

## Membrane

<script type="module">
    // for some reason the full path is needed here
    import init from "/dexterior/membrane.js";
    window.addEventListener("load", () => {
        init();
    });
</script>

<div id="membrane-canvas"></div>

## Plane wave

<script type="module">
    import init from "/dexterior/plane_wave_2d.js";
    window.addEventListener("load", () => {
        init();
    });
</script>

<div class="dagamez0ne">
    <div id="plane-wave-canvas"></div>
</div>
