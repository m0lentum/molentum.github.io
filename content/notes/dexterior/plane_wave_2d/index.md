+++
title = "Dexterior showcase: acoustic plane wave"
template = "page_wgpu.html"
+++

Plane wave applied on the edges as a Dirichlet boundary condition
and simulated inside the domain.
Useful for checking the accuracy of the method
against the known analytic solution.

<script type="module">
    import init from "/notes/dexterior/plane_wave_2d.js";
    window.addEventListener("load", () => {
        init();
    });
</script>
