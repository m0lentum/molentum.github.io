---
layout: post
title:  "MoleEngine, Part 0: Introduction"
date:   2018-09-23 16:10:00 +0300
categories: engine
---

MoleEngine is an ambitious hobby project, still early on in development, aiming to create a general-purpose 2D
game engine suitable for rapid prototyping and game jams as well as more polished, hopefully commercial-quality products.
This blog is meant to document the development and ideas behind it in a fair bit of detail - mostly to organize and
revise my own thoughts, but with the hope that someone else might also find it interesting and/or helpful.
In this first post I will outline what exactly I am trying to accomplish and why I am doing it.

# But why?
I'm the kind of person whose first thought when seeing something cool is "how can I do this too?".
Probably the second coolest thing in the universe to me, right after computers, is movement and the mathematics therein.
It blows my mind that we can mathematically describe objects and the ways in which they interact.
It naturally follows that I would want to program movement. Another thing I love very much is video games,
especially platformers, which just so happens to be a perfect platform to put movement on.

Alright, so I want to do movement, but what's the best way to involve this type of math in my work?
I've tried many game development tools over the years. While using an existing engine is undeniably the most
efficient way to "just make games" and I would absolutely recommend Unity to anyone, I always have this
nagging desire to know more about the inner workings of what I'm using and modify it to look more like me.
So, enter MoleEngine - an entire game engine framework with as few dependencies as I can manage.
This is my attempt to make the tool I want to have, something that I know inside and
out and is fully in my control to modify when I feel like it. Something that is truly mine.
With great movement physics, of course. But more importantly than that end goal,
which may or may not ever be fully realized, I love learning about this stuff. It's just fun.

# So, what's in it?
I won't go into much detail in this post, but here's a quick list of things I want to do,
roughly in order of priority (and probability of actually happening). Links to corresponding
blog posts should appear in this list when/if they exist.
* flexible game object architecture (ECS)
  * serializable level data, file I/O
* collision detection and realistic rigid body physics interaction
  * optimized via spatial partitioning
* graphics via OpenGL
  * sprite-sheet animation
  * dynamic camera system
  * keyframe-based, smoothed motion animation
* GUI framework for menus and HUDs
* multithreading
* soft body / liquid physics
* graphical level editor


# The platform
Sure, I'm making this more or less from scratch, but I still need *some* tools.

When I first started working on this project in June 2017, I chose C++ as my language and SFML
to help with cross-platform compatibility and OS interaction. C++ is still the standard language
in the game industry due to its speed and this felt like a great time to learn it. It still does,
and I'm happy I did, but I eventually got fed up with how laborious it is to write.
I figured, since this is a fun hobby project above everything else, that I should look into easier to write alternatives.

Shortly after this decision I settled on Rust. It provides comparable performance to C++ with a far
more concise syntax and many neat modern features. Cross-platform compatibility is provided out of the
box and Cargo handles fetching my dependencies for me, which is wonderful as I develop a lot on both Windows
and Linux. No more messing with CMake, header files and .dlls.
I don't have enough experience to say whether or not I recommend it to others yet, but it is
certainly many steps above C++ in terms of user experience.

This is the road I'm currently on - rewriting what I had done with C++ in this new and exciting language 
and revisiting old decisions along the way. I'm still in the very early stages of this and 
plan to write up a blog post whenever I'm finished with a major feature (which won't be often - I'm working
and studying so time is scarce). I won't go into language specifics much, but all the code examples will obviously be in Rust.
If all this happens to interest you, or if you want to give me feedback, you may want to hit me up on [Twitter](https://twitter.com/moletrooper),
where I post various garbage but also occasional engine-related stuff and blog links.
Also, for those interested, the full source code to this project lives on  [GitHub](https://github.com/MoleTrooper/moleengine-redux).

# Coming up
The next post in this series will be all about architecture. We'll take a look at
[Entity-Component-System](https://en.wikipedia.org/wiki/Entity%E2%80%93component%E2%80%93system),
how I implemented it, and a quick glance at my game loop and state machine.
