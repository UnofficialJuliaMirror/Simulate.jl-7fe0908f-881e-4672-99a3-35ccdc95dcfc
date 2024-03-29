#
# routines for handling functions as processes
#

"""
    loop(p::SimProcess, start::Channel, cycles::Number)

Put a `SimProcess` in a loop, which can be broken by a `SimException`.

# Arguments
- `p::SimProcess`:
- `start::Channel`:
- `cycles=Inf`:
"""
function loop(p::SimProcess, start::Channel, cycles::Number)
    take!(start)
    while cycles > 0
        try
            p.func(p.arg...; p.kw...)
        catch exc
            if isa(exc, SimException)
                exc.ev == Stop() ? break : nothing
            end
            rethrow(exc)
        end
        cycles -= 1
    end
    p.sim.processes = delete!(p.sim.processes, p.id)
end

"""
    startup!(p::SimProcess)

Start a `SimProcess` as a task in a loop.
"""
function startup!(p::SimProcess, cycles::Number)
    start = Channel(0)
    p.task = @async loop(p, start, cycles)
    p.state = Idle()
    put!(start, 1) # let the process start
end

"""
```
process!(sim::Clock, p::SimProcess, cycles=Inf)
process!(p::SimProcess, cycles=Inf)
```
Register a `SimProcess` to a clock, start it as an asynchronous process and
return the `id` it was registered with. It can then be found under `sim.processes[id]`.

# Arguments
- `sim::Clock`: clock, if no clock is given, it runs under 𝐶,
- `p::SimProcess`
- `cycles::Number=Inf`: number of cycles, the process should run.
"""
function process!(sim::Clock, p::SimProcess, cycles::Number=Inf)
    id = p.id
    while haskey(sim.processes, id)
        if isa(id, Float64)
            id = nextfloat(id)
        elseif isa(id, Int)
            id += 1
        elseif isa(id, String)
            s = split(id, "#")
            id = length(s) > 1 ? chop(id)*string(s[end][end]+1) : id*"#1"
        else
            throw(ArgumentError("process id $id is duplicate, cannot convert!"))
        end
    end
    sim.processes[id] = p
    p.id = id
    p.sim = sim
    startup!(p, cycles)
    id
end
process!(p::SimProcess, cycles=Inf) = process!(𝐶, p, cycles)


"stop a SimProcess"
function step!(p::SimProcess, ::Idle, ::Stop)
    schedule(p.task, SimException(Stop()))
    yield()
    p.state = Halted()
end

"""
```
delay!(sim::Clock, t::Number)
delay!(t::Number)
```
Delay a process for a time interval `t` on the clock `sim`. Suspend the calling
process until being reactivated by the clock at the appropriate time.

# Arguments
- `sim::Clock`: clock, if no clock is given, the delay goes to `𝐶`.
- `t::Number`: the time interval for the delay.
"""
function delay!(sim::Clock, t::Number)
    c = Channel(0)
    event!(sim, SF(put!, c, t), after, t)
    take!(c)
end
delay!(t::Number) = delay!(𝐶, t)

"""
```
wait!(sim::Clock, cond::Union{SimExpr, Array, Tuple}; scope::Module=Main)
wait!(cond::Union{SimExpr, Array, Tuple}; scope::Module=Main)
```
Wait on a clock for a condition to become true. Suspend the calling process
until the given condition is true.

# Arguments
- `sim::Clock`: clock, if no clock is given, the delay goes to `𝐶`.
- `cond::Union{SimExpr, Array, Tuple}`: a condition is an expression or SimFunction
    or an array or tuple of them. It is true if all expressions or SimFunctions
    therein return true.
- `scope::Module=Main`: evaluation scope for given expressions
"""
function wait!(sim::Clock, cond::Union{SimExpr, Array, Tuple}; scope::Module=Main)
    if all(simExec(sconvert(cond)))   # all conditions met
        return         # return immediately
    else
        c = Channel(0)
        event!(sim, SF(put!, c, 1), cond, scope=scope)
        take!(c)
    end
end
wait!(cond::Union{SimExpr, Array, Tuple}; scope::Module=Main) = wait!(𝐶, cond, scope=scope)

"""
    interrupt!(p::SimProcess, ev::SEvent, value=nothing)

Interrupt a `SimProcess` by throwing a `SimException` to it.
"""
function interrupt!(p::SimProcess, ev::SEvent, value=nothing)
    schedule(p.task, SimException(ev, value), error=true)
    yield()
end

"Stop a SimProcess"
stop!(p::SimProcess, value=nothing) = interrupt!(p, Stop(), value)

"""
```
now!(sim::Clock, ex::Union{SimExpr, Array, Tuple})
now!(ex::Union{SimExpr, Array, Tuple})
```
Lock the clock, execute the given expression, then unlock the clock again.

# Arguments
- `sim::Clock`:
- `ex::Union{SimExpr, Array, Tuple}`:
"""
function now!(sim::Clock, ex::Union{SimExpr, Array, Tuple})
    lock(sim.lock)
    simExec(sconvert(ex))
    unlock(sim.lock)
end
now!(ex::Union{SimExpr, Array, Tuple}) = now!(𝐶, ex)
