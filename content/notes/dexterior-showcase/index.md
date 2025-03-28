+++
title = "Dexterior showcase"
slug = "dexterior"
updated = "2024-08-22"
+++

An experimental collection of [dexterior](https://github.com/m0lentum/dexterior)
simulations built for WebGL. More to come later, probably.

<!-- more -->

# Acoustics

## Membrane

<script type="module">
    // for some reason the full path is needed here
    import init from "/notes/dexterior/membrane.js";
    window.addEventListener("load", () => {
        init();
    });
</script>

<div class="dagamez0ne">
    <div id="membrane-canvas"></div>
</div>

## Plane wave

<script type="module">
    import init from "/notes/dexterior/plane_wave_2d.js";
    window.addEventListener("load", () => {
        init();
    });
</script>

<div class="dagamez0ne">
    <div id="plane-wave-canvas"></div>
</div>
