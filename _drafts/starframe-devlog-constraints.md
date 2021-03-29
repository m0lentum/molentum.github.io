---
layout: post
title: "Starframe Devlog: Constraints in Physics"
date: 2021-01-09 00:11 +0300
categories: engine physics
usemathjax: true
---

The [Starframe] physics solver has gone through a few iterations recently as my
understanding of the problem and knowledge of available methods have grown. In
this post I attempt to explain what constraints are and detail a few
game-engine-friendly ways of solving them. I'll try to make this
understandable to someone with approximately the level of knowledge I had
before starting this: decent linear algebra and calculus skills and a
tiny bit of physics knowledge.

<!--excerpt-->

I'll start with the mathematical definition of constraints and then go over
three solvers in the order I implemented them myself: Impulses with Projected
Gauss-Seidel, Sequential Impulses, and Extended Position-Based Dynamics.

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
\begin{align*}
p_1(x_1, q_1) &= x_1 + q_1 \tilde{r}_1 \\
p_2(x_2, q_2) &= x_2 + q_2 \tilde{r}_2 \\
C_{contact}(x_1, q_1, x_2, q_2) &=
  (p_2(x_2, q_2) - p_1(x_1, q_1)) \cdot \hat{n} \\
  &= (x_2 + q_2 \tilde{r}_2 - x_1 - q_1 \tilde{r}_1) \cdot \hat{n} \\
\end{align*}
$$

where $q_1$ and $q_2$ are the orientations of each body, $\tilde{r}_1$ and
$\tilde{r}_2$ are the contact point in each body's local space, and
multiplication between them denotes a rotation by the orientation. From here on
I will use $r_1$ and $r_2$ to mean the worldspace offsets $q_1 \tilde{r}_1$ and
$q_2 \tilde{r}_2$ respectively, as this is the notation used by most papers.

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

Usually, the accepted range is either $C = 0$ (called an equality constraint),
or one of $C \leq 0$ and $C \geq 0$ (called inequality constraints).
Allowing something other than zero on the right-hand side would unnecessarily
complicate the solver, as constants like this can always be baked into the
constraint function instead.
{: .sidenote}

Another simple example of a constraint is a distance
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
constraint too, but this is a bit harder to implement efficiently and rarely
useful. Quoting [Erin Catto][cattotwit]'s (of [Box2D] fame) [2014 GDC
presentation][cat14],

> Constraints are an area of physics programming where we
> get to show our knowledge and creativity.

Check out e.g. the aforementioned presentation or [this paper][tam15] for some
more examples of constraint functions.

Constraints aren't just a physics thing! For instance, they're also an
important concept in optimization problems. The idea is the same there —
a function that takes some variables and returns a scalar, plus an acceptable
range for that scalar.
{: .sidenote}

## Solvers

I've built three solvers so far: Impulses with Projected
Gauss-Seidel, Sequential Impulses, and Extended Position-Based Dynamics.
Let's take a look at the theory and source material of each.

### Impulses with Projected Gauss-Seidel

I based this solver almost entirely on [this 2005 paper by Erin Catto][cat05],
with some input from the book Game Physics by David Eberly and other content
from the [Box2D publications page][box2dpub]. This was a long learning process
that involved a _ton_ of reading the same things over and over, and almost none
of the code I wrote for this is used anymore, but lots of invaluable
understanding was gained.

I recommend also reading the paper after (or before) you read this post.
I might have omitted or been unclear about something that the paper says
better, or vice versa. In general, reading many different takes on the same
thing is an effective way to understand complicated topics!
{: .sidenote}

This will be by far the longest section of this post because I'll cover
a lot of theory that applies to the other solvers as well.
{: .sidenote}

#### Constraint formulation

This method works on the velocity level, meaning that constraints take
velocities as their parameters and are resolved with velocity adjustments.
Earlier we defined constraints on positions instead, so we need to do a bit of
work to make them compatible with this idea. Velocity is the first time
derivative of position, so we can get to the velocity level by taking the time
derivative of the position constraint function. Here's what this would look
like for the contact constraint:

$$
\begin{align}
C_{contact}(x_1, q_1, x_2, q_2) &=
  (x_2 + r_2 - x_1 - r_1) \cdot \hat{n} \\
\dot{C}_{contact}(v_1, \omega_1, v_2, \omega_2)
  &= (v_2 + \omega_2 \times r_2 - v_1 - \omega_1 \times r_1) \cdot \hat{n} \\
  & \quad + (x_2 + r_2 - x_1 - r_1) \cdot \omega_1 \times \hat{n}
\end{align}
$$

The dot on $\dot{C}$ is a notation physicists use for the time derivative
$\frac{\partial C}{\partial t}$.
{: .sidenote}

where $v_i$ is the linear velocity of body $i$ and $\omega_i$ is its angular
velocity. The second term is likely to be negligibly small, so this solver
drops it entirely, leaving

