---
layout: post
title:  "Building a Game Engine, Part 1: Intro to ECS"
#date:   2018-09-23 16:10:00 +0300
categories: engine
---

Entity-Component-System is a flexible and scalable architecture for runtime data composition.
It's well suited for describing objects in a video game due to good performance
and convenient authoring of new object types.
This post is a brief intro to the whys and hows of the subject based on my learnings implementing it in [MoleEngine].
<!--excerpt-->

Before we begin, do keep in mind I am a newbie documenting myself learning this stuff as I go,
so everything I write should be subject to at least a tiny grain of salt.
Code examples will be in [Rust], but the theory applies to any language.

Let's start with what game objects are and how we might arrive at the idea of ECS.

# Objects
It's intuitive to think about everything that interacts in a game as objects because in many ways, that's exactly what they are.
Boxes, walls, monsters, bullets, and players are all distinct entities encapsulating their own distinct behaviors
(note the word *entity* there).

The easy way to model this in an object-oriented language would be to make every kind of game object its own class.
This will work, probably even quite well if you follow good object-oriented design principles -
most importantly, favor composition over inheritance whenever possible.
In other words, instead of a massive inheritance tree like
`Object -> TransformableObject -> DrawableObject -> AnimatedObject -> PhysicsObject -> Character -> Player`
which will get out of hand pretty much immediately,
slice your data into small reusable pieces to build your game objects out of.
We might call these pieces *components*.
The previous Player example might then look something like this:
```rust
struct Player {
    tr: Transform,
    anim: Animation,
    rb: RigidBody,
    coll: Collider,
    kb: KeyboardControls,
}
```
* <small>Note: in Rust there is no data inheritance, so we couldn't do the first approach even if we wanted to.</small>

This is *type-level* composition - we're defining a type for every distinct set of components.
[This blog post](oop-dead) provides another, more fleshed out perspective on the matter.

What if we zoom in a little from this object-focused view and start thinking about their components individually?

# Thinking about data
Let's take a quick digression into the world of *data-oriented design*.
This means that instead of logic and control flow, the basis of our thinking is the flow and placement of data.
That is, where to get data, how to transform it, and where to put the results.
[Here](data-ori) is a short blog post explaining the idea in a little more depth.

An important technical detail in data-oriented design is that loading things from memory is very slow.
Processors use [caches] to mitigate this by keeping some data close to the core
where it can be accessed for a vastly lower time cost.
Caches work best with data that is laid out in contiguous blocks, so
in order to make use of the cache as much as possible, data that is accessed together should be together in memory.

Alright, with this information, let's get back to thinking about game objects. What are the operations we perform on them?
We have many different, largely independent update loops going on - physics, AI, controls, rendering, and so on.
You may notice that all of these loops only use a certain subset of an object's components:
for instance, rigid body physics needs a transform, body and collider, and rendering needs a mesh and a transform.
In the object-oriented design, all components of an object are together in memory.
This means that in each loop, as we iterate over objects, we're accessing some data we don't use at all.

Our update loops could make better use of the processor cache if every component of one type was together in one place.
In a world like this the loops would get to zip through some nice contiguous memory where everything is relevant to their task.
This is one of the problems addressed by ECS.

# Entity-Component-System
As mentioned earlier, ECS is really just a fancy interface for composition,
a different data layout and usage pattern for the same concept.
The difference is that we decouple our data from the objects that own it and group it by type instead.
As a result, we now need a way to identify which data belongs to which object.



[oop-dead]: https://www.gamedev.net/blogs/entry/2265481-oop-is-dead-long-live-oop/
[data-ori]: http://www.codersnotes.com/notes/explaining-data-oriented-design/
[caches]: https://arstechnica.com/gadgets/2002/07/caching/
[Specs]: https://github.com/slide-rs/specs
[MoleEngine]: https://moletrooper.github.io/blog/2018/09/moleengine-part-0-introduction/
[Rust]: https://www.rust-lang.org/
