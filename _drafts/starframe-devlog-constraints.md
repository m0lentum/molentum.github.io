---
layout: post
title: "Starframe Physics Devlog: Constraint Solvers"
date: 2021-01-09 00:11 +0300
categories: engine physics
usemathjax: true
---

The Starframe physics solver has gone through a few iterations recently as my
understanding of the problem and knowledge of available methods have grown. In
this combined devlog and tutorial I attempt to explain what constraints are and
detail a few game-engine-friendly ways of solving them. <!--excerpt-->
I'll try to make things accessible, but some familiarity with linear algebra and
calculus will be necessary.

I'll start with the mathematical definition of constraints and then go over
three solvers in the order I implemented them myself: Impulses with Projected
Gauss-Seidel, Iterated Impulses, and Extended Position-Based Dynamics.

## What is a constraint?

The essence of a physics engine (and the difficult part of building one) is not
making things move — it's making things _stop_ moving or change their
trajectory in ways that make sense. Things interact with each other.
A constraint, in a nutshell, is something that generates these interactions by
telling things where they are allowed to be relative to each other.
Unfortunately, a nutshell alone isn't something you can feed into a computer,
so I'll have to elaborate on this a bit. Let's look at a concrete example.

The most important constraint in a rigid body engine is the contact
constraint, which basically says "bodies aren't allowed to overlap".
Let's say the collision detection system that I won't
cover in this post notified us of a situation like this:

![Two boxes that overlap](/assets/avatar.png)

These bodies overlap, which is a violation of the contact constraint.
So we know the system is in an illegal state, but that boolean information
is not going to do us any favors in terms of finding a way out of this state.
We need some more information, specifically _how big the error is_
and _how it changes when the bodies move_.
In the case of this contact, we can get these things by measuring
the distance between points $p_1$ and $p_2$ along the surface normal $\hat{n}$:

$$
C_{contact}(p_1, p_2) = (p_2 - p_1) \cdot \hat{n}
$$

This gives us the amount of error, but not quite how it changes when the bodies
move. We get the final form of the constraint function by figuring out how the
contact points depend on the body poses:

$$
\displaylines{
p_1(x_1, \omega_1) = x_1 + \omega_1 r_{l1} \\
p_2(x_2, \omega_2) = x_2 + \omega_2 r_{l2} \\
C_{contact}(x_1, \omega_1, x_2, \omega_2) =
  (p_1(x_1, \omega_1) - p_2(x_2, \omega_2)) \cdot \hat{n}
}
$$

where $\omega_1$ and $\omega_2$ are the orientations of each body,
$r_{l1}$ and $r_{l2}$ are the contact points in each body's local space,
and multiplication between them denotes a rotation by the orientation.

One question remains: what's an acceptable value for this function
to return? Geometrically it measures the amount of overlap between the
objects, so anything zero or less means there's no overlap at all.
Thus, any state where

$$
C_{contact}(x_1, \omega_1, x_2, \omega_2) \leq 0
$$

is legal. This is the whole constraint — a function from world state to a value
and an acceptable range of values. That's what every kind of constraint boils
down to. The constraint solver's job is to try to find a state where every
constraint function returns an acceptable value.

<p class="sidenote">
Note:
Usually, the accepted range is either $C = 0$ (called an equality constraint),
or one of $C \leq 0$ and $C \geq 0$ (called inequality constraints).
Something other than zero on the right hand side is possible, but zeroes make
things a little more convenient for the solver.
</p>

Let's look at a couple more examples to make it easier to believe that all
constraints really look the same. Another simple case is a distance
constraint, which attaches two objects such that the distance between
selected points on them is always in some range.

<div class="code-like-img">
  <img
    alt="Two boxes attached with a distance constraint"
    src="/assets/TODO"
  />
</div>

To achieve this we can simply measure the difference between the actual
distance and the desired one $d$:

$$
C_{dist}(x_1, \omega_1, x_2, \omega_2) =
  \|p_2(x_2, \omega_2) - p_1(x_1, \omega_1)\| - d
$$

For the accepted range we have a choice: $C \leq 0$ will only pull the bodies
towards each other, $C \geq 0$ will only push them apart, and $C = 0$ will do
both.

The idea of a constraint is very flexible. Putting the right math in $C$ can
produce a variety of effects like friction, all sorts of joints, and with some
additional trickery even things like motors and springs. You can also remove
one body from constraint function's parameters and attach bodies to places in
the world instead. Like [Erin Catto][cattotwit] (of [Box2D] fame) said in [his
2014 GDC presentation][cat14], constraints are a place where physics
programmers get to apply creativity. Check out e.g. the aforementioned
presentation or [this paper][tam15] for some more examples.

## Solvers

I've built three solvers so far: Impulses with Projected
Gauss-Seidel, Iterated Impulses, and Extended Position-Based Dynamics.
Let's take a look at the theory and source material of each.

### Impulses with Projected Gauss-Seidel

I based this solver almost entirely on [this 2005 paper by Erin Catto][cat05].
It took me a long time to really understand the concept of a constraint, and in
hindsight I should definitely have looked up more sources at this point, but
just reading this over and over about fifty times ended up working surprisingly
well for me in the end.

<!-- source documents -->

[cat05]: https://www.gamedevs.org/uploads/iterative-dynamics-with-temporal-coherence.pdf
[cat14]: https://box2d.org/files/ErinCatto_UnderstandingConstraints_GDC2014.pdf
[tam15]: http://www.mft-spirit.nl/files/MTamis_Constraints.pdf
[mmcjk20]: https://matthias-research.github.io/pages/publications/PBDBodies.pdf
[2mp-vid]: https://www.youtube.com/watch?v=F0QwAhUnpr4

<!-- other links -->

[cattotwit]: https://twitter.com/erin_catto
[box2d]: https://box2d.org/