$$
\dot{C}_{contact}(v_1, \omega_1, v_2, \omega_2)
  = (v_2 + \omega_2 \times r_2 - v_1 - \omega_1 \times r_1) \cdot \hat{n}
$$

The cross products here only apply in 3D where angular velocity is represented
as a 3D vector. In 2D the equivalent operation is $\omega r^\perp$ where
$r^\perp$ is the counterclockwise perpendicular (i.e. $r$ rotated 90 degrees
counterclockwise, also known as the left normal) of $r$.
{: .sidenote}

Doing a similar differentiation on all of our position-level constraints (or
defining constraints directly on the velocity level) gives us the building
blocks of the problem. Now we can dive into the solver's job of making all
these go on the right side of zero.

Beginning to arrange all the numbers in a way that this solver likes, we first
factorize our velocity constraints into a product of two matrices, one
containing the parameters of the constraint function (i.e. body velocities) and
one containing their coefficients from our functions, like this: $\dot{C} =
JV$. Continuing with the contact constraint as our example,

$$
\begin{align}
\dot{C}_{contact} &=
  (v_2 + \omega_2 \times r_2 - v_1 - \omega_1 \times r_1) \cdot \hat{n} \\
&= -\hat{n} \cdot v_1 - (r_1 \times \hat{n}) \cdot \omega_1
  + \hat{n} \cdot v_2 + (r_2 \times \hat{n}) \cdot \omega_2 \\
&= \begin{bmatrix}
  -\hat{n}^T & -(r_1 \times \hat{n})^T & \hat{n}^T & (r_2 \times \hat{n})^T
  \end{bmatrix}
  \begin{bmatrix}
  v_1 \\ \omega_1 \\ v_2 \\ \omega_2
  \end{bmatrix} \\
&= JV
\end{align}
$$

Note that $J$ and $V$ contain vectors as a shorthand notation.
The concrete matrices would be constructed by writing out the vectors elementwise,
producing a total of 12 elements in 3D (3 per $v$, 3 per $\omega$) and 6 in 2D
(2 per $v$, 1 per $\omega$).
{: .sidenote}

$J$ here is called the _Jacobian matrix_ of $C$.

