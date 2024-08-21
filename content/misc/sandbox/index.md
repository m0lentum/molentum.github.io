+++
path = "sandbox"
template = "starframe-app.html"
title = "sandbox"
[extra]
app_path = "builds/sandbox/sandbox.js"
+++

Testing sandbox for [Starframe](https://github.com/m0lentum/starframe/),
now running in the browser thanks to [wgpu](https://github.com/gfx-rs/wgpu)!
You can grab things with the mouse to toss them around,
and in scenes where a player exists (a little mint-colored capsule)
you can move it with the arrow keys, jump with shift and shoot bullets with Z.
The rest of the controls are on screen using [egui](https://github.com/emilk/egui/).

Requires an experimental browser with WebGPU enabled
(`dom.webgpu.enabled` in Firefox).
Tested on Linux with Firefox Nightly 103.0a1 and Vulkan.
