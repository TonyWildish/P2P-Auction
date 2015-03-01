
# The algorithm in a nutshell:

From *Design, Analysis and Simulation of the Progressive Second Price Auction For Network Bandwidth Sharing*

Let **_Q_** be the network bandwidth that is to be shared.

There are two design aspects: the message process that allows an allocation to be defined, and a Nash implementation, which follows allocation rules designed to drive the players to a satisfactory equilibrium.

## The message process:
To make this scalable for use on the WAN, we make a couple of design decisions:
- messages must be as small as possible, yet still be complete enough that the auction can proceed based on the messages alone (no a-priori knowledge of external factors etc)
- computation at the auction-centre must be minimised, to allow a rapid response, where 'rapid' has yet to be defined.

Let **_Q_** represent the resource to be shared, i.e. the network bandwidth.

Let **_I_** be the set of players, \{1,...,*I*\}, participating in the auction.

Player _i_'s bid is s_*i* = ( q_*i*, p_*i*), where q_*i* represents the quantity the player wants (0 <= q_*i* <= **_Q_**) and p_*i* represents the *unit* price they are willing to pay ( 0 <= p_*i* <= infinity).

Let s = (s_*1*, s_*2*, ..., s_*I*) be the bid profile.

Define s_*-i* to be the bid profile with player *i*'s bid removed.

An **allocation rule** maps **s = (p,q)** to **A(s) = (a(s),c(s))** where **a(s)** is the quantity allocated and **c(s)** is the cost charged for the allocation.

(Note that **c** is the total cost, while **p** is the price per unit)

