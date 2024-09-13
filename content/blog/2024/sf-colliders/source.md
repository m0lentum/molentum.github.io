+++
title = "Starframe devlog: Rounding collider corners"
draft = true
date = 2022-07-21
slug = "rounding-collider-corners"
[taxonomies]
tags = ["starframe", "physics", "collision"]
[extra]
use_katex = true
+++

Earlier this year I entirely rewrote one of the most complicated parts of
[Starframe], the collision detection system. A notable feature of the new system
is the ability to give any shape rounded corners. Here's why and how I did it.

<!-- more -->

Some basic linear algebra knowledge like dot products and projections will be assumed.

To begin, let's examine the situation before this rework took place.

## Status quo

I had already written a system that was quite fast, accurate and robust,
however, there was one glaring problem with it: I only had three collider shapes
and adding more was an extremely laborious operation. To illustrate why,
the collision check function looked like this (heavily paraphrased
to focus on the point):

```rust
pub fn intersection_check(colliders: [Collider; 2]) -> ContactResult {
    use ColliderShape::*;
    match [colliders[0].shape, colliders[1].shape] {
	[Circle, Circle] => circle_circle(colliders),
	[Circle, Rectangle] => circle_rect(colliders),
	[Circle, Capsule] => circle_capsule(colliders),
	[Rectangle, Circle] => flip(circle_rect(colliders)),
	[Rectangle, Rectangle] => rect_rect(colliders),
	[Rectangle, Capsule] => rect_capsule(colliders),
	[Capsule, Circle] => flip(circle_capsule(colliders)),
	[Capsule, Rectangle] => flip(rect_capsule(colliders)),
	[Capsule, Capsule] => capsule_capsule(colliders),
    }
}
```

The point being that every possible pair of shapes had its own hand-written
query. This meant adding a fourth shape would involve adding four more queries,
then adding a fifth would require five, and so on. This file was already over a
thousand lines long at this point, and implementing the three queries needed for
capsules had taken me several days of work. Clearly this was not sustainable
and I needed a generic solution.

Fortunately, these queries are all executing the same fundamental operation
called a separating axis test. I just needed to find a way to untangle that
operation from the specifics of each shape. While I was working that out I came
up with a way to extend the algorithm for rounded shapes. We'll need a bunch of
theory to get to that point, so first, let's talk about what the separating
axis test does.

## The separating axis test

The [Separating Hyperplane Theorem][sht] states something to the effect of: two
[**convex**][convex] shapes do not intersect if and only if you can draw a straight
line between them that doesn't touch either of them.

{% sidenote() %}
It's a line in 2D, plane in 3D, etc. This works in any dimension, which is why
the general theorem calls it a hyperplane.
{% end %}

![Illustration of two pairs of shapes, one intersecting and one not, and a line
drawn between them.](sat_line.png)

Now, how do we find such a line (or the lack thereof)? The first step is to
consider all possible _directions_ the line can go in. For every such
direction, there is a perpendicular _axis_.

![The previous illustration with the axis perpendicular to the line
added.](sat_axis.png)

With this we can transform the question "can a line in this direction fit between the shapes?"
into "is there room between the shapes when measured along this axis?".
This is a question we can actually answer by projecting each shape onto the axis!

![The previous illustration with projections of the shapes to the
axis.](sat_proj.png)

This still doesn't help all that much considering there are an infinite number of
possible directions. However, in games we're working with polygons, which have
a nice property: it's sufficient to test only the planes that align with each polygon's
edges, i.e. only the axes corresponding to their normals.

{% sidenote() %}
I'm not sure how to prove this, but it has to do with the fact that two
polygons cannot intersect without two of their edges intersecting. In 3D this is a
little more complicated because polyhedra have both faces and edges, which
results in more possible ways to intersect.
{% end %}

![Illustration of a rectangle and a circle, along with their potential
separating axes.](sat_sep.png)

So, a simple separating axis test that tells us whether or not two convex shapes intersect
goes as follows:

1. Define every possible separating axis for both shapes
2. For every axis, project both shapes onto it and see if the projections overlap
3. If an axis with no overlap was found, the shapes do not overlap. Otherwise they do.

Now, this only tells us whether or not a collision occurred, which isn't nearly
enough information to do physics with, but we'll get back to that later.

I'm glossing over a lot of detail here to keep this brief.
For a more comprehensive look at separating axis tests, I recommend the book
Real-Time Collision Detection by Christer Ericson or [this tutorial by Metanet Software][metanet-tut].
The tutorial has some fantastic interactive visualizations which unfortunately have been
lost to time due to the death of Flash, but it's still very good.

