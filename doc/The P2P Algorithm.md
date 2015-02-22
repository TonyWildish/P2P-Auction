
# The algorithm in a nutshell:
Let **_Q_** be the network bandwidth that is 

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
- the sum over bidders of **a_*i*(s)** is less than the total, **_Q_**
- for all bidders *i*, **a_*i*(s) <= q_*i*
- for all bidders *i*, **c_*i*(s) <= p_*i* . q_*i* **