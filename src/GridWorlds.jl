#################################################################
# This file implements the grid world problem as an MDP.
# In the problem, the agent is tasked with navigating in a
# stochatic environemnt. For example, when the agent chooses
# to go right, it may not always go right, but may go up, down
# or left with some probability. The agent's goal is to reach the
# reward states. The states with a positive reward are terminal,
# while the states with a negative reward are not.
#################################################################

#################################################################
# States and Actions
#################################################################
# state of the agent in grid world
type GridWorldState # this is not immutable because of how it is used in transition(), but maybe it should be
	x::Int64 # x position
	y::Int64 # y position
    done::Bool # entered the terminal reward state in previous step - there is only one terminal state
    GridWorldState(x,y,done) = new(x,y,done)
    GridWorldState() = new()
end
# simpler constructors
GridWorldState(x::Int64, y::Int64) = GridWorldState(x,y,false)
# for state comparison
function ==(s1::GridWorldState,s2::GridWorldState)
    if s1.done && s2.done
        return true
    elseif s1.done || s2.done
        return false
    else
        return posequal(s1, s2)
    end
end
# for hashing states in dictionaries in Monte Carlo Tree Search
posequal(s1::GridWorldState, s2::GridWorldState) = s1.x == s2.x && s1.y == s2.y
function hash(s::GridWorldState, h::UInt64 = zero(UInt64))
    if s.done
        return hash(s.done, h)
    else
        return hash(s.x, hash(s.y, h))
    end
end
Base.copy!(dest::GridWorldState, src::GridWorldState) = (dest.x=src.x; dest.y=src.y; dest.done=src.done; return dest)

# action taken by the agent indeicates desired travel direction
immutable GridWorldAction
    direction::Symbol
    GridWorldAction(d) = new(d)
    GridWorldAction() = new()
end 
==(u::GridWorldAction, v::GridWorldAction) = u.direction == v.direction
hash(a::GridWorldAction, h::UInt) = hash(a.direction, h)

#################################################################
# Grid World MDP
#################################################################
# the grid world mdp type
type GridWorld <: MDP{GridWorldState, GridWorldAction}
	size_x::Int64 # x size of the grid
	size_y::Int64 # y size of the grid
	reward_states::Vector{GridWorldState} # the states in which agent recieves reward
	reward_values::Vector{Float64} # reward values for those states
    bounds_penalty::Float64 # penalty for bumping the wall
    tprob::Float64 # probability of transitioning to the desired state
    terminals::Set{GridWorldState}
    discount_factor::Float64 # disocunt factor
    vec_state::Vector{Float64}
end
# we use key worded arguments so we can change any of the values we pass in 
function GridWorld(;sx::Int64=10, # size_x
                    sy::Int64=10, # size_y
                    rs::Vector{GridWorldState}=[GridWorldState(4,3), GridWorldState(4,6), GridWorldState(9,3), GridWorldState(8,8)],
                    rv::Vector{Float64}=[-10.,-5,10,3], 
                    penalty::Float64=-1.0, # bounds penalty
                    tp::Float64=0.7, # tprob
                    discount_factor::Float64=0.95)
    terminals = Set{GridWorldState}()
    for (i,v) in enumerate(rv)
        if v > 0.0
            push!(terminals, rs[i])
        end
    end
    return GridWorld(sx, sy, rs, rv, penalty, tp, terminals, discount_factor, zeros(2))
end

create_state(::GridWorld) = GridWorldState()
create_action(::GridWorld) = GridWorldAction()

#################################################################
# State and Action Spaces
#################################################################
# This could probably be implemented more efficiently without vectors

# state space
type GridWorldStateSpace <: AbstractSpace
    states::Vector{GridWorldState}
end
# action space
type GridWorldActionSpace <: AbstractSpace
    actions::Vector{GridWorldAction}
