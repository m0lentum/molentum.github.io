+++
title = "Demodemonini"
date = 2024-02-28
[extra]
container_classes = "gallery-container"
main_image = "demodemons.gif"
main_image_alt = """
Three demonic creatures standing against a background of pixelated fire.
A small imp in a hoodie holding a keyboard,
a gorilla-shaped creature with mechanical arm and a CRT television for a head,
and a horned woman with RGB-lit bat wings wearing VR goggles and a Power Glove.
Everything is viewed through a distorted filter with a stripey CRT effect and chromatic aberration.
"""
+++

My submission for the graphic art compo at Instanssi 2024.
Lines drawn in ink on paper,
characters painted digitally with Krita,
and animated effects written in Rust with wgpu.
[Source code on GitHub](https://github.com/m0lentum/art)

<!-- more -->

## Interactive WebGL build

<script type="module">
    import init from "./demodemons.js";
    window.addEventListener("load", () => {
        init();
    });
</script>

<div class="dagamez0ne">
    <div id="wgpu-canvas" />
</div>

Keyboard controls:

- P: show/hide postprocessing
- C: show/hide characters
- F: show/hide fire
