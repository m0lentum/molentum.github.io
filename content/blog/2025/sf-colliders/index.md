+++
title = "Rounding collider corners"
draft = true
date = 2025-01-04
slug = "rounding-collider-corners"
[taxonomies]
tags = ["starframe", "physics", "collision"]
[extra]
use_katex = true
+++

Back in 2022 I entirely rewrote one of the most complicated parts of [Starframe],
the collision detection system.
A notable feature of the new system is the ability to give any shape rounded corners.
I also wrote most of this post back then, but things happened and it was left unfinished.
Here it is now, two years later.
Better late than never I suppose.

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
[**convex**][convex] shapes intersect if and only if you cannot draw a straight
line between them that doesn't touch either of them.

{% sidenote() %}
It's a line in 2D, plane in 3D, etc. This works in any dimension, which is why
the general theorem calls it a hyperplane.
{% end %}

![Illustration of two pairs of shapes, one intersecting and one not, and a line
drawn between the non-intersecting ones.](sat_line.svg)

Now, how do we find such a line (or the lack thereof)? The first step is to
consider all possible _directions_ the line can go in. For every such
direction, there is a perpendicular _axis_.

![The previous illustration with the axis perpendicular to the line
added.](sat_axis.svg)

With this we can transform the question "can a line in this direction fit between the shapes?"
into "is there room between the shapes when measured along this axis?".
This is a question we can actually answer by projecting each shape onto the axis!

![The previous illustration with projections of the shapes to the
axis.](sat_proj.svg)

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

![Illustration of a rectangle and a triangle, along with their potential
separating axes.](sat_sep.svg)

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
The tutorial has some fantastic interactive visualizations made with Flash,
which isn't available in browsers anymore, but I hear [Ruffle] can still run them.

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
<span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi>A</mi></mrow><annotation encoding="application/x-tex">A</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6833em;"></span><span class="mord mathnormal">A</span></span></span></span> and <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi>B</mi></mrow><annotation encoding="application/x-tex">B</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6833em;"></span><span class="mord mathnormal" style="margin-right:0.05017em;">B</span></span></span></span> is the set containing every sum of two elements from <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi>A</mi></mrow><annotation encoding="application/x-tex">A</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6833em;"></span><span class="mord mathnormal">A</span></span></span></span> and <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi>B</mi></mrow><annotation encoding="application/x-tex">B</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6833em;"></span><span class="mord mathnormal" style="margin-right:0.05017em;">B</span></span></span></span>,

<span class="katex-display"><span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><semantics><mrow><mi>A</mi><mo>+</mo><mi>B</mi><mo>=</mo><mo stretchy="false">{</mo><mi>a</mi><mo>+</mo><mi>b</mi><mtext> </mtext><mi mathvariant="normal">∣</mi><mtext> </mtext><mi>a</mi><mo>∈</mo><mi>A</mi><mo separator="true">,</mo><mi>b</mi><mo>∈</mo><mi>B</mi><mo stretchy="false">}</mo><mi mathvariant="normal">.</mi></mrow><annotation encoding="application/x-tex">
A + B = \{ a + b \,|\, a \in A, b \in B \}.
</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7667em;vertical-align:-0.0833em;"></span><span class="mord mathnormal">A</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">+</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:0.6833em;"></span><span class="mord mathnormal" style="margin-right:0.05017em;">B</span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">=</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mopen">{</span><span class="mord mathnormal">a</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">+</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mord mathnormal">b</span><span class="mspace" style="margin-right:0.1667em;"></span><span class="mord">∣</span><span class="mspace" style="margin-right:0.1667em;"></span><span class="mord mathnormal">a</span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">∈</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:0.8889em;vertical-align:-0.1944em;"></span><span class="mord mathnormal">A</span><span class="mpunct">,</span><span class="mspace" style="margin-right:0.1667em;"></span><span class="mord mathnormal">b</span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">∈</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mord mathnormal" style="margin-right:0.05017em;">B</span><span class="mclose">}</span><span class="mord">.</span></span></span></span></span>

