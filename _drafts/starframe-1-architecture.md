---
layout: post
title: "Starframe dev blog: Architecture"
#date:   2018-09-23 16:10:00 +0300
categories: engine
---

I've spent a large portion of the past two years writing and rewriting
the basic structures that describe a game and its content in [Starframe].
This post is about what I've tried so far and what those attempts taught me.

<!--excerpt-->

I'll start with some rambling about the nature of game engines and game objects
before diving into the Entity-Component-System architecture and my efforts at implementing it.
Finally, I'll cover my latest approach, which represents objects as a more general graph.

Note: many details here are specific to the Rust language, as are all the code examples,
but most of the information can be applied to any environment.

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

We already have a type system provided by the language, why not just use it to represent our objects?

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
  pub fn get_position(&self) -> Option<&Vector2<f32>> { /* ... */ }
  pub fn get_sprite(&self) -> Option<&Sprite> { /* ... */ }
}
```

<small>(In real life I would probably make a parameterized trait like `GetComponent<T>` and use it to make systems generic,
but that's not relevant to the example)
</small>

There's a good chance something like this is already flexible enough to support your entire game without much trouble.
Check out [this post by Mason Remaley][way-of-rhea] for a more detailed description of such a system, as implemented in the game Way of Rhea.
This approach is dead simple and has some genuine advantages over other systems (simplicity in itself is a big one!),
but also some notable problems, both of which will be touched upon later.

# Attempt 1: Generic ECS

Entity-Component-System, or ECS for short, seems (to my limited perspective)
to be a de-facto standard in most of the game dev world at the moment.
There are various Rust crates implementing it, such as [specs], [legion], and [hecs].
At the time I started, `specs` was the big ECS crate everyone was using, I saw [this popular talk by Catherine West][west-talk],
and was naturally led to look into the `specs` source as my primary reference.

**So what is it?**

ECS takes the struct from our initial example, gives it an identifier, rips all its fields out and distributes them
into what are essentially database tables where they can be looked up with the identifier.
The identifier is called the Entity, and the fields are Components.
Game logic can select entities that have a certain set of components and ignore the rest.
Functions that do this are called Systems.

This improves performance by grouping data in memory more efficiently than those big everything-structs from earlier.
To put it briefly, memory lookups are extremely slow, and processors do best when they get to go from one memory location
to the one right next to it and repeat. This optimization is accomplished using _caches_ of very fast memory close to the processor.
Most things in the big structs are irrelevant to most operations, but they still take up space in the cache all the time.
On the other hand, ECS "tables" only have one type of thing each, so we can pick and choose what to pull into the cache
by completely ignoring the tables we don't need.
This is quite important in rigid-body physics, where the number of objects tends to be very large and the only parts of them that matter
are bodies, colliders, positions, orientations, and velocities.

The other benefits of this pattern stem from its nature as a dynamic type system, as do many of its flaws.
When using structs we were defining types in Rust's static type system,
which lets us use the compiler to verify that our objects are well-formed,
but requires a programmer to write every object type the game supports.
On the other hand, in ECS, all our types are defined at runtime by inserting components into tables.
No programming is needed to create new types of object or to wire them into the game logic,
but we get no static analysis to help catch errors.
An interesting consequence is that an object can change its type at runtime —
a classic example is an RPG character getting status effects added and removed dynamically.

**My implementation**

At this point I was still wrapping my head around what an ECS even is, and I started by more or less just copying what `specs` does.
I had a top-level manager called `Space` that gave out entity IDs, kept track of alive entities with a `BitSet` from the `hibitset` crate,
and stored all the component tables in an `AnyMap` (a container that stores pointers to any given type indexed by the type,
essentially a `HashMap<TypeId, Box<Any>>`) from the `anymap` crate.
I made different types of `Storage` for my component tables that would be selected by the user based on how common the component was —
`VecStorage` when almost every object has it, `DenseVecStorage` when it's common but not ubiquitous, `HashMapStorage` when it's rare,
and `NullStorage` when it's a zero-sized tag component.
Object IDs contained a generation index that allowed them to be deleted and overwritten with new things
in a way that invalidated any old components still hanging around.

Where things diverge a little from `specs` is in the queries that Systems use to select their desired component sets.
This was in some part because I didn't really care for the tuple-based interface in `specs`, but mostly because I didn't fully understand how it worked.
I wrote a rather long procedural macro that generated query implementations for structs of references (plus some special fields with special annotations)
like this one from my physics module:

```rust
#[derive(ComponentQuery)]
pub struct RigidBodyQuery<'a> {
    #[id]
    id: ecs::IdType,
    tr: &'a mut util::Transform,
    body: &'a mut phys::RigidBody,
}
```

Running this query through a `Space` would return a slice `&mut [RigidBodyQuery]` where each item in the slice represented one entity.
I still think this is a neat interface, but the macro ended up so large it was quite hard to maintain.

Additional concepts I added from outside the realm of `specs` were `Recipe`s and `Pool`s.

A `Recipe` is very similar to the idea of a _prefab_ in most game engines.
It's a simple struct that knows how to turn itself into an entity, and with some macros around it,
also knows how to read itself from a file with `serde`.
[Here][ecs-impl-1-recipes]'s what their definitions looked like.
If you're wondering about the `recipes!` macro (which I don't use anymore because it made people wonder),
it simply creates an enum with the given types as its variants (plus a bit more magic that was later deemed unnecessary).
With these I was able to read scenes from RON files like this:

```ron
[
    Player ((
        transform: ( position: (0, 0) ),
    )),
    DynamicBlock ((
        width: 1, height: 0.8, transform: ( position: (1, -1.5) ),
    )),
    StaticBlock ((
        width: 8, height: 0.2, transform: ( position: (0, -3) ),
    )),
]
```

I still use more or less the same recipe system today.
It's a concise but human-readable way to express scenes and helps a lot when a text file is the only level editor I have.

A `Pool` is an optimization for types of objects that are frequently spawned and deleted, such as bullets or other projectiles in an action game.
What it does is preallocate and take control of entity slots so that entities it manages are always placed in those slots.
The benefit of this is twofold — firstly, it prevents memory fragmentation from objects getting deleted and respawned far away in memory.
Secondly, it lets you limit the number of instances of an object type that can exist at one time,
preventing them from taking up more memory than your budget allows.
This was especially important in this implementation because my `Space`s had a maximum capacity and weren't growable at runtime.

The last revision of source code with this implementation can be found [here][ecs-impl-1].

# Attempt 2: Distributed ECS

arst

# Attempt 3: Graph

oien

Just for fun, let's look at what the previous architectures would look like if interpreted as a graph.

First, the big structs. The smallest unit we can operate on in this model is a whole object.
We can look at different parts inside them to produce different behaviors, but we can't pull those parts apart and put them in different places.
Therefore, the 'atomic' unit of this world and the node type of this graph would be the whole object.
Representing different behaviors with different colors, this graph would look something like this:

(graph here)

The nodes are entirely self-contained and don't need any edges to connect them to anything.

<!-- links -->

[starframe]: https://github.com/MoleTrooper/starframe
[amethyst]: https://amethyst.rs/
[way-of-rhea]: https://www.anthropicstudios.com/2019/06/05/entity-systems/
[specs]: https://github.com/amethyst/specs
[legion]: https://github.com/TomGillen/legion
[hecs]: https://github.com/Ralith/hecs
[west-talk]: https://www.youtube.com/watch?v=aKLntZcp27M
[ecs-impl-1]: https://github.com/MoleTrooper/starframe/tree/cec0dbec5bce8612ffb9dd82441e30eb9233ef60/
[ecs-impl-1-recipes]: https://github.com/MoleTrooper/starframe/blob/cec0dbec5bce8612ffb9dd82441e30eb9233ef60/examples/testgame/recipes.rs