end
# returns the state space
function states(mdp::GridWorld)
	s = GridWorldState[] 
	size_x = mdp.size_x
	size_y = mdp.size_y
    for y = 1:mdp.size_y, x = 1:mdp.size_x
        push!(s, GridWorldState(x,y,false))
    end
    push!(s, GridWorldState(0, 0, true))
    return GridWorldStateSpace(s)
end
# returns the action space
function actions(mdp::GridWorld, s=nothing)
	acts = [GridWorldAction(:up), GridWorldAction(:down), GridWorldAction(:left), GridWorldAction(:right)]
	return GridWorldActionSpace(acts)
end
actions(mdp::GridWorld, s::GridWorldState, as::GridWorldActionSpace) = as;

# returns an iterator over states or action (arrays in this case)
iterator(space::GridWorldStateSpace) = space.states
iterator(space::GridWorldActionSpace) = space.actions

# sampling and mutating methods
rand(rng::AbstractRNG, space::GridWorldStateSpace, s::GridWorldState=GridWorldState(0,0)) = space.states[rand(rng, 1:end)]
rand(space::GridWorldStateSpace) = space.states[rand(1:end)]

rand(rng::AbstractRNG, space::GridWorldActionSpace, a::GridWorldAction=GridWorldAction(:up)) = space.actions[rand(rng,1:end)]
rand(space::GridWorldActionSpace) = space.actions[rand(1:end)]

#################################################################
# Distributions
#################################################################

type GridWorldDistribution <: AbstractDistribution
    neighbors::Array{GridWorldState}
    probs::Array{Float64} 
end

function create_transition_distribution(mdp::GridWorld)
    # can have at most five neighbors in grid world
    neighbors =  [GridWorldState(i,i) for i = 1:5]
    probabilities = zeros(5) + 1.0/5.0
    return GridWorldDistribution(neighbors, probabilities)
end

# returns an iterator over the distirubtion
function POMDPs.iterator(d::GridWorldDistribution)
    return d.neighbors
end

function pdf(d::GridWorldDistribution, s::GridWorldState)
    for (i, sp) in enumerate(d.neighbors)
        if s == sp
            return d.probs[i]
        end
    end   
    return 0.0
end

function rand(rng::AbstractRNG, d::GridWorldDistribution, s::GridWorldState=GridWorldState(0,0))
    cat = WeightVec(d.probs)
    d.neighbors[sample(rng, cat)]
end

n_states(mdp::GridWorld) = mdp.size_x*mdp.size_y+1
n_actions(mdp::GridWorld) = 4

#check for reward state
function reward(mdp::GridWorld, state::GridWorldState, action::GridWorldAction, sp::GridWorldState)
    if state.done
        return 0.0
    end
	r = 0.0
	reward_states = mdp.reward_states
	reward_values = mdp.reward_values
	n = length(reward_states)
	for i = 1:n
		if posequal(state, reward_states[i]) 
			r += reward_values[i]
		end
	end 
    if !inbounds(mdp, sp)
        r += mdp.bounds_penalty
    end
	return r
end

function reward(mdp::GridWorld, state::GridWorldState)
    @assert mdp.bounds_penalty == 0.0
	r = 0.0
	reward_states = mdp.reward_states
	reward_values = mdp.reward_values
	n = length(reward_states)
	for i = 1:n
		if posequal(state, reward_states[i]) 
			r += reward_values[i]
		end
	end 
    return r
end

#checking boundries- x,y --> points of current state
function inbounds(mdp::GridWorld,x::Int64,y::Int64)
	if 1 <= x <= mdp.size_x && 1 <= y <= mdp.size_y 
		return true 
	else 
		return false
	end
end

function inbounds(mdp::GridWorld,state::GridWorldState)
	x = state.x #point x of state
	y = state.y
	return inbounds(mdp, x, y)
end

function fill_probability!(p::Vector{Float64}, val::Float64, index::Int64)
	for i = 1:length(p)
		if i == index
			p[i] = val
		else
			p[i] = 0.0
		end
	end
