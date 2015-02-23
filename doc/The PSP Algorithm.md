
# The algorithm in a nutshell:
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
- the sum over bidders of **a_*i*(s)** is less than the total, **_Q_** (you don't over-allocate the resource)
- for all bidders *i*, a_*i*(s) <= q_*i* (each bidder gets no more than they asked for)
- for all bidders *i*, c_*i*(s) <= p_*i* . q_*i* (the total cost does not exceed what each bidder is willing to pay)

N.B. A typical auction, in which one bidder gets the entire resource, has a_*i* = **_Q_** for one bidder and a_*i* = 0 for all other bidders.

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

Then we can define the **PSP Allocation Rule** as:
- **a_*i*(s)** = *minimum(* q_*i*, **Qbar_i(p_*i*,s_-i)** *)*
- **c_*i*(s)** = *sum over j != i of (* **a_*j*(0; s_-i)** - **a_*j*(s_i; s_-i)**

i.e.
- the allocation is the minimum of what the bidder asked for and what is left after all other bidders who bid more than bidder *i* get their allocation. Put more simply, bidder *i* gets what's left after higher-paying bidders are satisfied, up to the limit they requested.
- the cost they pay is the sum over all other bidders of the price the other bidder offerred times the difference between the actual allocation and the allocation they would have received if player *i* had not participated. Or, for all other bidders, add up the amount they lose because *i* exists multiplied by the price they were willing to pay, and charge *i* that amount.