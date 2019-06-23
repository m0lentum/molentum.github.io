---
layout: post
title:  "MoleEngine, Part 1: ECS"
#date:   2018-09-23 16:10:00 +0300
categories: engine
---

Entity-Component-System is a popular word in game development these days. It's a highly flexible and scalable,
data-oriented architecture that handles game objects. In this post I will attempt to explain the architecture in detail and
outline how I implemented it in MoleEngine.

Before we begin, do keep in mind I am learning this stuff as I go and documenting said learnings here,
so everything I write should be subject to at least a tiny grain of salt.

# Objects
It's very intuitive to think about everything that interacts in a game as objects because in many ways, that's exactly what they are.
The easy way to model this in an object-oriented language would be to make every kind of game object its own class.
This will work. In fact, it can be made to work quite well by following good object-oriented design principles - most importantly,
favor composition over inheritance whenever possible. [This blog post](oop-dead) goes into a lot of good detail on this.
In fact, all ECS really is is a fancy interface for composition.
So I'm not here to tout ECS as the best or "correct" way to design your game objects. However, it does have some nice advantages over
the object-oriented approach. Plus, it's trendy as heck.

# Thinking about data
ECS is often called a data-oriented design pattern. This means that instead of logic and control flow, the basis
of our thinking is the flow and placement of data. That is, where to get data, how to transform it, and where to put the results.
[Here](data-ori) is a short blog post explaining the idea in a little more depth.

An important thing to understand here is that 1. loading things from memory is very slow and 2. processors use [caches](caches)
to subvert going all the way to RAM for everything. Caches work best with data that is laid out in sequential order, so
in order to make use of the cache as much as possible data that is accessed together should be together in memory.

So data-oriented thinking leads us to consider when data is accessed and try to clump related data together.
What we find is that most of the time in our update loops we are only handling a few components of each object.
This is one weakness of the object-oriented approach - it stores every component of an object together in memory.
This means when our physics update loop is fiddling with an object's rigid body, collider and transform,
we're jumping over its graphics, AI, sounds and whatever else it might have.
What we would like instead is for every component of one type in the world to be tightly together.

# ECS





[oop-dead]: https://www.gamedev.net/blogs/entry/2265481-oop-is-dead-long-live-oop/
[data-ori]: http://www.codersnotes.com/notes/explaining-data-oriented-design/
[caches]: https://arstechnica.com/gadgets/2002/07/caching/