As far as I understand, calling this the Jacobian isn't entirely accurate, as
the Jacobian is
[defined](https://en.wikipedia.org/wiki/Jacobian_matrix_and_determinant) as the
coefficients of spatial partial derivatives, whereas this one contains the
coefficients of the time derivative. I don't know of a better word so I'll
stick to the paper's nomenclature and call it the Jacobian nonetheless.
{: .sidenote}

A geometric interpretation of $\dot{C} = JV = 0$ is that $V$ must be orthogonal
to $J$ to satisfy the constraint. In more intuitive terms, this means that $V$
must be aligned with the level curve/surface $C = 0$ (because $J$ represents
the steepest direction of change for $C$ and is thus orthogonal to its level
curves).

What we need now is a vector to add to $V$ to accomplish this. There are an
infinite number of such vectors, but not just any will do. Because a
constraint's purpose is to prevent motion and not cause it, constraint forces
should do no [work](<https://en.wikipedia.org/wiki/Work_(physics)>). This is
only true if the force is orthogonal to $V$ and thus collinear with $J$. A
force in any other direction would cause an acceleration in a direction
allowed by the constraint, thereby doing work on the system.

This idea is hard to explain in rigorous terms and I may not have done
it very well. I think it's very intuitive though — imagine a box sitting on a
flat floor. Clearly, the supporting force keeping the box in place must be
orthogonal to the floor; otherwise it would cause the box to start sliding in
some direction.
{: .sidenote}

Knowing this, we can express the force as $F_c = J^T \lambda$, where $\lambda$
is an unknown scalar that we can solve for.

$F_c$ here contains both the linear and angular components of the force,
i.e. the force and the torque:
$$F_c = \begin{bmatrix} f_c \\ \tau_c \end{bmatrix}$$.
{: .sidenote}

#### Constructing the problem

We still need two more things to get to the problem we actually want to
solve, which is how the system evolves over time. First, we need a set of
equations called the _equations of motion_, which are exactly what
they sound like — equations describing motion. These are given by the
Newton-Euler equations. For a single body:

$$
\displaylines{
m\dot{v} = f_c + f_{ext} \\
I\dot{\omega} = \tau_c + \tau_{ext}
}
$$

Here $f_c$ and $\tau_c$ are constraint forces and torques, $f_{ext}$ and
$\tau_{ext}$ are external forces and torques (gravity, usually), $m$ is the
mass of a body and $I$ its moment of inertia.

In 2D, moment of inertia is a simple scalar. In 3D, it's a 3x3 matrix.
{: .sidenote}

Recalling that
$$F_c = \begin{bmatrix} f_c \\ \tau_c \end{bmatrix} = J^T \lambda$$
and $$V = \begin{bmatrix} v \\ \omega \end{bmatrix}$$,
we can refactor this into one matrix equation

$$
M\dot{V} = J^T \lambda + F_{ext}
$$

where $M$ is a block-diagonal mass matrix that looks like this in 2D:

$$
M = \begin{bmatrix}
m & 0 & 0 \\
0 & m & 0 \\
0 & 0 & I
\end{bmatrix}
$$

and like this in 3D:

$$
M = \begin{bmatrix}
m & 0 & 0 & 0 & 0 & 0 \\
0 & m & 0 & 0 & 0 & 0 \\
0 & 0 & m & 0 & 0 & 0 \\
0 & 0 & 0 & I_{11} & I_{12} & I_{13} \\
0 & 0 & 0 & I_{21} & I_{22} & I_{23} \\
0 & 0 & 0 & I_{31} & I_{32} & I_{33} \\
\end{bmatrix}
$$

To understand why the mass matrix is shaped like this, try computing the
product $M\dot{V}$ and see how the result matches the two Newton-Euler equations
above.
{: .sidenote}

Add the constraint equation $JV = 0$ from earlier and we have all the necessary
equations of motion. However, so far we've only been considering a single body.
For the body $i$, the equations of motion are thus

$$
\begin{align}
M_i \dot{V}_i &= J_i^T \lambda_i + F_{ext,i} \\
J_i V_i &= 0.
\end{align}
$$

Fortunately, extending these to the whole system of bodies is fairly
straightforward — we can simply stack the matrices from these equations on top
of each other (give or take a couple of details). For a system of $n$ bodies:

$$
\begin{align}
V &= \begin{bmatrix} v_1 \\ \omega_1 \\ \vdots \\ v_n \\ \omega_n \end{bmatrix} \\
J &= \begin{bmatrix} J_1 \\ \vdots \\ J_n \end{bmatrix} \\
\lambda &= \begin{bmatrix} \lambda_1 \\ \vdots \\ \lambda_n \end{bmatrix} \\
F_{ext} &= \begin{bmatrix} f_{ext,1} \\ \tau_{ext,1} \\ \vdots \\ f_{ext,n} \\ \tau_{ext,n} \end{bmatrix} \\
M &= \begin{bmatrix} M_1 & 0 & 0 \\ 0 & \ddots & 0 \\ 0 & 0 & M_n \end{bmatrix} \\
\end{align}
$$

One important detail is that the Jacobian rows $J_i$ won't line up correctly if
they just have the four vector elements they had earlier in our two-body
example. Here we need to treat them as if the constraint function took the
entire system's velocity vector as its parameters, which means a lot of padding
with zeroes.

This isn't super relevant to the actual solver because it doesn't really store
the padding zeroes in memory at all, but I'm mentioning it because
understanding the theoretical matrix dimensions was an important step in my own
understanding of the math we're doing here.
{: .sidenote}

Let's look at a concrete example. Say we have a system with three bodies.
There are two contacts, C1 between bodies 1 and 2 and C2 between bodies 1 and 3.
The velocity vector of this system looks like this:

$$
V = \begin{bmatrix} v_1 \\ \omega_1 \\ v_2 \\ \omega_2 \\ v_3 \\ \omega_3 \end{bmatrix}
$$

Earlier we defined the contact constraint as

$$
\dot{C}_{contact} = \begin{bmatrix}
  -\hat{n}^T & -(r_1 \times \hat{n})^T & \hat{n}^T & (r_2 \times \hat{n})^T
  \end{bmatrix}
  \begin{bmatrix}
  v_1 \\ \omega_1 \\ v_2 \\ \omega_2
  \end{bmatrix}. \\
$$

To replace the velocity vector here with the whole system's velocity vector
which has 6 rows, we need to pad the contact jacobians so they have 6 columns.
Here's the constraint vector for the whole system:

$$
C = JV = \begin{bmatrix}
  -\hat{n}^T_{C1} & -(r_{1,C1} \times \hat{n}_{C1})^T
    & \hat{n}^T_{C1} & (r_{2,C1} \times \hat{n}_{C1})^T & 0 & 0 \\
  -\hat{n}^T_{C2} & -(r_{1,C2} \times \hat{n}_{C2})^T
    & 0 & 0 & \hat{n}^T_{C2} & -(r_{3,C2} \times \hat{n}_{C2})^T \\
\end{bmatrix}
\begin{bmatrix}
v_1 \\ \omega_1 \\ v_2 \\ \omega_2 \\ v_3 \\ \omega_3
\end{bmatrix}
$$

The subscripts are a bit of a mess with this many variables around, but
hopefully you get the idea. Also, apologies to mobile users having to scroll
this horizontally :P
{: .sidenote}

Now that we have the matrices for the whole system,
the equations of motion look exactly like the single-body versions from earlier
but without the index subscripts:

$$
\begin{align}
  M \dot{V} &= J^T \lambda + F_{ext} \\
  JV &= 0
\end{align}
$$

Now we have our equations of motion. There's one more thing (besides $\lambda$
which we want to solve for) that we don't have: the acceleration $\dot{V}$.
We'll use a linear approximation: if we have a velocity $V_1$, move forward in
time by a step $\Delta t$, and the velocity is now $V_2$, then the acceleration
during that time step is approximately

$$
\dot{V} \approx \frac{V_2 - V_1}{\Delta t}.
$$

When we're at the beginning of the timestep, we don't know the value of $V_2$ —
it's actually the thing we're trying to eventually calculate here! As you'll
see in a second, this turns out to be less of a problem than it sounds like.
{: .sidenote}

With this we finally have all the variables needed to actually solve for
$\lambda$. The steps to get there are many and not entirely obvious, so I'll
write them out:

$$
\begin{align*}
  M\dot{V} &= J^T \lambda + F_{ext} \scriptstyle{\text{ (1st eq. of motion)}} \\
  M\frac{V_2 - V_1}{\Delta t} &= J^T \lambda + F_{ext} \\
  \frac{1}{\Delta t}MV_2 &= \frac{1}{\Delta t}MV_1 + J^T \lambda + F_{ext} \\
  \frac{1}{\Delta t}V_2 &= \frac{1}{\Delta t}V_1 + M^{-1} J^T \lambda + M^{-1} F_{ext} \\
  \frac{1}{\Delta t}V_2 - M^{-1} J^T \lambda &= \frac{1}{\Delta t}V_1 + M^{-1} F_{ext} \\
  \frac{1}{\Delta t}JV_2 - JM^{-1} J^T \lambda &= J(\frac{1}{\Delta t}V_1 + M^{-1} F_{ext}) \\
\end{align*}
$$

We multiplied by $J$ in the last step because the constraint equation states that
$JV_2 = 0$. We can now eliminate that term, flip the signs, and we're left with

$$
JM^{-1}J^T \lambda = -J(\frac{1}{\Delta t}V_1 + M^{-1} F_{ext}).
$$

We have the values for all the variables in this except $\lambda$, so
we're ready to solve this!

This is just an equation with an equality symbol, which doesn't do anything to
address inequality constraints. Those require some additional operations which
we'll get to in a minute.
{: .sidenote}

One more thing I do to simplify this further is to apply external forces
before solving anything with

$$
  V_{1+f} = V_1 + \frac{1}{\Delta t} M^{-1} F_{ext},
$$

leaving just

$$
  JM^{-1}J^T \lambda = -\frac{1}{\Delta t}JV_{1+f}.
$$

#### The solver itself

It's possible to solve this problem exactly with so-called global methods
(which I don't know much about), but these methods are too expensive for
real-time use. We need a faster approximate method. A class of numerical
methods known as Gauss-Seidel has just what we need.

The basic Gauss-Seidel method for linear systems looks like this in
(pseudo-)Rust:

The same algorithm is presented as regular pseudocode in the [paper][cat05],
so look there if you prefer that style.
{: .sidenote}

```rust
/// approximately solve x in the linear system Ax = b
/// starting with an initial guess x0
fn gauss_seidel<const N: usize>(
    a: [[f64; N]; N],
    b: [f64; N],
    lambda_0: [f64; N],
) -> [f64; N] {
    let mut lambda = lambda_0;
    for _iter in 0..MAX_ITERATIONS {
        for i in 0..N {
            let delta_lambda_i = (b[i] - dot(a[i], lambda)) / a[i][i];
            lambda[i] += delta_lambda_i;
        }
    }
    lambda
}
```

You might want to check e.g. how much the values of $\lambda$ changed in an
iteration and exit early if they're all below some threshold, but it's probably
fine to just run `MAX_ITERATIONS` iterations every time.
{: .sidenote}

However, we have inequality constraints which can't be expressed as a linear
system of equations, so this isn't enough. Fortunately, we only need one new
operation. The trick is that we can allow a range of values of $C$ by
_limiting_ the allowed range of $\lambda$. For instance, if we want $C \geq 0$,
we can disallow negative values for $\lambda$.

Remember that $\lambda$ represents an impulse that moves things in the gradient
direction of $C$, meaning that a positive $\lambda$ would cause $C$ to increase
and a negative $\lambda$ would cause it to decrease. Thus, a negative $\lambda$
would only appear when $C > 0$.
{: .sidenote}

In general, we can clamp $\lambda$ in a range $[\lambda^-, \lambda^+]$. For
example, the range for an inequality constraint $C \geq 0$ would be $[0,
\infty]$. For an equality constraint we don't want any limits, so the range
would be $[-\infty, \infty]$. This clamping operation is also called
_projection_, hence the name Projected Gauss-Seidel algorithm, which looks
something like this:

```rust
// changes from normal gauss-seidel denoted with // *

fn projected_gauss_seidel<const N: usize>(
    a: [[f64; N]; N],
    b: [f64; N],
    bounds: [(f64, f64); N], // *
    lambda_0: [f64; N],
) -> [f64; N] {
    let mut lambda = lambda_0;
    for _iter in 0..MAX_ITERATIONS {
        for i in 0..N {
            let delta_lambda_i = (b[i] - dot(a[i], x)) / a[i][i];
            lambda[i] += delta_lambda_i;
            lambda[i] = clamp(lambda[i], bounds[i].0, bounds[i].1); // *
        }
    }
    lambda
}
```

The initial guess can be anything, but a vector of zeroes is a good choice
if we have nothing better to go off. More on this later.
{: .sidenote}

That's it! We can now take the matrix equation from earlier,

$$
JM^{-1}J^T \lambda = -\frac{1}{\Delta t}JV_{1+f},
$$

add appropriate bounds for inequality constraints,
and feed it into this algoritm. In reality, there's also an indirection
step to avoid storing lots of zeroes in $J$ and $M$, but this is the gist of
it. Refer to the [paper][cat05] for all the details.

By the way, this type of matrix problem involving inequalities is called a
_linear complementarity problem_.
{: .sidenote}

#### Finishing steps

Now that we have $\lambda$, the hard part is done, but a few more things need
to be done to put it in action. We need to apply the impulse to the system
velocity and step forward in time.

Solving for $V_2$ from our earlier equations of motion gives

$$
  V_2 = V_{1+f} + \Delta t M^{-1} J^T \lambda.
$$

The best suited method for stepping forward in time with the information we have
is the [semi-implicit Euler method](https://en.wikipedia.org/wiki/Semi-implicit_Euler_method),
which preserves energy well and doesn't require solving any further equations.
The formula for it is simple: for each body with pre-timestep position $x_1$ and
newly computed velocity $v_2$ we do

$$
  x_2 = x_1 + \Delta t v_2.
$$

Now we run collision detection again to update $J$, re-do all of this math, do
that 60 times per second and we have a simulation! It's not the most accurate
one out there, but it's quite fast and good enough for the vast majority of
games.

#### Additional tricks

There's a variety of little things we can plug on top of this method to improve
its performance and model more kinds of things. Here's a brief overview of what
I know of.

##### **Resolving overlaps**

Because this method works on the velocity level, it prevents position-level
errors from getting worse, but does nothing to _resolve_ them. If two bodies
overlap, solving the velocity-level contact constraint stops them from moving
deeper into each other, but won't move them apart. In practice this causes
stacks of objects to slowly sink into each other. A mechanism for resolving
position errors is needed.

This solver addresses the problem using something called _Baumgarte
stabilisation_. By modifying the constraint equation $JV = 0$ to include a
_bias_: $JV = \zeta$, constraints can be made to cause movement and not just
stop it, doing work in the process. If we feed the position error $C$ into the
bias term, the velocity constraint will push bodies towards a permissible
configuration:

$$
  \zeta = -\beta C
$$

where $\beta$ is a tuning coefficient that controls how fast errors are resolved.

With this modification, the equation for $\lambda$ becomes

$$
JM^{-1}J^T \lambda = \frac{1}{\Delta t} (\zeta - JV_{1+f}).
$$

A problem with this is that constraints with nonzero bias do work, thereby
adding energy to the system. If $\beta$ is too high, objects can jitter and
bounce when they collide, but if it's very low, overlaps will take a long time
to resolve.

In his later work (e.g. [this presentation][cat14]), Catto speaks about
using _pseudo velocities_ for corrections instead. These are velocities that
are immediately discarded and don't affect future states, removing the
problem of generating energy.
{: .sidenote}

Another option is _projection_, which simply moves objects apart directly on
the position level. This doesn't create energy, but tends to cause stacked
objects to jitter due to the projection away from one object moving them into
overlap with another one.

Whatever method you choose, leaving a bit of _slop_ can make a big difference.
This means scaling position errors down slightly before solving them, so that
they're never quite resolved completely. This guarantees that resting contacts
get a collision every frame, eliminating jitter caused by overcorrections
pushing objects all the way apart.

##### **Other uses for bias**

Bias can be a useful tool even if you do something else to correct errors.
For example, elastic collisions (i.e. bouncy things) can be modeled by
setting the bias to $-eJV_1$, where $e$ is the coefficient of restitution.

I haven't actually implemented this, but I'm pretty sure that's the formula.
{: .sidenote}

Also, various kinds of motors can be created by varying a constraint over time
and using bias-based position correction (as described above) to power it.

##### **Friction**

Friction is a bit of a weird phenomenon to represent as a constraint, for a
few reasons. For one, it only exists at the velocity level. Also, it
doesn't always completely stop movement; in most cases it merely slows things
down. How much it slows things down depends on many factors.

Friction slows down movement in the tangent direction of every contact.
A neat thing about this is that we can reuse the constraint equation from
the contact, just replacing $\hat{n}$ with its tangent.

In 3D, the tangent is a plane. The paper uses two separate constraints with two
linearly independent tangent vectors to achieve friction in the whole tangent
plane. This is results in something called a pyramid-shaped _friction cone_.
It's not perfectly accurate, but as usual, game physics is all about being fast
and plausible.
{: .sidenote}

We can simulate a bounded friction force by limiting the minimum and maximum
values of $\lambda$ for the friction constraint. The paper uses a simplified
model with a single coefficient of friction and no regard to other forces in
the system with

$$
  -\mu m_c g \leq \lambda \leq \mu m_c g
$$

where $\mu$ is the coefficient of friction between the colliding bodies'
materials, $m_c$ is a fraction of the bodies' masses depending on the number of
contact points between them, and $g$ is the acceleration of gravity.

In my solver, I went for a slightly more sophisticated model based on
Coulomb's friction model, which states that the friction force is bounded by
the supporting force:

$$
  -\mu \lambda_n \leq \lambda \leq \mu \lambda_n
$$

where $\lambda_n$ is the impulse caused by the contact constraint related to
this friction constraint. This requires a bit more code for finding
$\lambda_n$ but is more realistic, especially in stacks of bodies where the
ones at the bottom correctly experience more friction than the ones at the top.

In reality, there's also a difference between static and dynamic friction, i.e.
friction that prevents motion from starting and friction that slows down
nonzero motion. I didn't care enough to implement this.
{: .sidenote}

##### **Impulse caching**

Sometimes the PGS algorithm is slow to converge on the correct solution. These
cases can be made less common with better initial guesses, and physics has a
nice property called _temporal coherence_ that can help us here. This means
that things tend not to change much from one timestep to the next. By caching
the result $\lambda$ of one timestep and using it as the next step's initial
guess $\lambda_0$, convergence becomes faster whenever the state of the system
doesn't change drastically between timesteps. This is called _warm starting_
the algorithm.

I'm not an expert on when or why convergence is slow, but one such situation
is when bodies with wildly different masses interact. You can help convergence
simply by designing systems where big mass discrepancies don't exist.
{: .sidenote}

This can have a side effect of causing bounces when large forces suddenly
disappear, as you start with a large $\lambda_0$ and fail to converge on the
small correct solution. It may be helpful to tune it e.g. by multiplying with
some constant $\alpha$ between 0 and 1, $\lambda_0 = \alpha \lambda$.
{: .sidenote}

This introduces a tricky little problem: contacts are regenerated by collision
detection every timestep. We need a way to match new contacts with previous
ones to figure out which element of $\lambda_0$ belongs to them. The paper
introduces a couple of options for solving this: contact point positions or
incident edge labels. Contact point positions change, so they need a tolerance
region where two points are considered the same. This is tricky because it's
hard to know how much the contact points can move between timesteps. Labeling
incident edges means assigning numbers to the edges on each body's collider
that make up the contact point. I used a method similar to this, but my
implementation had some problems so probably don't copy it :)

##### **Islands and sleeping**

This is an optimization method the paper doesn't cover and I haven't
implemented (yet) either, but it's something worth knowing. By building a graph
with bodies as nodes and constraints as edges, we can identify sets of bodies
that directly or indirectly affect each other, often called _islands_.

![Two islands of interacting bodies](/assets/TODO)

Having identified these islands, we can send them all to different threads to
solve with PGS (which itself can't be parallelized) simultaneously or, more
importantly, islands where nothing is happening can be set to _sleep_. This
means that they're skipped entirely by the solver until their topology changes,
that is, a new constraint appears (a collision happens) or something
disappears. You can imagine how much time this would save in a large game level
where things only actually happen near the player.

##### **Code**

For those who like to read code, here's a link to [my PGS solver's source
code][pgs-src], and here's the [timestep function][pgs-src-tick] that builds
all the matrices.

### Sequential impulses

Finally, I've run out of things to ramble about and it's time to move to a
different method. We're not going very far though — this one still works on the
velocity level with mostly the same constraint formulations, is still largely
based on Erin Catto's work, and even the code for it is mostly the same as
before. The method is called Sequential Impulses, and it does what it sounds
like it does.

The idea of this solver is that instead of building this big matrix problem
that PGS wants, we compute $\lambda$ individually for every constraint (using
the exact same equations from earlier) and immediately apply it to body
velocities. Repeat this however many times you can afford to and you have an
approximate global solution.

If you (figuratively) squint your eyes a little, this looks almost exactly like
PGS, which solves each row of the matrix individually. The benefit is the
removal of the matrix abstraction, which makes the method easier to understand
and somewhat more flexible — it's easy to change the formula for $\lambda$ on a
per-object basis if you need to.

So why did I make this change? I was trying to implement [soft
constraints][cat11], which are a way to express physically accurate springs as
constraints. This changes the formula for $\lambda$ in a way that isn't
entirely obvious in how it fits into the matrix of PGS, so I found it easier to
switch methods.

#### Soft constraints

The difference between hard and soft constraints is that soft constraints
resolve over multiple timesteps and not immediately. This is achieved by
augmenting the constraint equation from

$$
  Jv = 0
$$

to

$$
  Jv + \frac{\beta}{\Delta t} C + \frac{\gamma}{\Delta t} \lambda = 0.
$$

Here $\beta$ is a position correction coefficient similar to Baumgarte
stabilisation earlier, responsible for steering the constraint towards $C = 0$,
and $\gamma$, called _compliance_, feeds $\lambda$ back into the equation,
allowing a constraint violation proportional to currently applied force. This
is hard to understand intuitively and I don't really know how to explain it any
better, but take a look at the [slides linked earlier][cat11] to see how they
relate to spring-damper systems and harmonic oscillators.

The reason why I found this hard to integrate into PGS is that it changes the
way $\lambda$ is treated. Instead of just computing a $\lambda$, applying and
then discarding it, we need to hold on to it because it's on both sides of the
equation now. This ends up looking like this:

$$
  \begin{align*}
    \Delta \lambda &\leftarrow -\frac{Jv + \frac{\beta}{\Delta t} C + \frac{\gamma}{\Delta t}}
                {JM^{-1}J^T + \gamma} \\
    \lambda &\leftarrow \lambda + \Delta \lambda
  \end{align*}
$$

All the tricks like warm starting and Baumgarte stabilisation discussed at the
end of the last chapter still apply here, but warm starting in particular
requires some care as it doesn't play as well with soft constraints.
{: .sidenote}

The code for this one is a bit messy because it heavily reuses PGS code, and I
don't think I used harmonic oscillator parameters correctly, but for the sake
of completeness, here's a link to [this solver incarnation's source code][si-src].

### Extended Position-Based Dynamics

While I was working on Sequential Impulses, I suddenly remembered [this Two
Minute Papers video][2mp-vid] about an impressive-looking recent method called
Extended Position-Based Dynamics (abbreviated XPBD). I was unhappy about how
messy my code was getting and thought it was a perfect time to check out [the
source paper][mmcjk20]. Surprisingly, I was able to understand more or less all
of it and decided to redo my entire solver once again.

As the name implies, XPBD is an extension of the [Position-Based
Dynamics][mhhr06] (PBD) method to handle rigid bodies. PBD, then, is a method
of particle simulation based on [Verlet
integration](https://en.wikipedia.org/wiki/Verlet_integration) where
constraints are solved on the position level and velocities aren't touched at
all. Velocity is then approximated from position changes. In pseudo-Rust,

```rust
fn pbd_timestep(dt: f64) {
    for p in particles {
        p.old_position = p.position;
        p.velocity += (ext_force / p.mass) * dt;
        p.position += p.velocity * dt;
    }
    solve_position_constraints();
    for p in particles {
        p.velocity = (p.position - p.old_position) / dt;
    }
}
```

Why is this good? Many position constraints are _nonlinear_. For instance, the
distance constraint wants particles to move in a circle around each other,
which clearly isn't a linear shape. If we take the time derivative to solve
this type of constraints on the velocity level, we create a linear problem,
which can be easier to solve, but comes with inaccuracy. Here's an illustration
similar to one you can find in the XPBD paper:

![Solving distance constraints on the velocity level and the position level](/assets/TODO)

Here $p_1$ and $p_2$ are fixed positions that the particle $p_3$ is attached to
with distance constraints $l_1$ and $l_2$. The first image shows how a
velocity-level solve can only operate in the tangent direction of the distance
constraints, and as a result can never find the position satisfying both
constraints. The second image shows how a position-level solve can change the
correction direction, enabling it to converge on the correct solution.

This type of iterative solution methods where the direction can change are called
_nonlinear Gauss-Seidel_ methods.
{: .sidenote}

Because PBD is good at nonlinear problems, it's popular in simulating
deformable bodies such as cloth built out of distance-constrained particles. A
big advantage of XPBD compared to velocity-based methods is that connecting
such simulations with rigid bodies becomes very simple.

The trouble with rigid bodies compared to particles is that in addition to
position, they also have an orientation. Regular PBD only deals in positions.
This is where the X in XPBD comes to the rescue, adding two new correction
operations.

For a general position constraint $C(x_1, q_1, x_2, q_2) = 0$, starting
from Newton's second law like we did with the PGS solver, adding compliance
(familiar from soft constraints) and solving for a position correction
$\lambda$ gives

$$
\begin{align*}
  \Delta \lambda &\leftarrow -\frac{C - \frac{\alpha}{(\Delta t)^2} \lambda}
        {\nabla C M^{-1} \nabla C^T + \frac{\alpha}{(\Delta t)^2}} \\
  \lambda &\leftarrow \lambda + \Delta \lambda
\end{align*}
$$

The derivation for this can be found in [the original XPBD paper][mmc17].
This paper uses some advanced language and ideas I don't understand well enough
to explain, so I won't go over the whole thing here.
{: .sidenote}

where $\alpha$ is compliance (using a different symbol in this paper). The only
difference from the velocity-level soft constraints from earlier is using the
gradient $\nabla C$ in place of $J$ and dividing compliance by timestep one more
time to get physically correct units at the position level.

In terms of physical properties, compliance is the inverse of _stiffness_.
Hard constraints like contacts have a compliance of zero, corresponding to
infinite stiffness.
{: .sidenote}

For a contact constraint (or any constraint restricting movement at a point in
a direction), this can be written as

$$
\begin{align*}
  \Delta \lambda &\leftarrow -\frac{C - \frac{\alpha}{(\Delta t)^2} \lambda}
        {w_1 + w_2 + \frac{\alpha}{(\Delta t)^2}} \\
  \lambda &\leftarrow \lambda + \Delta \lambda
\end{align*}
$$

where $w_1$ and $w_2$ are each body's _generalized inverse mass_ or _effective
inverse mass_,

$$
  w = \frac{1}{m} + (qr \times \hat{n})^T I^{-1} (qr \times \hat{n}).
$$

Here $m$ is the body's mass and $r$ and $n$ are the contact's offset and normal
as discussed in the first chapter of the post.

As seen earlier, the cross products only apply in 3D. The 2D equivalent is

$$
  w = \frac{1}{m} + \frac{(\omega r^\perp)^2}{I}.
$$

This can be factored like this in 2D because $I$ is a scalar. In 3D it's a
matrix and order of operations matters.
{: .sidenote}

Once we have $\Delta \lambda$, we turn it into an impulse $p = \Delta \lambda
\hat{n}$ and apply it to positions right away with

$$
  \begin{align*}
    x_1 &\leftarrow x_1 + \frac{p}{m_1} \\
    x_2 &\leftarrow x_2 - \frac{p}{m_2} \\
  \end{align*}
$$

and to orientations with

$$
  \begin{align*}
    q_1 &\leftarrow q_1 + \frac{1}{2}[I_1^{-1}(r_1 \times p),0] q_1 \\
    q_2 &\leftarrow q_2 - \frac{1}{2}[I_2^{-1}(r_2 \times p),0] q_2 \\
  \end{align*}
$$

if you're in 3D using quaternions, or

$$
  \begin{align*}
    q_1 &\leftarrow q_1 + I_1^{-1} (p \cdot r_1^\perp) \\
    q_2 &\leftarrow q_2 - I_2^{-1} (p \cdot r_2^\perp) \\
  \end{align*}
$$

if, like me, you're in 2D using angles.

An equivalent to the "perp-dot product" used above is the _wedge product_ $p
\wedge r$ (interpreted as a scalar (in geometric algebra terms, the actual type
this operation gives (in 2D) is something called a _pseudoscalar_ (confusing
nested parentheses, woo!))).
{: .sidenote}

This is all it takes to solve a constraint of this type.

This is essentially the same operation you would use to resolve overlaps with
projection instead of Baumgarte stabilisation in the earlier solvers!
{: .sidenote}

- Angle constraint next!

- working on both position and velocity level
- substeps instead of iterations
  - advantage: better energy conservation and stiffness
  - demonstrate difference from earlier solver
  - tradeoff: need more collision checking
- nonlinear at position-level
  - simpler attachment constraints
  - no overshoot on contacts and joint limits
- no need for warm starting shenanigans

- demo also PGS after that chapter!

<!-- source documents -->

[cat05]: https://www.gamedevs.org/uploads/iterative-dynamics-with-temporal-coherence.pdf
[cat11]: https://box2d.org/files/ErinCatto_SoftConstraints_GDC2011.pdf
[cat14]: https://box2d.org/files/ErinCatto_UnderstandingConstraints_GDC2014.pdf
[tam15]: http://www.mft-spirit.nl/files/MTamis_Constraints.pdf
[mhhr06]: https://matthias-research.github.io/pages/publications/posBasedDyn.pdf
[mmc17]: https://matthias-research.github.io/pages/publications/XPBD.pdf
[mmcjk20]: https://matthias-research.github.io/pages/publications/PBDBodies.pdf
[2mp-vid]: https://www.youtube.com/watch?v=F0QwAhUnpr4

<!-- other links -->

[starframe]: https://github.com/MoleTrooper/starframe/
[cattotwit]: https://twitter.com/erin_catto
[box2d]: https://box2d.org/
[box2dpub]: https://box2d.org/publications/
[pgs-src]: https://github.com/MoleTrooper/starframe/blob/89953322eedcb491815aa6f6115797f9cca78d0a/src/physics/constraint.rs#L315
[pgs-src-tick]: https://github.com/MoleTrooper/starframe/blob/89953322eedcb491815aa6f6115797f9cca78d0a/src/physics.rs#L152
[si-src]: https://github.com/MoleTrooper/starframe/blob/3db52efa10a8c505fe352d9bc57f70ce00fea45a/src/physics/constraint/solver.rs#L71
[xpbd-src]: https://github.com/MoleTrooper/starframe/blob/master/src/physics.rs
