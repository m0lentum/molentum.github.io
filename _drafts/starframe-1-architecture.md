---
layout: post
title: "Starframe dev blog: Architecture"
#date:   2018-09-23 16:10:00 +0300
categories: engine
---

Most of the past two years of [Starframe] development have gone into implementing and reimplementing
the basic structures that describe a game and its content.
This post is about what I've tried so far and what those attempts taught me.

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

In general, though, the tools provided by an engine tend to be fairly independent from each other, especially if they're meant to be used in multiple games.
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

Before we get to the things I've been building, let's establish a starting point that we can compare to.
I've made a thing that's considerably complicated, and there are reasons why I want to have that thing,
but you can boil the same concept down to a very simple thing indeed.

We already have a type system, why not just use it to represent our objects?

```rust
struct Goblin {
  position: Vector2<f32>,
  attack_power: u32,
  health: u32,
  catchphrase: String,
  has_a_gun: bool,
}
```

In languages with support for sum types (a.k.a. tagged unions or fat enums) you can even build a single all-encompassing object type that can be queried
for components in a similar fashion to the more complicated systems we're about to discuss.

```rust
enum GameObject {
  Player(Player),
  Goblin(Goblin),
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
  pub fn get_sprite(&self) -> Option<&Sprite> {
    match self {
      // ...
    }
  }
}
```

There's a good chance something like this is already flexible enough to support your entire game without much trouble.
Check out [this post by Mason Remaley][way-of-rhea] for a more detailed description of such a system, as implemented in the game Way of Rhea.
This approach is dead simple and has some genuine advantages over other systems (simplicity in itself is a big one!),
but also some notable problems, both of which will be touched upon later.

What would this object model look like as a graph? This is a strange question at this point but bear with me, it'll make more sense later.
The smallest unit we can operate on in this model is a whole object.
We can look at different parts inside them to produce different behaviors, but we can't pull those parts apart and put them in different places.
Therefore, the 'atomic' unit of this world and the node type of this graph would be the whole object.
Representing different behaviors with different colors, this graph would look something like this:

TODO: not sure if this is good here, maybe only discuss it in the actual graph talk

![graph_1](/assets/graphs/structs.png)

The nodes are entirely self-contained and don't need any edges to connect them to anything.

# Attempt 1: ECS

Entity-Component-System, or ECS for short, seems (to my limited perspective)
to be a de-facto standard in most of the game dev world at the moment.
There are various Rust crates implementing it, such as [specs], [legion], and [hecs].
At the time I started, `specs` was the big ECS crate everyone was using, I saw [this popular talk by Catherine West][west-talk],
and naturally this led me to look into the `specs` source as my primary reference.

**So what is it?**

ECS takes the struct from our initial example, gives it an identifier, rips all its fields out and distributes them
into what are essentially database tables where they can be looked up with the identifier.
The identifier is called the Entity, and the fields are Components.
Game logic can select entities that have a certain set of components and ignore the rest.
Functions that do this are called Systems.

This improves performance by grouping data in memory more efficiently than those big everything-structs from earlier.
To put it briefly, memory lookups are extremely slow, and processors do best when they get to go from one memory location
to the one right next to it and repeat. This optimization is accomplished using _caches_ of very fast memory close to the processor.
The big structs have a bunch of irrelevant things in them that take up space in the cache,
whereas ECS database tables only have one type of thing each, so we can pick and choose what to pull into the cache when running Systems.

The other benefits of this pattern stem from its nature as a dynamic type system, as do many of its flaws.

<!-- links -->

[starframe]: https://github.com/MoleTrooper/starframe
[amethyst]: https://amethyst.rs/
[way-of-rhea]: https://www.anthropicstudios.com/2019/06/05/entity-systems/
[specs]: https://github.com/amethyst/specs
[legion]: https://github.com/TomGillen/legion
[hecs]: https://github.com/Ralith/hecs
[west-talk]: https://www.youtube.com/watch?v=aKLntZcp27M