An allocation is **feasible** if:
- the sum over players of **a_*i*(s)** is less than the total, **_Q_** (you don't over-allocate the resource)
- for all players *i*, a_*i*(s) <= q_*i* (each player gets no more than they asked for)
- for all players *i*, c_*i*(s) <= p_*i* . q_*i* (the total cost does not exceed what each player is willing to pay)

N.B. A typical auction, in which one player gets the entire resource, has a_*i* = **_Q_** for one player and a_*i* = 0 for all other players.

By using the 'Revelation principle', we could restrict ourselves to the case where each user specifies a function theta_*i* which maps points in the interval [0,**_Q_**] to a price from 0 to infinity, along with their total budget. This mapping represents the 'type' of the user.

However, there are an infinite number of types, in that there are an infinite number of curves mapping an allocation to a price within a given budget.

Since we're using a 2-dimensional message space (q,p), we can't apply the revelation principle. So, we posit an allocation rule, then show it has the desired equilibrium properties. This is equivalent to guessing the answer then proving ourselves right.

## The Allocation Rule

For **_y_ >= 0**, define:

**Qbar_i(y, s_-i)** = **Q - sum over [k != i, p_k >= y] q_k**

i.e. **Qbar_i(y, s_-i)** is the total resource minus the sum of requested resources for all players *i* who bid more than *y*.

(N.B. Have to understand the square-bracket notation with the superscript '+')

also define:

**Q_i(y, s_-i)** = *limit as eta descends to y of* **Qbar(eta, s_-i)**

Then we can define the **PSP Allocation Rule** as a pair of functions, one for the allocation, one for the cost:

- **a_*i*(s)** = *minimum(* q_*i*, **Qbar_i(p_*i*,s_-i)** *)*
- **c_*i*(s)** = *sum over j != i of **p_*j* ** ( **a_*j*(0; s_-i)** - **a_*j*(s_i; s_-i)** )

i.e.

- the allocation is the minimum of what the player asked for and what is left after all other players who bid more than player *i* get their allocation. Put more simply, player *i* gets what's left after higher-paying players are satisfied, up to the limit they requested.
- the cost they pay is the sum over all other players of the price the other player offerred times the difference between the actual allocation and the allocation they would have received if player *i* had not participated. Put differently, for all other players, add up the amount they lose because *i* exists multiplied by the price they were willing to pay, and charge *i* that amount.

N.B. For a given (fixed) opponent profile *s_i*, **Q_i(p_*i*,s_-i)** is the maximum quantity available at price *p_i*. This means that player *i* pays the price that exactly compensates the bids of players who are excluded by *i*'s presence. This is an example of an **exclusion compensation principle**.

Note 1:
This is equivalent to saying that a bid of *(p_i,q_i)* represents a continuous valuation function of slope *p_i* in the vicinity of *q_i*. This effectively transforms the 2-dimensional bid into a continuous range, which is why the revelation principle holds in practice.

The cost *c_i* increases with allocation similarly to progressive income tax, with higher allocations crossing thresholds into higher price-bands for the fraction above that threshold. This is a natural extension of Vickrey auctions, in which an indivisible item is sold to the highest bidder at a price given by the second-highest bid. This follows from the allocation rule if the entire item goes to one player only.

Vickrey auctions have many useful properties, including a truthful equilibrium, in which all players bid their true valuation. The PSP preserves that property, which leads to a favourable Nash equilibrium.

Note 2:
When two players bid the same price and the sum of their requests exceeds what is available, the allocation rule punishes them both. E.g., set **_Q_** = 100, **s1** = (4,60) and **s2** = (4,10). The allocation would then be 30 to player 1 (the minimum of 60 and 100-70), and 40 to player 2, leaving 30 unallocated.

One could choose to allocate the excess proportionally, or equally, assuming there is no player 3 to give it to. In practise it doesn't matter, since players will change their bids toget a more favourable outcome which will settle at equilibrium over time.

# Analysis of the algorithm
Computational complexity is dominated by calculating the cost function, which goes as the square of the number of bidders.

Players have a **valuation** of their allocation, **theta_i(a_i(s)) >= 0**, which also gives their utility function, **u_i(s)**, as their valuation minus their cost:

_**u_i(s) = theta_i(a_i(s)) - c_i(s)**_

Players can be constrained by a budget in the range 0 to infinity.

Assume players have elastic demand, by which we mean:

* **theta_i(0) = 0** - their demand for a quantity of zero is zero
* **theta_i** is differentiable
* the derivative of **theta_i** is >= 0, non-increasing, and continuous - in other words player *i* is willing to pay most for their first increment, and progressively less for greater and greater slices..
* as long as the valuation is strictly increasing it must also be strictly concave. However, it is allowed to flatten beyond some point.

This form of elastic demand is just the law of diminshing marginal returns by another name. It can also be justified from information-theoretic considerations, where the value of an allocation can be equated to the level of distortion in (e.g.) video-encoding, where the distortion increases as available bandwidth decreases. Shame that doesn't apply to LHC data-transfer :-(

## Equilibrium of the PSP
PSP can be analysed as a game **(Q,u_1,...u_i,A)** (i.e. the quantity being auctioned, the players' utility functions, and a feasible allocation rule). It can be treated as a strategic game of complete information.

Players re-compute their best response to the current strategy profile of their opponents, this converges to the equilibrium.

A more general case for equilibrium is an **epsilon-Nash** equilibrium, where perfect equilibrium isn't reached but the players come within a small offset, *epsilon*, of the true Nash equilibrium. This can be interpreted as imposing a *bid-fee* on players, they are charged an amount *epsilon* to place a bid. A small epsilon allows closer approach to the true equilibrium, while a larger epsilon reduces the number of iterations to convergence, by discouraging excessive find-tuning of bids.

Can show that, for a fixed opponent profile (_**s\_-i**_), a players' best strategy is truthful. That means setting the bid equal to the marginal valuation, i.e. _**p_i = theta'_i(q_i)**_. This guarantees they will always get within _epsilon > 0_ of their best utility.

Figure 2 of the paper shows this well. To find your bid-price, follow your utility curve along the _**Q**_ axis while the cost at _**Q = q**_ is less than your utility at that point, then at the point where the cost jumps up above your utility, bid that point of your utility curve.

A plot of **(u,p,q)** for a given player shows plateau where the allocation can no longer be increased at the bid-price **p**. Where the bid-price exceeds that of another player, the utility decreases with increasing allocation, because the allocation is taken from the other player, causing the 'social cost' to increase. This is the dis-incentive to players bidding above their valuation.

Note that if the players have linear valuation for the item being sold, and have an infinite budget, then the PSP becomes identical to a second-price auction for a non-divisible item.

**N.B.** It's' possible to devise an allocation rule that takes a true budget, instead of a cost per unit of the item. This transfers the computational load onto the auctioneer, but would reduce the cycles of messaging between payers and auctioneer. Depending on the scalability requirements this may or may not be worth doing. In particular, it's unlikely that the allocation rule would then have a simple closed form, like the PSP does.

Note also that the truthful best response is continuous in the opponent profiles. This follows from the 'staircase' property of the cost function and the fact that the utility function steadily decreases, their intersection moves smoothly.

We can introduce another player, player zero, whose valuation is **theta_0(z) = p_0 * z**. This acts as a 'reserve price', which reduces silliness.

At equilibrium, the marginal valuation for any player is never greater than the bid-price of any ohter player whose allocation is greater than zero. If it were, the first player could take some of that allocation, increasing their utility but also their cost. This means that, at equilibrium, the total value of the players is maximised. I.e. the PSP is 'efficient'.

Efficiency is guaranteed if budgets are infinite, but can be achieved with finite budgets too. If players co-operate, bidding close to what they can actually get, then the price would be **p_0** for all allocations, and the auction can be efficient with reasonable budgets. In general, if there are no players with very high demand and very low budgets, you can get an efficient outcome.

## Simulating the PSP
Can show that efficiency depends only on the second derivative of the valuation, so can use valuations which are parabolic in form:

**theta\_i(z) = k\_i . z . (qbar\_i - z/2) for 0 <= z <= qbar\_i**
**theta\_i(z) = k\_i . qbar\_i^2 / 2 for z > qbar_i**

where **k_i** is positive and **qbar_i** is the line rate (whatever _that_ means!).

This has the form of a rising parabola that then becomes horizontal at its peak.

### Reproducing the simulation results from this paper
Generate a population of users with *qbar_i* uniformly distributed on [50,100]. Generate maximum per-unit prices the players would pay on [10,20]. Note that this corresponds to *theta_i'(0)*, the marginal utility per unit for zero allocation. Give all players a budget of 100, and set the total bandwidth for sale to 100 too.

Let players bid no faster than once per second, and fix *epsilon* at 5. (N.B. Could consider reducing epsilon as equilibrium approaches?)

Run the simulation for populations from 2 to 96 players. See figures 5 and 6 for the results.

Find that the overall mean is about 11.9 bids per player, growing roughly as the square of the number of players.

The time to converge grows more slowly, and at first decreases as the number of players increases from very small values. This is because with very few players it takes time to explore the space to find equilibrium, but with more players you can get there faster. Eventually you have so many players you get  overwhelmed by the volume of bids, so this doesn't help anymore. Even with 150 players it takes less than 2 minutes to converge.

Increasing epsilon reduces the number of bids to convergence from about 170 bids per player (epsilon = 5) to 120 (epsilon = 50), while the (attained total utility) - (maximal possible utility) varies from 5 to 10 over the same values (compared to a total possible of 1965 for epsilon = 0 or 1957 for epsilon = 50). So increasing epsilon doesn't seem to furt much, but likewise doesn't gain a reduce the bidding that much either.

For each player, the algorithm is:

1 Let **s_i = 0** and **s^_-i = 0**. Start an independent thread which receives updates to **s^_-i**
2 compute the truthful epsilon-best-reply of Proposition 1, **t_i in T_i intersected with S_i\[epsilon\](s^\_-i))**
3 if **u_i(t_i; s^\_-i) > u_i(s_i; s^\_-i) + epsilon**, send a bid **s_i = t_i**
4 sleep for 1 second
5 go to 2

This is a selfish and short-sighted algorithm. It's selfish because it only bids if it can improve its own utility. It's short-sighted because it doesn't employ history, and will not consider a temporary loss in favour of a future gain.

## Decentralised PSP for networked resources
Can expend the PSP to a set of resources **L = {1,...,_L_}** where each has a value **Q1,...,Ql**, and a set of players as before.

A fundamental goal is that the allocation at any node depends only on loacal information, the resources available at that node and the bids for that node only. This eliminates the need for communication between auctioneers, and makes the players responsible for co-ordinating their bids at the nodes on the route they are interested in to maximise their utility.

Player i's type now includes a *route*, **r_i**, which is a subset of **L**, as well as their valuation and budget. 'Route' in this context would naturally mean a set of connected netowrk paths, but that is not formally required, the player could bid separately on distinct elements of **L**. Nonetheless, we assume they are bidding for a connected path and care only about their total budget and the minimal thickness (allocation) of any element (i.e. their most restrictive path-segment).

In other words their utility **u_i(s)** is given by their valuation function **theta_i** applied to the minimim allocation along their route, minus their cost function **c_i(s)**

Ignore for now the possibilty of multi-path routing.

It can be shown that if the derivative of the demand function, **theta_i**, is strictly positive, then a bid is a best reply only if it results in the same allocation at all links on the route.

For each player _i_, define **x_i(s) = (z_i,y_i)** where:

* **z_i(l)** is the minimum allocation under **s** for all links in player _i_'s route, and
* **y_i(l)** is the maximum price under **s** for all links in player _i_'s route.

Can show that **u_i(x_i(s);s_-i) >= u_i(s)**. This is rather intuitive: if you're getting a minimum at some point along the route, there's no point in bidding for more elsewhere, you can't use it. Likewise, if you're offering less than your maximal price-per-unit somewhere, you may lose out and get a lower allocation on that link.

This establishes a key property, namely that each players best strategy is to bid consistently, i.e. place the same bid on all links in their path and bid zero on other links. We can show that we can restrict ourselves to consistent strategies and still have feasible best replies.

This means that within feasible sets, the embedded game (with many routes) is identical to the single-node game, barring a change of notation.

## Open questions:

* how to apply PSP to future reservations?
* evolutionary behaviour from long-term interaction between the same set of players?
* how to handle budgets in repeats of the game?