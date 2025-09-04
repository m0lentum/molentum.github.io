+++
title = "Dexterior showcase: elastic wave"
template = "page_wgpu.html"
+++

An early prototype of a heat transport simulation
using an elastic wave model
(this has been further developed in <https://codeberg.org/molentum/phononic>).
A wave pulse is sent from the bottom boundary
through a material with piecewise constant parameters
and absorbed by the other boundaries.

Press R to restart the simulation
or W to switch the visualization from pressure to shear potential.

<script type="module">
    import init from "/notes/dexterior/elastic_2d.js";
    window.addEventListener("load", () => {
        init();
    });
</script>