A more intuitive way to understand this operation in the context of shapes
is that we're taking one shape,
sliding its center of mass along the boundary of another shape,
and making the outer edge of the covered area the new shape's boundary.

![Illustration of sweeping a circle along the edges of a
triangle](minkowski.svg)

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
Replace addition with subtraction and you get the Minkowski difference, 
a crucial operation in another collision detection algorithm called
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
marked with a red arrow](contact_dir.svg)

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
overlap (labelled <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mover accent="true"><mi mathvariant="bold">a</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\hat{\mathbf{a}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7079em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.7079em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">a</span></span><span style="top:-3.0134em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.25em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span> in the following illustration). This edge
is sometimes called the _reference edge_. The other shape's edge closest to
parallel with the reference edge, sometimes called the _incident edge_, can be
found by looping over that shape's edges and picking the one whose normal
vector's dot product with <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mover accent="true"><mi mathvariant="bold">a</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\hat{\mathbf{a}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7079em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.7079em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">a</span></span><span style="top:-3.0134em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.25em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span> is lowest.

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

A separating axis test followed by this edge clip technique is a robust way to
generate contact manifolds for any pair of polygons. With polygon-circle sums
it's not quite as simple, but we now have all the building blocks for the full
algorithm.

{% sidenote() %}
Note that this isn't strictly speaking a _correct_ solution from a physics point of view,
in fact such a thing is impossible (at least without continuous techniques),
as we're in a physically incorrect situation to begin with.
This is just a reasonable guess that tends to give well-behaved results.
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
It's probably not the only thing you want to do with these shapes, though.
Let's look at a couple more questions 
that collision detection systems commonly need to answer.

## Other operations

So what are the questions that we haven't aswered yet?
For one, in the previous section I
ignored the case where one of the shapes is just a circle.
We also want some other queries for gameplay purposes,
namely closest points and raycasts.

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
to know whether <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> is inside or outside of it, we wouldn't need to
get the closest point. We could simply do a separating axis test using the edge
normals. With the circle component added, however, we need the closest point
for the same reason we needed it in the SAT earlier, so we might as well
compute it even if we only want the yes/no result.
{% end %}

Let's define a bit of notation first to make this easier to write. We'll be
operating on edges of the shape's inner polygon, and each edge is defined as a
starting point <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">s</mi></mrow><annotation encoding="application/x-tex">\mathbf{s}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.4444em;"></span><span class="mord mathbf">s</span></span></span></span>, a direction <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\hat{\mathbf{d}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.9579em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span> and a length <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi>l</mi></mrow><annotation encoding="application/x-tex">l</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6944em;"></span><span class="mord mathnormal" style="margin-right:0.01968em;">l</span></span></span></span>.
Each edge also has a normal <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mover accent="true"><mi mathvariant="bold">n</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\hat{\mathbf{n}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7079em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.7079em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">n</span></span><span style="top:-3.0134em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.25em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span> which is perpendicular to
<span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\hat{\mathbf{d}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.9579em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span> and points outward. Let's call the point we're querying for
<span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> and the radius of the shape's circle component <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mi>r</mi><mi>c</mi></msub></mrow><annotation encoding="application/x-tex">r\_c</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.5806em;vertical-align:-0.15em;"></span><span class="mord"><span class="mord mathnormal" style="margin-right:0.02778em;">r</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:-0.0278em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">c</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.15em;"><span></span></span></span></span></span></span></span></span></span>.

![Illustration of an edge line segment and its parameters](edge_params.png)

Now for the algorithm.

1. Project <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> onto each inner edge with
   <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mi>t</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mo>=</mo><mo stretchy="false">(</mo><mi mathvariant="bold">s</mi><mo>−</mo><mi mathvariant="bold">p</mi><mo stretchy="false">)</mo><mo>⋅</mo><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">t\_{proj} = (\mathbf{s} - \mathbf{p}) \cdot \hat{\mathbf{d}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.9012em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathnormal">t</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">=</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mopen">(</span><span class="mord mathbf">s</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">−</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mord mathbf">p</span><span class="mclose">)</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">⋅</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:0.9579em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span>
   and clamp it to the edge's bounds with
   <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mi>t</mi><mi>c</mi></msub><mo>=</mo><mtext>clamp</mtext><mo stretchy="false">(</mo><msub><mi>t</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mo separator="true">,</mo><mn>0</mn><mo separator="true">,</mo><mi>l</mi><mo stretchy="false">)</mo></mrow><annotation encoding="application/x-tex">t\_{c} = \text{clamp}(t_{proj}, 0, l)</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7651em;vertical-align:-0.15em;"></span><span class="mord"><span class="mord mathnormal">t</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">c</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.15em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">=</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:1.0361em;vertical-align:-0.2861em;"></span><span class="mord text"><span class="mord">clamp</span></span><span class="mopen">(</span><span class="mord"><span class="mord mathnormal">t</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mpunct">,</span><span class="mspace" style="margin-right:0.1667em;"></span><span class="mord">0</span><span class="mpunct">,</span><span class="mspace" style="margin-right:0.1667em;"></span><span class="mord mathnormal" style="margin-right:0.01968em;">l</span><span class="mclose">)</span></span></span></span>.
   The closest point to <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> on the edge is then
   <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mo>=</mo><mi>s</mi><mo>+</mo><msub><mi>t</mi><mi>c</mi></msub><mo>⋅</mo><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\mathbf{p}\_{proj} = s + t_{c} \cdot \hat{\mathbf{d}}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7305em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathbf">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">=</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:0.6667em;vertical-align:-0.0833em;"></span><span class="mord mathnormal">s</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">+</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:0.7651em;vertical-align:-0.15em;"></span><span class="mord"><span class="mord mathnormal">t</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">c</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.15em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">⋅</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:0.9579em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span></span></span></span>.
2. Find the edge where the distance <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="normal">∣</mi><mi mathvariant="normal">∣</mi><mi mathvariant="bold">p</mi><mo>−</mo><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mi mathvariant="normal">∣</mi><mi mathvariant="normal">∣</mi></mrow><annotation encoding="application/x-tex">||\mathbf{p} - \mathbf{p}\_{proj}||</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mord">∣∣</span><span class="mord mathbf">p</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">−</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1.0361em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathbf">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mord">∣∣</span></span></span></span>
   is the smallest. The variables in the following steps refer to this edge and
   the point projected to it.
3. If <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mn>0</mn><mo>≤</mo><msub><mi>t</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mo>≤</mo><mi>l</mi></mrow><annotation encoding="application/x-tex">0 \leq t\_{proj} \leq l</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.7804em;vertical-align:-0.136em;"></span><span class="mord">0</span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">≤</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:0.9221em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathnormal">t</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">≤</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:0.6944em;"></span><span class="mord mathnormal" style="margin-right:0.01968em;">l</span></span></span></span> (i.e. the projected point lies inside the edge,
   no clamping necessary), <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> might be inside the inner polygon. We
   need to know if this is the case, so check against the edge normal:
   <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> is inside the polygon if and only if
   <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mo stretchy="false">(</mo><mi mathvariant="bold">s</mi><mo>−</mo><mi mathvariant="bold">p</mi><mo stretchy="false">)</mo><mo>⋅</mo><mover accent="true"><mi mathvariant="bold">n</mi><mo>^</mo></mover><mo>≤</mo><mn>0</mn></mrow><annotation encoding="application/x-tex">(\mathbf{s} - \mathbf{p}) \cdot \hat{\mathbf{n}} \leq 0</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mopen">(</span><span class="mord mathbf">s</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">−</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mord mathbf">p</span><span class="mclose">)</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">⋅</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:0.8438em;vertical-align:-0.136em;"></span><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.7079em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">n</span></span><span style="top:-3.0134em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.25em;"><span class="mord">^</span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">≤</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:0.6444em;"></span><span class="mord">0</span></span></span></span>.
4. We now have the closest point on the inner polygon's boundary. To get the
   closest point on the sum shape's boundary, first define the direction
   from the projected point to the query point,
   <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover><mi>p</mi></msub><mo>=</mo><mfrac><mrow><mi mathvariant="bold">p</mi><mo>−</mo><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub></mrow><mrow><mi mathvariant="normal">∣</mi><mi mathvariant="normal">∣</mi><mi mathvariant="bold">p</mi><mo>−</mo><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mi mathvariant="normal">∣</mi><mi mathvariant="normal">∣</mi></mrow></mfrac></mrow><annotation encoding="application/x-tex">\hat{\mathbf{d}}\_p = \frac{\mathbf{p} - \mathbf{p}_{proj}}{||\mathbf{p} - \mathbf{p}_{proj}||}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:1.244em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">p</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">=</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:1.458em;vertical-align:-0.5423em;"></span><span class="mord"><span class="mopen nulldelimiter"></span><span class="mfrac"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.9157em;"><span style="top:-2.655em;"><span class="pstrut" style="height:3em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mtight">∣∣</span><span class="mord mathbf mtight">p</span><span class="mbin mtight">−</span><span class="mord mtight"><span class="mord mathbf mtight">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3281em;"><span style="top:-2.357em;margin-left:0em;margin-right:0.0714em;"><span class="pstrut" style="height:2.5em;"></span><span class="sizing reset-size3 size1 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2819em;"><span></span></span></span></span></span></span><span class="mord mtight">∣∣</span></span></span></span><span style="top:-3.23em;"><span class="pstrut" style="height:3em;"></span><span class="frac-line" style="border-bottom-width:0.04em;"></span></span><span style="top:-3.5073em;"><span class="pstrut" style="height:3em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathbf mtight">p</span><span class="mbin mtight">−</span><span class="mord mtight"><span class="mord mathbf mtight">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3281em;"><span style="top:-2.357em;margin-left:0em;margin-right:0.0714em;"><span class="pstrut" style="height:2.5em;"></span><span class="sizing reset-size3 size1 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2819em;"><span></span></span></span></span></span></span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.5423em;"><span></span></span></span></span></span><span class="mclose nulldelimiter"></span></span></span></span></span>.
   Then,
   - If <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="bold">p</mi></mrow><annotation encoding="application/x-tex">\mathbf{p}</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.6389em;vertical-align:-0.1944em;"></span><span class="mord mathbf">p</span></span></span></span> is inside the inner polygon, return "inside" and the point
     <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mo>−</mo><msub><mi>r</mi><mi>c</mi></msub><msub><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover><mi>p</mi></msub></mrow><annotation encoding="application/x-tex">\mathbf{p}\_{proj} - r_c\hat{\mathbf{d}}_p</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.8694em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathbf">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">−</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1.244em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathnormal" style="margin-right:0.02778em;">r</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:-0.0278em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">c</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.15em;"><span></span></span></span></span></span></span><span class="mord"><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">p</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span></span></span></span>
   - If not, return the point
     <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mo>+</mo><msub><mi>r</mi><mi>c</mi></msub><msub><mover accent="true"><mi mathvariant="bold">d</mi><mo>^</mo></mover><mi>p</mi></msub></mrow><annotation encoding="application/x-tex">\mathbf{p}\_{proj} + r_c\hat{\mathbf{d}}_p</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:0.8694em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathbf">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">+</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1.244em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathnormal" style="margin-right:0.02778em;">r</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:-0.0278em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">c</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.15em;"><span></span></span></span></span></span></span><span class="mord"><span class="mord accent"><span class="vlist-t"><span class="vlist-r"><span class="vlist" style="height:0.9579em;"><span style="top:-3em;"><span class="pstrut" style="height:3em;"></span><span class="mord mathbf">d</span></span><span style="top:-3.2634em;"><span class="pstrut" style="height:3em;"></span><span class="accent-body" style="left:-0.0833em;"><span class="mord">^</span></span></span></span></span></span></span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">p</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span></span></span></span>
     and "inside" if <span class="katex"><span class="katex-mathml"><math xmlns="http://www.w3.org/1998/Math/MathML"><semantics><mrow><mi mathvariant="normal">∣</mi><mi mathvariant="normal">∣</mi><mi mathvariant="bold">p</mi><mo>−</mo><msub><mi mathvariant="bold">p</mi><mrow><mi>p</mi><mi>r</mi><mi>o</mi><mi>j</mi></mrow></msub><mi mathvariant="normal">∣</mi><mi mathvariant="normal">∣</mi><mo>≤</mo><msub><mi>r</mi><mi>c</mi></msub></mrow><annotation encoding="application/x-tex">||\mathbf{p} - \mathbf{p}\_{proj}|| \leq r_c</annotation></semantics></math></span><span class="katex-html" aria-hidden="true"><span class="base"><span class="strut" style="height:1em;vertical-align:-0.25em;"></span><span class="mord">∣∣</span><span class="mord mathbf">p</span><span class="mspace" style="margin-right:0.2222em;"></span><span class="mbin">−</span><span class="mspace" style="margin-right:0.2222em;"></span></span><span class="base"><span class="strut" style="height:1.0361em;vertical-align:-0.2861em;"></span><span class="mord"><span class="mord mathbf">p</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.3117em;"><span style="top:-2.55em;margin-left:0em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mtight"><span class="mord mathnormal mtight">p</span><span class="mord mathnormal mtight">ro</span><span class="mord mathnormal mtight" style="margin-right:0.05724em;">j</span></span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.2861em;"><span></span></span></span></span></span></span><span class="mord">∣∣</span><span class="mspace" style="margin-right:0.2778em;"></span><span class="mrel">≤</span><span class="mspace" style="margin-right:0.2778em;"></span></span><span class="base"><span class="strut" style="height:0.5806em;vertical-align:-0.15em;"></span><span class="mord"><span class="mord mathnormal" style="margin-right:0.02778em;">r</span><span class="msupsub"><span class="vlist-t vlist-t2"><span class="vlist-r"><span class="vlist" style="height:0.1514em;"><span style="top:-2.55em;margin-left:-0.0278em;margin-right:0.05em;"><span class="pstrut" style="height:2.7em;"></span><span class="sizing reset-size6 size3 mtight"><span class="mord mathnormal mtight">c</span></span></span></span><span class="vlist-s">​</span></span><span class="vlist-r"><span class="vlist" style="height:0.15em;"><span></span></span></span></span></span></span></span></span></span>,
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
original version of this algorithm, and reimplemented the whole thing.
Blog-mediated rubber duck debugging! 😛
{% end %}

This information actually allows us to implement collision detection between
these sum shapes and circles. Simply compute the closest point to the
circle center, check if it's inside the circle, and you're done!

### Raycasts and spherecasts

{% sidenote() %}
This is where the part I wrote in 2022 ends.
I hope you'll forgive me for cutting some corners
from here on to get the post finished in reasonable time
and move on with my life 😅
{% end %}

Another important question game developers need to ask their physics engine
is where the closest thing in some specific direction is.
A raycast is a way to answer this question:
given a starting point and a direction,
walk along a line defined by these parameters
and return the first object touched.
This information can be applied in myriad creative ways,
from shots and lines of sight in a shooter game
to keeping track of the ground under a hovercraft.

Sometimes you might have small gaps between things
where a thin ray can get lost.
What if you want something that can't pass through tiny gaps?
A simple solution (at least conceptually)
is, instead of just walking a point along the ray,
make it a shape with some nonzero width instead
and find the first thing that shape runs into.
This is called a _shapecast_.

Attentive readers may find a resemblance here to an idea we've talked about quite a bit in this post
(hint: it starts with M and ends with 'inkowski sum').
A shapecast is like a Minkowski sum of a ray and a shape.
And the objects we're looking for with the cast are Minkowski sums of polygons and circles.
Turns out we can move terms of these sums around,
and this test can be expressed as a regular raycast
against the Minkowski sum of the target shape with the shape being cast!

How convenient. We already have a way to add a circle to a polygon,
so if we want to do a shapecast with a circle (called a spherecast) in this framework,
we just need to add the circle to the shapes we're testing against
and run a plain old raycast.
Neat! So let's take a look at how to raycast against a polygon-circle sum.
This isn't as easy as raycasting against a simple polygon,
but getting spherecasts for free is a heck of a benefit.

{% sidenote() %}
This isn't quite the whole story when using a spatial structure
such as a grid or a tree to speed up the search,
as the shape needs to traverse this structure.
Explaining this in detail is out of this post's scope,
but I'm using an AABB tree where this redistributed Minkowski sum idea can also be applied —
simply expand each node by the circle's radius and traverse a regular ray through it.
{% end %}

First, to check if the ray intersects with a shape _somewhere_,
we can make use of the fact that we're in 2D space
and use a trick we already know.
The only separating axis between a ray and anything in 2D
is the one perpendicular to the ray,
so we can find out if the ray misses or hits by running a separating axis test
on the ray's origin point and the target shape along this axis.

If the test says we have a hit, we once again find
that the harder part is finding the point where the ray intersected the shape.
It's not too complicated, just a bit of work.
First, note that the boundaries of our shapes are composed of only two kinds of things,
circle arcs and line segments.

![Illustration of a shape's boundary decomposed into arcs and line segments.](shape_boundary.svg)

So all we really need is a ray-line segment and ray-circle intersection test.
We could simply check against every boundary segment
and pick the closest intersection found,
but with a bit of cleverness we can skip all but at most one of the circle arcs.
Here's what my implementation does:
- Start by considering the polygon obtained by extending the outer edges until they meet.
  Check for intersection against each of the edges and find the closest one.
- If this intersection is inside the part of the segment
  that's part of the actual shape, we're done.
  Return this intersection point.
- Otherwise, we now know which side of the edge we've overshot,
  which tells us which circle arc we must have hit instead.
  Run a ray-circle test against this circle and return the result.

TODO each of these steps probably needs a picture

{% sidenote() %}
Note that the endpoints of the boundary line segments
are not just the inner polygon's edges extruded out in the normal direction.
I'll leave computing the exact endpoints
as a trigonometry exercise for the reader.
{% end %}

And that's how you compute a ray-shape intersection, with one caveat:
Special cases are needed for circles and capsules,
since the construction of the boundary here
relies on two different edges starting from each vertex.
I won't go over the details here, but the ideas are the same.

TODO finish this section, mention what information is needed from colliders now
(do I say that anywhere yet?), add a teaser image to the start and animation to the end,
then we're done here methinks

## Conclusion

We've looked at three fundamental operations of a collision detection system —
shape intersections, closest point queries, and ray-/shapecasts,
and how I've implemented them for shapes expressed as Minkowski sums
of convex polygons and circles.
Most of the complexity comes from finding points of contact,
which are not always important but are entirely crucial for realistic physics.

Here's a little animation of this system in action
as a reward for making it this far,
also showcasing the graphics and lighting I've been working on lately.
I know better than to promise blog posts now,
but I'm hoping do a bit of writing about what's been going on there soon.

![Various shapes with rounded corners falling into a pile.
Some of the shapes are emitting light, while others are absorbing it,
casting colored shadows.](TODO.gif)

I've left out many mathematical details to save time.
If you'd like to see how to compute the line intersections needed in edge clipping and raycasting,
or how to compute the area and moment of inertia of these shapes for the purposes of physics
(moment of inertia in particular is an interesting exercise in surface integrals),
feel free to ping me on Mastodon
and I'll be happy to dig up my old notes (I think I still have them somewhere..)
to post as an appendix.

[starframe]: https://github.com/m0lentum/starframe
[sht]: https://en.wikipedia.org/wiki/Hyperplane_separation_theorem
[convex]: https://en.wikipedia.org/wiki/Convex_set
[metanet-tut]: https://www.metanetsoftware.com/2016/n-tutorial-a-collision-detection-and-response
[ruffle]: https://ruffle.rs/
[minkowski]: https://en.wikipedia.org/wiki/Minkowski_addition
