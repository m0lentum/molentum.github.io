---
layout: post
title: "Building a Game Engine: Architecture"
#date:   2018-09-23 16:10:00 +0300
categories: engine
---

Most of the past two years of [Starframe] development have gone into implementing and reimplementing
the basic structures that describe a game and its content.
This is a story about the things I've tried and learned so far.

<!--excerpt-->

I'll start with some rambling about the nature of game engines and game objects
before diving into the Entity-Component-System architecture and my efforts at implementing it.
Finally, I'll cover my latest approach, which represents objects as a general graph structure instead.

Note: many details of each implementation are specific to the Rust language, as are all the code examples,
but most of the content here should be fairly language-agnostic.

# Intro: Engines and objects

It's difficult to define exactly what a game engine is. The best-known ones used in commercial games,
like Unity, Unreal and Godot, are huge suites of reusable tools for every aspect of game production.
Everything from physics libraries to graphical editing tools is considered part of the package that is the engine.
On the other hand, many games have tools and background libraries built specifically for them.
In these cases the separation between "engine" and "gameplay" code can get very blurry.

In general, though, the tools provided by an engine tend to be fairly independent from each other, especially if they're meant to be reusable in multiple games.
A physics library doesn't need to know anything about graphics.
A level editor doesn't need to know anything about physics, nor does an input manager or a sound system, and so on.
As such, it doesn't make much sense to talk about the overall architecture of an engine – most of these pieces don't need to fit together at all.
However, there is one point where almost everything is connected, and that is the **game object**, also known as the **entity**.
I'll speak about game objects here to separate this more general concept from the entities found in the Entity-Component-System architecture.

Game objects are another thing whose definition is quite hard to nail down, but I'm sure you have an intuition for it.
They're _things_ that exist in a game world and probably interact with other _things_ therein in some way.
To interact, or indeed have any purpose at all, they need to have some data associated with them.
These associations can be implemented in many ways, and any tool or system
that touches game objects (i.e. most of them) needs to be able to follow them.
Well, either that or you need additional compatibility code converting things to whatever formats each system wants,
which is the only option if you want your systems to be usable outside of the engine they were made for.
A large part of the [Amethyst] game engine's job, for instance, is to glue various libraries
(many of them also developed by the Amethyst team, but intentionally made independent of the engine)
into their entity system of choice.

Anyway, this is where architecture suddenly becomes crucial in a fully integrated engine like mine –
almost every higher-level system depends on how you compose game objects.
This is why I've spent so much time thinking about this and doing it over and over.
I don't want to build too many systems on top of my object model until I'm happy with it,
because every time I redo it I have to update large parts of everything else.

# Building up

Before we get too deep into the mud here, I want any beginners reading this to know that game objects don't have to be complicated
and unless you're more interested in this stuff than actually making games (like I am, apparently),
implementing complicated things yourself is going to be a waste of time. So let's take a moment to start simple.

In small projects you can probably get away with using simple structs as objects.
```rust
struct Goblin {
  position: Vector2<f32>,
  attack_power: u32,
  health: u32,
  catchphrase: String,
  has_a_gun: bool,
}
```
In languages with support for sum types (a.k.a tagged unions or fat enums) you can even build a single type that can be queried
for components in a similar fashion to the more complicated systems we're about to discuss.
```rust
enum GameObject {
  Player(Player),
  Enemy(Enemy),
  Projectile(Projectile),
  Decoration(Decoration),
  // ...
}
impl GameObject {
  pub fn get_rigid_body(&self) -> Option<&RigidBody> {
    match self {
      GameObject::Projectile(p) => Some(p.body),
      GameObject::Decoration(_) => None,
      // ... you get the idea
    }
  }
  get_sprite(&self) -> Option<&Sprite> { /* ... */ }
}
```
There's a good chance something like this is already flexible enough to support your entire game without much trouble.
Check out [this post by Mason Remaley][way-of-rhea] for a more detailed description of such a system.
This approach is dead simple and has some genuine advantages over other systems,
but also some notable problems, both of which I'll discuss later.

## Attempt 1: ECS

arst

<!-- links -->

[starframe]: https://github.com/MoleTrooper/starframe
[amethyst]: https://amethyst.rs/
[specs]: https://github.com/amethyst/specs
[way-of-rhea]: https://www.anthropicstudios.com/2019/06/05/entity-systems/