## Circles

Circles don't have a finite number of edges like polygons do, which poses a
problem for the separating axis test. Fortunately, circles are nice in other
ways. A circle is defined in terms of distance only, independent of direction,
which means the projection of a circle to any axis is always the same. This
allows us to limit a separating axis test to just one axis, namely the one
pointing from the circle center to the closest point to it on the other shape.

{% sidenote() %}
Once you have the closest point on the other shape, a separating axis test is
actually redundant — just check if that point is inside the circle.
{% end %}

How to compute the closest point on the other shape isn't entirely obvious,
but in the interest of vaguely coherent storytelling I'll get back to that later.

## Combining circles and polygons

Now we get to the cool idea that actually motivated me to write this blog post.
That idea is called the [Minkowski sum][minkowski] and it's a way to take two shapes
and combine them into one larger shape. Formally, the Minkowski sum of sets
$A$ and $B$ is the set containing every sum of two elements from $A$ and $B$,

$$
A + B = \{ a + b \,|\, a \in A, b \in B \}.
$$

{% sidenote() %}
The operation is defined on sets, but I'm talking about shapes.
A shape is really just a kind of set — the set of all points contained by it.
{% end %}

A more intuitive way to understand this operation in the context of solid
shapes (i.e. ones without holes in them) is that we're taking one shape,
sweeping it along the edge of another shape, and making the outer edge of the
swept area the new shape's boundary.

![Illustration of sweeping a circle along the edges of a
triangle](minkowski.png)

Cool. How would we use this in collision detection? From what we've learned so
far, we need a projection operation and a set of possible axes for the
separating axis test. As it turns out, projecting a Minkowski sum of two shapes
just means projecting each shape and summing the results! When one of the
shapes is a circle and its projection is thus independent of axis, this is as
simple as projecting the polygon part and adding the circle's radius.

As far as possible separating axes go, this adds one: the one between the
closest points on the two shapes. Determining what the closest points are isn't
a trivial matter, but before we get to that another digression is in order.

