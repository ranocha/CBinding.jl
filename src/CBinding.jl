module CBinding
	import Libdl
	using Todo: @todo_str
	
	
	export Clongdouble, Caggregate, Cstruct, Cunion, Carray, Cenum, Clibrary, Cglobal, Cglobalconst, Cfunction, Cconvention, Calignment, Cconst, Caccessor
	export STDCALL, CDECL, FASTCALL, THISCALL
	export @ctypedef, @cstruct, @cunion, @carray, @calign, @cenum, @cextern, @cbindings
	export propertytypes
	
	
	# in auto-generated bindings, macros can be used to avoid naming conflicts between Julia and C, so `@CBinding().include(...)` will not conflict with `include(...)`
	macro CBinding() return @__MODULE__ end
	
	
	# provide a temporary placeholder for 128-bit floating point primitive
	primitive type Clongdouble <: AbstractFloat sizeof(Cdouble)*2*8 end
	
	
	abstract type Cstruct end
	abstract type Cunion end
	const Caggregate = Union{Cstruct, Cunion}
	
	abstract type Cenum <: Integer end
	
	const Copaques = Union{Caggregate, Cenum}
	
	struct Cconst{T, S}
		mem::NTuple{S, UInt8}
		
		Cconst{T}(x::NTuple{X, UInt8}) where {T, X} = new{T, sizeof(T)}(x)
	end
	
	
	# alignment strategies
	struct Calignment{SymT}
	end
	
	const ALIGN_NATIVE = Calignment{:native}
	const ALIGN_PACKED = Calignment{:packed}
	
	
	# calling conventions
	struct Cconvention{SymT}
	end
	
	const STDCALL  = Cconvention{:stdcall}
	const CDECL    = Cconvention{:cdecl}
	const FASTCALL = Cconvention{:fastcall}
	const THISCALL = Cconvention{:thiscall}
	
	
	include("ctypespec.jl")
	include("clibrary.jl")
	include("cbindings.jl")
	include("cenum.jl")
	include("carray.jl")
	include("cconst.jl")
	include("caggregate.jl")
	include("cglobal.jl")
	include("cfunction.jl")
	include("cetc.jl")
	include("ctypelayout.jl")
	include("caccessor.jl")
end
