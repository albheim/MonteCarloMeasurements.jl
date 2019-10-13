import Base.Cartesian.@ntuple

const ParticleArray = AbstractArray{<:AbstractParticles}
const SomeKindOfParticles = Union{<:MonteCarloMeasurements.AbstractParticles, ParticleArray}


nparticles(p) = length(p)
nparticles(p::ParticleArray) = length(eltype(p))
nparticles(p::Type{<:ParticleArray}) = length(eltype(p))

vecindex(p,i) = getindex(p,i)
vecindex(p::ParticleArray,i) = getindex.(p,i)

function indexof_particles(ntt::Type{<:NamedTuple})
    inds = findall(ft -> ft <: SomeKindOfParticles, fieldtypes(ntt))
    (inds...,)
    # TODO: test all same number of particles
end

function indexof_particles(args)
    inds = findall([a <: SomeKindOfParticles for a in args])
    inds === nothing && throw(ArgumentError("At least one argument should be <: AbstractParticles. If particles appear nested as fields inside an argument, see `with_workspace` and `Workspace`"))
    all(nparticles(a) == nparticles(args[inds[1]]) for a in args[inds]) || throw(ArgumentError("All p::Particles must have the same number of particles."))
    (inds...,)
    # TODO: test all same number of particles
end

@generated function Ngetter(nt::NamedTuple)
    inds = indexof_particles(nt)
    N = nparticles(fieldtypes(nt)[inds[1]])
    :($N)
end

@generated function Ngetter(args...)
    nargs = length(args)
    inds = indexof_particles(args)
    N = nparticles(args[inds[1]])
    :($N)
end

function arggetter(i,ntt::Type{NamedTuple})
    inds = indexof_particles(ntt)
    nargs = fieldcount(ntt)
    quote
        args = fieldnames(typeof(ntt))
        (;Pair.(args, @ntuple $nargs j->j ∈ $inds ? vecindex(getfield(ntt,args[j]),i) : getfield(ntt,args[j]))...) # Must interpolate in vars that were created outside of the quote, but not arguments to the generated function
    end
end

function arggetter(i,a::SomeKindOfParticles)
    vecindex(a,i)
end

function arggetter(i,a)
    a
end

macro bymap(ex)
    @capture(ex, f_(args__)) || error("expected a function call")
    fsym = string(f)
    nargs = length(args)
    quote
        N = Ngetter($(esc.(args)...))
        individuals = map(1:N) do i
            eargs = ($(esc.(args)...),)
            argsi = ntuple(j->arggetter(i,eargs[j]), $nargs)
            $(esc(f))(argsi...)
        end
        if ndims(individuals[1]) == 0
            Particles(individuals)
        elseif ndims(individuals[1]) == 1
            Particles(copy(reduce(hcat,individuals)'))
        elseif ndims(individuals[1]) == 2
            reshape(Particles(copy(reduce(hcat,vec.(individuals))')), size(individuals[1])...)
        else
            error("Output with dimension >2 is currently not supported by `@bymap`. Consider if `ℝⁿ2ℝⁿ_function($($fsym), $($args...))` works for your use case.")
        end
    end
end


macro bypmap(ex)
    @capture(ex, f_(args__)) || error("expected a function call")
    fsym = string(f)
    nargs = length(args)
    quote
        N = Ngetter($(esc.(args)...))
        individuals = pmap(1:N) do i
            eargs = ($(esc.(args)...),)
            argsi = ntuple(j->arggetter(i,eargs[j]), $nargs)
            $(esc(f))(argsi...)
        end
        if ndims(individuals[1]) == 0
            Particles(individuals)
        elseif ndims(individuals[1]) == 1
            Particles(copy(reduce(hcat,individuals)'))
        elseif ndims(individuals[1]) == 2
            reshape(Particles(copy(reduce(hcat,vec.(individuals))')), size(individuals[1])...)
        else
            error("Output with dimension >2 is currently not supported by `@bymap`. Consider if `ℝⁿ2ℝⁿ_function($($fsym), $($args...))` works for your use case.")
        end
    end
end