end

function transition(mdp::GridWorld, state::GridWorldState, action::GridWorldAction, d::GridWorldDistribution)
	a = action.direction 
	x = state.x
	y = state.y 
    
    neighbors = d.neighbors
    probability = d.probs
    
    fill!(probability, 0.1)
    probability[5] = 0.0 

    neighbors[1].x = x+1; neighbors[1].y = y
    neighbors[2].x = x-1; neighbors[2].y = y
    neighbors[3].x = x; neighbors[3].y = y-1
    neighbors[4].x = x; neighbors[4].y = y+1
    neighbors[5].x = x; neighbors[5].y = y


    if state.done
        fill_probability!(probability, 1.0, 5)
        neighbors[5].done = true
        return d
    end

    for i = 1:5 neighbors[i].done = false end 
    reward_states = mdp.reward_states
    reward_values = mdp.reward_values
	n = length(reward_states)
	for i = 1:n
		#if state == reward_states[i] && reward_values[i] > 0.0
		if posequal(state, reward_states[i]) && reward_values[i] > 0.0
			fill_probability!(probability, 1.0, 5)
            neighbors[5].done = true
            return d
		end
	end 

    if a == :right  
		if !inbounds(mdp, neighbors[1])
			fill_probability!(probability, 1.0, 5)
		else
			probability[1] = 0.7
		end

	elseif a == :left
		if !inbounds(mdp, neighbors[2])
			fill_probability!(probability, 1.0, 5)
		else
			probability[2] = 0.7
		end

	elseif a == :down
		if !inbounds(mdp, neighbors[3])
			fill_probability!(probability, 1.0, 5)
		else
			probability[3] = 0.7
		end

	elseif a == :up 
		if !inbounds(mdp, neighbors[4])
			fill_probability!(probability, 1.0, 5)
		else
			probability[4] = 0.7 
		end
	end

    count = 0
    new_probability = 0.1
    
    for i = 1:length(neighbors)
        if !inbounds(mdp, neighbors[i])
         count += 1
            probability[i] = 0.0
         end
     end
 
    if count == 1 
        new_probability = 0.15
    elseif count == 2
        new_probability = 0.3
    end 
    
    if count > 0 
        for i = 1:length(neighbors)
            if probability[i] == 0.1
               probability[i] = new_probability
            end
        end
    end
    d
end


function state_index(mdp::GridWorld, s::GridWorldState)
    return s2i(mdp, s)
end

function s2i(mdp::GridWorld, state::GridWorldState)
    if state.done
        return mdp.size_x*mdp.size_y + 1
    else
        return sub2ind((mdp.size_x, mdp.size_y), state.x, state.y)
    end
end 


function isterminal(mdp::GridWorld, s::GridWorldState)
    return s.done
end

discount(mdp::GridWorld) = mdp.discount_factor

#XXX It doesn't seem like a good idea to have vec_state as a member of the mdp to me (zsunberg)
function vec(mdp::GridWorld, s::GridWorldState)
    mdp.vec_state[1] = s.x
    mdp.vec_state[2] = s.y
    return mdp.vec_state
end

initial_state(mdp::GridWorld, rng::AbstractRNG) = GridWorldState(rand(rng, 1:mdp.size_x), rand(rng, 1:mdp.size_y))

# Visualization

#=
function colorval(val, brightness::Real = 1.0)
  val = convert(Vector{Float64}, val)
  x = 255 - min(255, 255 * (abs(val) ./ 10.0) .^ brightness)
  r = 255 * ones(size(val))
  g = 255 * ones(size(val))
  b = 255 * ones(size(val))
  r[val .>= 0] = x[val .>= 0]
  b[val .>= 0] = x[val .>= 0]
  g[val .< 0] = x[val .< 0]
  b[val .< 0] = x[val .< 0]
  (r, g, b)
end

function plot(g::GridWorld, f::Function)
  V = map(f, g.S)
  plot(g, V)
