+++
title = "Dexterior showcase: acoustic scatterer"
template = "page_wgpu.html"
+++

Incident plane wave scattered by a sound-soft obstacle,
modelled by a Dirichlet boundary condition on the scatterer geometry
and an absorbing boundary on the outer edge.

<script type="module">
    import init from "/notes/dexterior/scatterer_2d.js";
    window.addEventListener("load", () => {
        init();
    });
</script>
