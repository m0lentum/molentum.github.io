+++
title = "Dexterior showcase: membrane"
template = "page_wgpu.html"
+++

Vibrating membrane with fixed edges,
and my main place to test new graphics features.
Press L to see a newly added multi-tile layout mode.

<script type="module">
    // for some reason the full path is needed here
    import init from "/notes/dexterior/membrane.js";
    window.addEventListener("load", () => {
        init();
    });
</script>
