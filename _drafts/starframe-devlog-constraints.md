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

![Two boxes that overlap](/assets/TODO)

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
p_1(x_1, q_1) = x_1 + q_1 r_1 \\
p_2(x_2, q_2) = x_2 + q_2 r_2 \\
C_{contact}(x_1, q_1, x_2, q_2) =
  (p_2(x_2, q_2) - p_1(x_1, q_1)) \cdot \hat{n} \\
  = (x_2 + q_2 r_2 - x_1 - q_1 r_1) \cdot \hat{n}
}
$$

where $q_1$ and $q_2$ are the orientations of each body,
$r_1$ and $r_2$ are the contact points in each body's local space,
and multiplication between them denotes a rotation by the orientation.

Note:
There are many ways to represent orientations. Most 3D engines use unit
quaternions, the 2D equivalent of which is a unit complex number. In 2D, even
just a single angle can be used. I use _rotors_ from geometric algebra (see
e.g. [bivector.net](https://bivector.net) for sources).
{: .sidenote}

One question remains: what's an acceptable value for this function
to return? Geometrically it measures the amount of overlap between the
objects, so anything zero or less means there's no overlap at all.
Thus, any state where

$$
C_{contact}(x_1, q_1, x_2, q_2) \leq 0
$$

is legal. This is the whole constraint — a function from world state to a value
and an acceptable range of values. That's what every kind of constraint boils
down to. The constraint solver's job is to try to find a state where every
constraint function returns an acceptable value.

Note:
Usually, the accepted range is either $C = 0$ (called an equality constraint),
or one of $C \leq 0$ and $C \geq 0$ (called inequality constraints).
Allowing something other than zero on the right-hand side would unnecessarily
complicate the solver, as constants like this can always be baked into the
constraint function instead.
{: .sidenote}

Let's look at a couple more examples to make it easier to believe that all
constraints really look the same. Another simple case is a distance
constraint, which attaches two objects such that the distance between
selected points on them is always in some range.

![Two boxes attached with a distance constraint](/assets/TODO)

To achieve this we can simply measure the difference between the actual
distance and the desired one $d$:

$$
C_{dist}(x_1, q_1, x_2, q_2) =
  \|p_2(x_2, q_2) - p_1(x_1, q_1)\| - d
$$

For the accepted range we have a choice: $C \leq 0$ will only pull the bodies
towards each other, $C \geq 0$ will only push them apart, and $C = 0$ will do
both.

The idea of a constraint is very flexible. Putting the right math in $C$ can
produce a variety of effects like friction, all sorts of joints, and with some
additional trickery even things like motors and springs (we'll take a look at
these things when discussing solvers). You can also remove one body from
constraint function's parameters and attach bodies to places in the world
instead. Technically more than two bodies could participate in a single
constraint too, but this is a bit harder to implement and rarely useful. Like
[Erin Catto][cattotwit] (of [Box2D] fame) said in [his 2014 GDC
presentation][cat14], constraints are a place where physics programmers get to
apply creativity. Check out e.g. the aforementioned presentation or [this
paper][tam15] for some more examples of constraint functions.

## Solvers

I've built three solvers so far: Impulses with Projected
Gauss-Seidel, Iterated Impulses, and Extended Position-Based Dynamics.
Let's take a look at the theory and source material of each.

### Impulses with Projected Gauss-Seidel

I based this solver almost entirely on [this 2005 paper by Erin Catto][cat05],
with some input from the book Game Physics by David Eberly. It took me a long
time to get a sufficient grasp of the math, and in hindsight I should probably
have looked up more sources at this point, but just reading this over and over
about fifty times ended up working surprisingly well for me in the end.

This method works on the velocity level, meaning that constraints are defined
on velocities and resolved with velocity adjustments. Earlier we defined
constraints on positions instead, so we need to do a bit of work to make them
compatible with this idea. Velocity is the first time derivative of position,
so we can get to the velocity level by taking the time derivative of the
position constraint function. Here's what this would look like for the contact
constraint:

$$
\displaylines{
C_{contact}(x_1, q_1, x_2, q_2) =
  (x_2 + q_2 r_2 - x_1 - q_1 r_1) \cdot \hat{n} \\
\dot{C}_{contact}(v_1, \omega_1, v_2, \omega_2)
  = (v_2 + \omega_2 \times q_2 r_2 - v_1 - \omega_1 \times q_1 r_1) \cdot \hat{n}
  + (x_2 + q_2 r_2 - x_1 - q_1 r_1) \cdot \omega_1 \times \hat{n}
}
$$

where $v_i$ is the linear velocity of body $i$ and $\omega_i$ is its angular
velocity. The second term is likely to be negligibly small, so this solver
drops it entirely, leaving

$$
\dot{C}_{contact}(v_1, \omega_1, v_2, \omega_2)
  = (v_2 + \omega_2 \times q_2 r_2 - v_1 - \omega_1 \times q_1 r_1) \cdot \hat{n}
$$

Note:
The cross products here only work in 3D where angular velocity is represented
as a 3D vector. In 2D the actual operation is $\omega q r^\perp$ where
$r^\perp$ is the counterclockwise perpendicular (i.e. $r$ rotated 90 degrees
counterclockwise, also known as the left normal) of $r$.
{: .sidenote}

Doing a similar differentiation on all of our position-level constraints (or
formulating constraints directly on velocities from the outset, but this isn't
always ideal for reasons we'll get into later) gives us the building blocks of
the problem. Now we can dive into the solver's job of making all these go on
the right side of zero.

Beginning to arrange all the numbers in a way that this solver likes, we first
factorize our velocity constraints into a product of two matrices, one
containing the velocities of bodies in the system and one containing their
coefficients from our functions, like this: $\dot{C} = JV$.
Continuing with the contact constraint as our example,

$$
\displaylines{
\dot{C}_{contact} =
  (v_2 + \omega_2 \times q_2 r_2 - v_1 - \omega_1 \times q_1 r_1) \cdot \hat{n} \\
= -\hat{n} \cdot v_1 - (q_1 r_1 \times \hat{n}) \cdot \omega_1
  + \hat{n} \cdot v_2 + (q_2 r_2 \times \hat{n}) \cdot \omega_2 \\
= \begin{bmatrix}
  -\hat{n}^T & -(q_1 r_1 \times \hat{n})^T & \hat{n}^T & (q_2 r_2 \times \hat{n})^T
  \end{bmatrix}
  \begin{bmatrix}
  v_1 \\ \omega_1 \\ v_2 \\ \omega_2
  \end{bmatrix}
}
$$

$J$ here is called the _Jacobian matrix_ of $C$.

Note:
As far as I understand, calling this the Jacobian isn't entirely accurate, as
the Jacobian is
[defined](https://en.wikipedia.org/wiki/Jacobian_matrix_and_determinant) as the
coefficients of spatial partial derivatives, whereas this one contains the
coefficients of the time derivative. I don't have a better word so I'll
stick to the paper's nomenclature and call it the Jacobian nonetheless.
{: .sidenote}

A geometric interpretation of $\dot{C} = JV = 0$ is that $V$ and $J$ must
be orthogonal to satisfy the constraint.
TOTO: conservation of energy, equal and opposite forces, principle of
virtual work, yadda yadda -> forces also orthogonal to V, becomes $F_c = J^T \lambda$

- matrix, PGS, note about abstractness of matrix construction
  (vs. "just hit them with impulses 4Head")
- bias, Baumgarte stabilisation, problem of adding energy
  and being slow to resolve position errors
- semi-implicit Euler integration
- something about stability and convergence? or just refer to sources
- warm starting
- consider dropping the $q$s everywhere to simplify and conform to the paper

### Iterated impulses

- still working on velocity level
- only a minimal change to the solver
- enables more flexible constraint formulations
  (PGS requires same form of the function for everything)
  (e.g. soft constraints)

### Extended Position-Based Dynamics

- modern
- Verlet instead of semi-implicit Euler
- originally for just particles
- working on both position and velocity level
- substeps instead of iterations
  - advantage: better energy conservation and stiffness
  - tradeoff: need more collision checking
- nonlinear at position-level
  - simpler attachment constraints
  - no overshoot on contacts and joint limits
- no need for warm starting shenanigans

<!-- source documents -->

[cat05]: https://www.gamedevs.org/uploads/iterative-dynamics-with-temporal-coherence.pdf
[cat14]: https://box2d.org/files/ErinCatto_UnderstandingConstraints_GDC2014.pdf
[tam15]: http://www.mft-spirit.nl/files/MTamis_Constraints.pdf
[mmcjk20]: https://matthias-research.github.io/pages/publications/PBDBodies.pdf
[2mp-vid]: https://www.youtube.com/watch?v=F0QwAhUnpr4

<!-- other links -->

[cattotwit]: https://twitter.com/erin_catto
[box2d]: https://box2d.org/
