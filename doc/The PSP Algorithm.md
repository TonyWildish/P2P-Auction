
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

*u_i(s) = theta_i(a_i(s)) - c_i(s)*

Players can be constrained by a budget in the range 0 to infinity.

Assume players have elastic demand, by which we mean:

* **theta_i(0) = 0** - their demand for a quantity of zero is zero
* **theta_i** is differentiable
* the derivative of **theta_i** is >= 0, non-increasing, and continuous - in other words player *i* is willing to pay most for their first increment, and progressively less for greater and greater slices..
* as long as the valuation is strictly increasing it must also be strictly concave. However, it is allowed to flatten beyond some point.

This form of elastic demand is just the law of diminshing marginal returns by another name. It can also be justified from information-theoretic considerations, where the value of an allocation can be equated to the level of distortion in (e.g.) video-encoding, where the distortion increases as available bandwidth decreases. Shame that doesn't apply to LHC data-transfer :-(

## Equilibrium of the PSP
PSP can be analysed as a game **(Q,u_1,...u_i,A)** (i.e. the quantity being auctioned, the players' utility functions, and the allocation rule). It can be treated as a strategic game of complete information.

Players re-compute their best response to the current strategy profile of their opponents, this converges to the equilibrium.

A more general case for equilibrium is an **epsilon-Nash** equilibrium, where perfect equilibrium isn't reached but the players come within a small offset, *epsilon*, of the true Nash equilibrium. This can be interpreted as imposing a *bid-fee* on players, they are charged an amount *epsilon* to place a bid.





# From another paper...
A key property here is that each players best strategy is to bid consistently, i.e. place the same bid on all links in their path and bid zero on other links. We can show that we can restrict ourselves to consistent strategies and still have feasible best replies.

Can also show that if the derivative of the demand function, **theta_i**, is strictly positive, then a bid is a best reply only if it results in the same allocation at all links on the route.