{% sidenote() %}
Replace addition with subtraction and you get the Minkowski difference, the
core operation of another collision detection algorithm called
[Gilbert-Johnson-Keerthi](https://en.wikipedia.org/wiki/Gilbert%E2%80%93Johnson%E2%80%93Keerthi_distance_algorithm)
(GJK). I won't cover that one here.
{% end %}

## Contact points

As mentioned earlier, just knowing whether or not two shapes intersect isn't
enough for physics. We also need to know _where_ they intersect, which turns
out to be quite a bit harder of a question to answer.

The first problem we have to tackle is that things don't intersect in real
life, they stop moving into each other as soon as their surfaces touch. We
don't have that luxury here in discrete-time computer land (unless using
continuous collision detection, another thing I won't cover here), so we have
to make some assumptions. A reasonable one here is that two intersecting
objects probably came into contact from the direction where they overlap least.
Thus that should be the direction our physics response should push them in.

![Illustration of two intersecting rectangles with the direction of contact
marked with a red arrow](contact_dir.png)

We can easily find this direction during the separating axis test. The test
finds the amount of overlap between the two shapes in all relevant directions,
and what we're looking for is the direction with least overlap. Thus, all we
need to do is keep track of the axis with the lowest overlap during SAT and set
that as the contact direction at the end.

That's not all though. We're dealing with polygons which have flat edges,
making for a few different contact scenarios.

![Illustration of two rectangles in four different contact
situations](contact_scenarios.png)

Many of these cases involve two parallel edges, where we would naturally like
our physics system to understand there is a contact along the entire
overlapping part of those edges. In other cases (???) there's just one extreme
point. Then there are cases like (???) where it's not clear if the contact
happened at a point or along a surface. And how do we identify these cases to begin with?
The general idea of the shape of the contact area between two shapes is often called
a _contact manifold_. Here's the most robust way I've found for figuring it out in 2D.

{% sidenote() %}
In 3D this is even more complicated, since contacts can not only happen at a
point or along a line segment, but in an area of a plane as well.
{% end %}

### Clipping edges

Most polygon vs. polygon intersections don't involve perfectly parallel edges,
but we can always find the edges that are _closest_ to parallel, and this turns
out to be very useful.

Because the axes tested in the separating axis test all correspond to edges of
these polygons, one of these edges is given directly by the axis of least
overlap (labelled $\hat{\mathbf{a}}$ in the following illustration). This edge
is sometimes called the _reference edge_. The other shape's edge closest to
parallel with the reference edge, sometimes called the _incident edge_, can be
found by looping over that shape's edges and picking the one whose normal
vector's dot product with $\hat{\mathbf{a}}$ is lowest.

![Illustration of two overlapping rectangles and the reference and incident
edges of the intersection](edges.png)

The first question to ask about these edges is: do they intersect? If they do,
we can conclude this is probably not an edge-to-edge collision. For our contact
manifold, then, we say the point at the far end of the incident edge collided
with the closest point to it on the reference edge.

![Illustration of two intersecting edges and the resulting points of
contact](point_of_contact.png)

If, on the other hand, the edges do not intersect, we decide this is a contact
along a line segment. We can define that line segment by examining the
projection of the incident edge onto the reference edge as illustrated here:

![Illustration of three different cases of nonintersecting edges and the
corresponding line segments of contact](line_of_contact.png)

The separating axis test should rule out all cases that don't look like one of
these, but in practice there's another possible case where the projection of
the incident edge lies entirely outside of the reference edge due to floating
point inaccuracy. It's also possible the clip would give a line segment, but
the incident edge turns out to be entirely outside the reference shape. In both
these cases we can report that no collision happened.

{% sidenote() %}
It takes a bit of a math workout to actually do the calculations illustrated
here. I'll put that at the end as an appendix for those interested.
{% end %}

A separating axis test followed by this edge clip technique is a robust way to
generate contact manifolds for any pair of polygons. With polygon-circle sums
it's not quite as simple, but we now have all the building blocks for the full
algorithm.

{% sidenote() %}
Note that this isn't strictly speaking a _correct_ solution, in fact such a
thing is impossible (at least without continuous techniques), as we're in a
physically incorrect situation to begin with. This is just a reasonable guess
that tends to give well-behaved results.
{% end %}

## The rounded polygon algorithm

Finally, the thing we've been building towards for the last, like, several
hundred words. A general algorithm to detect collisions and compute contact
manifolds for any pair of polygon-circle Minkowski sums. First, let's make up
some terms to make this easier to explain.

![Illustration of a rounded polygon with parts of it highlighted and
named](sum_parts.png)

The polygon component of the Minkowski sum is the _inner polygon_ and its edges
the _inner edges_. The edges of the sum shape are the _outer edges_ and between
them are the _corner circles_.

Recall that the possible separating axes between the two shapes are the axes
defined by the inner polygons, plus one more axis between the closest points on
each shape's boundary. The algorithm I came up with goes like this:

1. Perform a separating axis test on all the axes of the inner polygons. If an
   axis with no overlap is found, stop and return no contact.
2. Pick a reference and incident edge from the outer edges of each shape,
   and perform the clip operation discussed earlier.
3. Depending on the result of the clip:
   - If it's line segment contact, stop and return it.
     ![Illustration of a line segment contact](result_line_seg.png)
   - If it's a point contact, return the farthest point in the axis direction on the
     incident shape's corner circle.
     ![Illustration of a point contact derived from the edge clip](result_point_early.png)
   - If it's no contact, continue to step 4.
4. If neither of the shapes has a circle component, stop and return no contact.
5. Get the endpoint of the **inner** incident edge and the closest point to it
   on the **inner** reference edge. Check if the distance between these points
   is less than the sum of the shapes' circle components. If so, return a point
   contact, otherwise, return no contact.
   ![Illustration of two different point contacts and one no-contact that would
result from this step of the algorithm](result_point_late.png)

{% sidenote() %}
Step 5 corresponds to a separating axis test on the final axis between the
closest points on the shapes.
{% end %}

In the case that both shapes are simple polygons without a circle component,
this simplifies to the separating axis test plus edge clip defined earlier. In
the case that there's at least one shape with a circle component, it covers
every possible separating axis including the one between the closest points on
the two shapes, and understands line segment contacts between edges of the
shapes. The part that's a little clever (if I do say so myself) is finding the
closest points as a byproduct of the edge clip before finishing the separating
axis test.

The original motivation for this collision detection rework was to make it
generic, and fortunately making this slightly more complex algorithm generic
wasn't any more difficult than doing that to the original polygon-only
algorithm. It merely added a couple of extra steps. I'll talk about what this
entailed a little later.

That's all there is to collision detection between two shapes like this.
Here's our reward for making it all the way here — a nice gif of shapes
colliding with each other using this algorithm:

![Screen recording of a scene with various rounded shapes moving around](result.gif)

## Other operations

This is great, but it's not the end of the story. There are still a few other
things we need to do with these shapes. For one, in the previous section I
completely ignored the case where one of the shapes is a circle. We also want
some other queries for gameplay purposes, and there are some physical
properties we need to extract from these shapes.

### Point queries

It's often very useful to know whether or not a point is inside a shape. For
instance, I use a query like this to implement selecting objects with the mouse
cursor. Sometimes if the answer is no, you might still want to know where the
closest point on the shape is. For circles and rectangles this question is
trivial to answer, but less so for other shapes. Here's an algorithm that works
for any shape defined as a polygon-circle sum like we've been doing and finds
two things: the closest point on the shape's boundary, as well as whether the
queried point is inside or outside of the shape.

{% sidenote() %}
If the shape was a simple polygon without a circle component and we just wanted
to know whether $\mathbf{p}$ is inside or outside of it, we wouldn't need to
get the closest point. We could simply do a separating axis test using the edge
normals. With the circle component added, however, we need the closest point
for the same reason we needed it in the SAT earlier, so we might as well
compute it even if we only want the yes/no result.
{% end %}

Let's define a bit of notation first to make this easier to write. We'll be
operating on edges of the shape's inner polygon, and each edge is defined as a
starting point $\mathbf{s}$, a direction $\hat{\mathbf{d}}$ and a length $l$.
Each edge also has a normal $\hat{\mathbf{n}}$ which is perpendicular to
$\hat{\mathbf{d}}$ and points outward. Let's call the point we're querying for
$\mathbf{p}$ and the radius of the shape's circle component $r_c$.

![Illustration of an edge line segment and its parameters](edge_params.png)

Now for the algorithm.

1. Project $\mathbf{p}$ onto each inner edge with
   $t_{proj} = (\mathbf{s} - \mathbf{p}) \cdot \hat{\mathbf{d}}$
   and clamp it to the edge's bounds with
   $t_{c} = \text{clamp}(t_{proj}, 0, l)$.
   The closest point to $\mathbf{p}$ on the edge is then
   $\mathbf{p}_{proj} = s + t_{c} \cdot \hat{\mathbf{d}}$.
2. Find the edge where the distance $||\mathbf{p} - \mathbf{p}_{proj}||$
   is the smallest. The variables in the following steps refer to this edge and
   the point projected to it.
3. If $0 \leq t_{proj} \leq l$ (i.e. the projected point lies inside the edge,
   no clamping necessary), $\mathbf{p}$ might be inside the inner polygon. We
   need to know if this is the case, so check against the edge normal:
   $\mathbf{p}$ is inside the polygon if and only if
   $(\mathbf{s} - \mathbf{p}) \cdot \hat{\mathbf{n}} \leq 0$.
4. We now have the closest point on the inner polygon's boundary. To get the
   closest point on the sum shape's boundary, first define the direction
   from the projected point to the query point,
   $\hat{\mathbf{d}}_p = \frac{\mathbf{p} - \mathbf{p}_{proj}}{||\mathbf{p} - \mathbf{p}_{proj}||}$.
   Then,
   - If $\mathbf{p}$ is inside the inner polygon, return "inside" and the point
     $\mathbf{p}_{proj} - r_c\hat{\mathbf{d}}_p$
   - If not, return the point
     $\mathbf{p}_{proj} + r_c\hat{\mathbf{d}}_p$
     and "inside" if $||\mathbf{p} - \mathbf{p}_{proj}|| \leq r_c$,
     "outside" otherwise.

{% sidenote() %}
The step 3 check for being inside the inner polygon is necessary not just to
get the correct direction vector to add in step 4, but also because the
distance check at the end of step 4 would miss points that are too close to the
polygon's center (and thus too far from its edges).
{% end %}

That's all. TL;DR: first compute the closest point on the inner polygon's boundary,
then expand towards the query point until we reach the sum shape's boundary.
While you do that, see if the query point is inside the shape.

{% sidenote() %}
While writing this post I realized I had made a mistaken assumption in my
original version of this algorithm, and reimplemented the whole thing. Fixing
bugs by writing blogs! 😛
{% end %}

This information actually allows us to implement collision detection between
these sum shapes and circles. Simply compute the closest point to the
circle center, check if it's inside the circle, and you're done!

### Raycasts and spherecasts

todos:

- implementation details: ~~closest point~~, edge clip math, other operations needed
- raycast / spherecast discussion, AABB tree mention maybe?
- area and moment of inertia math
- performance

[starframe]: https://github.com/m0lentum/starframe
[sht]: https://en.wikipedia.org/wiki/Hyperplane_separation_theorem
[convex]: https://en.wikipedia.org/wiki/Convex_set
[metanet-tut]: https://www.metanetsoftware.com/2016/n-tutorial-a-collision-detection-and-response
[minkowski]: https://en.wikipedia.org/wiki/Minkowski_addition