end

function plot(obj::GridWorld, V::Vector; curState=0)
  o = IOBuffer()
  sqsize = 1.0
  twid = 0.05
  (r, g, b) = colorval(V)
  for s = obj.S
    (yval, xval) = s2xy(s)
    yval = 10 - yval
    println(o, "\\definecolor{currentcolor}{RGB}{$(r[s]),$(g[s]),$(b[s])}")
    println(o, "\\fill[currentcolor] ($((xval-1) * sqsize),$((yval) * sqsize)) rectangle +($sqsize,$sqsize);")
    if s == curState
      println(o, "\\fill[orange] ($((xval-1) * sqsize),$((yval) * sqsize)) rectangle +($sqsize,$sqsize);")
    end
    vs = @sprintf("%0.2f", V[s])
    println(o, "\\node[above right] at ($((xval-1) * sqsize), $((yval) * sqsize)) {\$$(vs)\$};")
  end
  println(o, "\\draw[black] grid(10,10);")
  tikzDeleteIntermediate(false)
  TikzPicture(takebuf_string(o), options="scale=1.25")
end

function plot(g::GridWorld, f::Function, policy::Function; curState=0)
  V = map(f, g.S)
  plot(g, V, policy, curState=curState)
end

function plot(obj::GridWorld, V::Vector, policy::Function; curState=0)
  P = map(policy, obj.S)
  plot(obj, V, P, curState=curState)
end

function plot(obj::GridWorld, V::Vector, policy::Vector; curState=0)
  o = IOBuffer()
  sqsize = 1.0
  twid = 0.05
  (r, g, b) = colorval(V)
  for s in obj.S
    (yval, xval) = s2xy(s)
    yval = 10 - yval
    println(o, "\\definecolor{currentcolor}{RGB}{$(r[s]),$(g[s]),$(b[s])}")
    println(o, "\\fill[currentcolor] ($((xval-1) * sqsize),$((yval) * sqsize)) rectangle +($sqsize,$sqsize);")
    if s == curState
      println(o, "\\fill[orange] ($((xval-1) * sqsize),$((yval) * sqsize)) rectangle +($sqsize,$sqsize);")
    end
  end
  println(o, "\\begin{scope}[fill=gray]")
  for s in obj.S
    (yval, xval) = s2xy(s)
    yval = 10 - yval + 1
    c = [xval, yval] * sqsize - sqsize / 2
    C = [c'; c'; c']'
    RightArrow = [0 0 sqsize/2; twid -twid 0]
    if policy[s] == :left
      A = [-1 0; 0 -1] * RightArrow + C
      println(o, "\\fill ($(A[1]), $(A[2])) -- ($(A[3]), $(A[4])) -- ($(A[5]), $(A[6])) -- cycle;")
    end
    if policy[s] == :right
      A = RightArrow + C
      println(o, "\\fill ($(A[1]), $(A[2])) -- ($(A[3]), $(A[4])) -- ($(A[5]), $(A[6])) -- cycle;")
    end
    if policy[s] == :up
      A = [0 -1; 1 0] * RightArrow + C
      println(o, "\\fill ($(A[1]), $(A[2])) -- ($(A[3]), $(A[4])) -- ($(A[5]), $(A[6])) -- cycle;")
    end
    if policy[s] == :down
      A = [0 1; -1 0] * RightArrow + C
      println(o, "\\fill ($(A[1]), $(A[2])) -- ($(A[3]), $(A[4])) -- ($(A[5]), $(A[6])) -- cycle;")
    end

    vs = @sprintf("%0.2f", V[s])
    println(o, "\\node[above right] at ($((xval-1) * sqsize), $((yval-1) * sqsize)) {\$$(vs)\$};")
  end
  println(o, "\\end{scope}");
  println(o, "\\draw[black] grid(10,10);");
  TikzPicture(takebuf_string(o), options="scale=1.25")
end
=#
